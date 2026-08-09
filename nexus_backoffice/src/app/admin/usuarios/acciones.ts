'use server';

import { revalidatePath } from 'next/cache';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { supabaseServer } from '@/lib/supabase/server';
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

  // Auth Admin API requiere service_role (no hay equivalente con JWT de usuario).
  const { data: userData, error: errUser } =
    await supabaseAdmin().auth.admin.getUserById(userId);
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
 * Papelera: JWT + RLS (es_admin). Ban: Auth Admin API (service_role).
 */
export async function moverAPapelera(
  userId: string,
  emailConfirmacion: string,
  motivo?: string
): Promise<ResultadoAccion> {
  const check = await verificarAdminYEmail(userId, emailConfirmacion);
  if (!check.ok) return check;

  const sbSesion = supabaseServer();
  const sbAdmin = supabaseAdmin();

  const { data: ya, error: errYa } = await sbSesion
    .from('usuarios_papelera')
    .select('user_id')
    .eq('user_id', userId)
    .maybeSingle();
  if (errYa) {
    return {
      ok: false,
      mensaje:
        `No se pudo consultar la papelera: ${errYa.message}. ` +
        '¿Aplicaste las migraciones 0019 y 0020?',
    };
  }
  if (ya) {
    return { ok: false, mensaje: 'Ese usuario ya está en la papelera.' };
  }

  // Conteos de datos ajenos: RLS de predios/lotes no deja verlos al admin
  // por JWT → service_role solo para el snapshot informativo.
  const [predios, lotes, cultivos, feedbacks] = await Promise.all([
    sbAdmin.from('predios').select('id', { count: 'exact', head: true })
      .eq('owner_id', userId).is('deleted_at', null),
    sbAdmin.from('lotes').select('id', { count: 'exact', head: true })
      .eq('owner_id', userId).is('deleted_at', null),
    sbAdmin.from('cultivos').select('id', { count: 'exact', head: true })
      .eq('owner_id', userId).is('deleted_at', null),
    sbSesion.from('feedback_encuestas').select('id', { count: 'exact', head: true })
      .eq('user_id', userId),
  ]);

  const snapshot = {
    predios: predios.count ?? 0,
    lotes: lotes.count ?? 0,
    cultivos: cultivos.count ?? 0,
    feedbacks: feedbacks.count ?? 0,
  };

  const { error: errInsert } = await sbSesion.from('usuarios_papelera').insert({
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
        '¿Aplicaste la migración 0019/0020?',
    };
  }

  const { error: errBan } = await sbAdmin.auth.admin.updateUserById(userId, {
    ban_duration: BAN_SOFT_DELETE,
  });
  if (errBan) {
    const { error: errRollback } = await sbSesion
      .from('usuarios_papelera')
      .delete()
      .eq('user_id', userId);
    return {
      ok: false,
      mensaje:
        `No se pudo suspender la cuenta: ${errBan.message}` +
        (errRollback ? ` (rollback papelera: ${errRollback.message})` : ''),
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

  const sbSesion = supabaseServer();
  const { data: fila, error: errFila } = await sbSesion
    .from('usuarios_papelera')
    .select('email')
    .eq('user_id', userId)
    .maybeSingle();
  if (errFila || !fila) {
    return { ok: false, mensaje: 'Usuario no encontrado en la papelera.' };
  }

  const { error: errUnban } = await supabaseAdmin().auth.admin.updateUserById(
    userId,
    { ban_duration: 'none' }
  );
  if (errUnban) {
    return {
      ok: false,
      mensaje: `No se pudo reactivar la cuenta: ${errUnban.message}`,
    };
  }

  const { error: errDel } = await sbSesion
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
 * Borrado definitivo vía RPC `admin_eliminar_usuario` (es_admin en BD).
 * Anonimiza patrimonio comunitario y borra auth.users → CASCADE privado.
 */
export async function eliminarUsuarioDefinitivo(
  userId: string,
  emailConfirmacion: string
): Promise<ResultadoAccion> {
  const check = await verificarAdminYEmail(userId, emailConfirmacion);
  if (!check.ok) return check;

  // JWT del admin → la RPC vuelve a verificar es_admin() (capa BD).
  const { data, error } = await supabaseServer().rpc('admin_eliminar_usuario', {
    p_user_id: userId,
  });

  if (error) {
    return {
      ok: false,
      mensaje:
        `No se pudo eliminar la cuenta: ${error.message}. ` +
        'Verifica migraciones 0015/0018 (FKs y patrimonio comunitario).',
    };
  }

  const ok = data && typeof data === 'object' && (data as { ok?: boolean }).ok;
  if (!ok) {
    return {
      ok: false,
      mensaje: 'La RPC no confirmó el borrado. Revisa los logs de Supabase.',
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

/** @deprecated Usar moverAPapelera. */
export async function eliminarUsuario(
  userId: string,
  emailConfirmacion: string
): Promise<ResultadoAccion> {
  return moverAPapelera(userId, emailConfirmacion);
}
