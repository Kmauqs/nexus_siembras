'use server';

import { revalidatePath } from 'next/cache';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { obtenerSesionAdmin } from '@/lib/auth';

export type ResultadoAccion = { ok: boolean; mensaje: string };

/** Ban largo (~100 años) = soft-delete: el usuario no puede iniciar sesión. */
const BAN_SOFT_DELETE = '876600h';

async function verificarAdminYEmail(
  userId: string,
  emailConfirmacion: string
): Promise<
  | { ok: true; sesion: { userId: string; email: string }; emailReal: string }
  | { ok: false; mensaje: string }
> {
  const sesion = await obtenerSesionAdmin();
  if (!sesion) return { ok: false, mensaje: 'No autorizado.' };
  if (userId === sesion.userId) {
    return {
      ok: false,
      mensaje: 'No puedes eliminar tu propia cuenta desde el panel.',
    };
  }

  const sb = supabaseAdmin();
  const { data: userData, error: errUser } =
    await sb.auth.admin.getUserById(userId);
  if (errUser || !userData?.user) {
    return { ok: false, mensaje: 'Usuario no encontrado.' };
  }
  const emailReal = (userData.user.email ?? '').toLowerCase();
  if (emailReal !== emailConfirmacion.trim().toLowerCase()) {
    return {
      ok: false,
      mensaje: 'El correo escrito no coincide con el del usuario.',
    };
  }
  return { ok: true, sesion, emailReal };
}

/**
 * Soft-delete: mueve el usuario a papelera y lo banea (no puede entrar).
 * Los datos privados se conservan hasta el borrado definitivo.
 */
export async function moverAPapelera(
  userId: string,
  emailConfirmacion: string,
  motivo?: string
): Promise<ResultadoAccion> {
  const check = await verificarAdminYEmail(userId, emailConfirmacion);
  if (!check.ok) return check;

  const sb = supabaseAdmin();
  const { data: ya } = await sb
    .from('usuarios_papelera')
    .select('user_id')
    .eq('user_id', userId)
    .maybeSingle();
  if (ya) {
    return { ok: false, mensaje: 'Ese usuario ya está en la papelera.' };
  }

  const [predios, lotes, cultivos, feedbacks] = await Promise.all([
    sb.from('predios').select('id', { count: 'exact', head: true })
      .eq('owner_id', userId).is('deleted_at', null),
    sb.from('lotes').select('id', { count: 'exact', head: true })
      .eq('owner_id', userId).is('deleted_at', null),
    sb.from('cultivos').select('id', { count: 'exact', head: true })
      .eq('owner_id', userId).is('deleted_at', null),
    sb.from('feedback_encuestas').select('id', { count: 'exact', head: true })
      .eq('user_id', userId),
  ]);

  const snapshot = {
    predios: predios.count ?? 0,
    lotes: lotes.count ?? 0,
    cultivos: cultivos.count ?? 0,
    feedbacks: feedbacks.count ?? 0,
  };

  const { error: errInsert } = await sb.from('usuarios_papelera').insert({
    user_id: userId,
    email: check.emailReal,
    snapshot,
    motivo: motivo?.trim() || null,
    eliminado_por: check.sesion.userId,
  });
  if (errInsert) {
    return {
      ok: false,
      mensaje:
        `No se pudo registrar en papelera: ${errInsert.message}. ` +
        '¿Aplicaste la migración 0019?',
    };
  }

  const { error: errBan } = await sb.auth.admin.updateUserById(userId, {
    ban_duration: BAN_SOFT_DELETE,
  });
  if (errBan) {
    await sb.from('usuarios_papelera').delete().eq('user_id', userId);
    return {
      ok: false,
      mensaje: `No se pudo suspender la cuenta: ${errBan.message}`,
    };
  }

  revalidatePath('/admin/usuarios');
  revalidatePath('/admin/usuarios/papelera');
  revalidatePath('/admin');
  return {
    ok: true,
    mensaje:
      `${check.emailReal} movido a la papelera. Puede recuperarse o ` +
      'eliminarse definitivamente desde allí.',
  };
}

/** Quita el ban y saca al usuario de la papelera. */
export async function recuperarUsuario(
  userId: string
): Promise<ResultadoAccion> {
  const sesion = await obtenerSesionAdmin();
  if (!sesion) return { ok: false, mensaje: 'No autorizado.' };

  const sb = supabaseAdmin();
  const { data: fila, error: errFila } = await sb
    .from('usuarios_papelera')
    .select('email')
    .eq('user_id', userId)
    .maybeSingle();
  if (errFila || !fila) {
    return { ok: false, mensaje: 'Usuario no encontrado en la papelera.' };
  }

  const { error: errUnban } = await sb.auth.admin.updateUserById(userId, {
    ban_duration: 'none',
  });
  if (errUnban) {
    return {
      ok: false,
      mensaje: `No se pudo reactivar la cuenta: ${errUnban.message}`,
    };
  }

  const { error: errDel } = await sb
    .from('usuarios_papelera')
    .delete()
    .eq('user_id', userId);
  if (errDel) {
    return {
      ok: false,
      mensaje: `Cuenta reactivada, pero no se limpió la papelera: ${errDel.message}`,
    };
  }

  revalidatePath('/admin/usuarios');
  revalidatePath('/admin/usuarios/papelera');
  revalidatePath('/admin');
  return {
    ok: true,
    mensaje: `${fila.email} recuperado: ya puede iniciar sesión de nuevo.`,
  };
}

/**
 * Borrado definitivo desde la papelera (o con confirmación de email).
 * Anonimiza patrimonio comunitario y borra auth.users → CASCADE privado.
 */
export async function eliminarUsuarioDefinitivo(
  userId: string,
  emailConfirmacion: string
): Promise<ResultadoAccion> {
  const check = await verificarAdminYEmail(userId, emailConfirmacion);
  if (!check.ok) return check;

  const sb = supabaseAdmin();

  const { error: errVar } = await sb
    .from('variedades_comunitarias')
    .update({ created_by: null })
    .eq('created_by', userId);
  if (errVar) {
    return {
      ok: false,
      mensaje: `No se pudo anonimizar variedades: ${errVar.message}`,
    };
  }

  const { error: errPat } = await sb
    .from('patologias_reportadas')
    .update({ owner_id: null, cliente_id: null })
    .eq('owner_id', userId);
  if (errPat) {
    return {
      ok: false,
      mensaje: `No se pudo anonimizar reportes: ${errPat.message}`,
    };
  }

  // Quitar de papelera antes del CASCADE (FK ON DELETE CASCADE también lo haría).
  await sb.from('usuarios_papelera').delete().eq('user_id', userId);

  const { error } = await sb.auth.admin.deleteUser(userId);
  if (error) {
    return {
      ok: false,
      mensaje:
        `No se pudo eliminar la cuenta: ${error.message}. ` +
        'Verifica que la migración 0015 (FKs a auth.users) esté aplicada.',
    };
  }

  revalidatePath('/admin/usuarios');
  revalidatePath('/admin/usuarios/papelera');
  revalidatePath('/admin');
  revalidatePath('/');
  return {
    ok: true,
    mensaje:
      `Cuenta ${check.emailReal} eliminada definitivamente. Variedades y ` +
      'reportes de patologías se conservan anónimos en la comunidad.',
  };
}

/** @deprecated Usar moverAPapelera — se mantiene por si queda algún import. */
export async function eliminarUsuario(
  userId: string,
  emailConfirmacion: string
): Promise<ResultadoAccion> {
  return moverAPapelera(userId, emailConfirmacion);
}
