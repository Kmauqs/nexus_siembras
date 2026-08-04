'use server';

import { revalidatePath } from 'next/cache';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { obtenerSesionAdmin } from '@/lib/auth';

export type Resultado = { ok: boolean; mensaje: string };

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/** Guarda un parámetro de `app_config` con validación por tipo. */
export async function guardarParametro(
  clave: string,
  valor: string,
  tipo: string
): Promise<Resultado> {
  const sesion = await obtenerSesionAdmin();
  if (!sesion) return { ok: false, mensaje: 'No autorizado.' };

  const v = valor.trim();
  if (tipo === 'email' && !EMAIL_RE.test(v)) {
    return { ok: false, mensaje: 'Correo con formato inválido.' };
  }
  if (tipo === 'numero' && !Number.isFinite(Number(v))) {
    return { ok: false, mensaje: 'Debe ser un número.' };
  }
  if (tipo === 'bool' && !['true', 'false'].includes(v)) {
    return { ok: false, mensaje: 'Debe ser verdadero o falso.' };
  }

  const sb = supabaseAdmin();
  const { error } = await sb
    .from('app_config')
    .update({
      valor: v,
      updated_at: new Date().toISOString(),
      updated_by: sesion.userId,
    })
    .eq('clave', clave);
  if (error) return { ok: false, mensaje: error.message };

  // El email del desarrollador también alimenta las notificaciones de
  // feedback: se replica en `feedback_config` para el webhook.
  if (clave === 'email_desarrollador') {
    await sb
      .from('feedback_config')
      .update({ email_notificacion: v, updated_at: new Date().toISOString() })
      .eq('id', 1);
  }
  if (clave === 'feedback_notificar') {
    await sb
      .from('feedback_config')
      .update({ notificar_activo: v === 'true' })
      .eq('id', 1);
  }

  revalidatePath('/admin/config');
  revalidatePath('/');
  return { ok: true, mensaje: 'Parámetro actualizado.' };
}

/** Alta/baja de administradores del backoffice. */
export async function guardarAdmin(
  email: string,
  activo: boolean,
  nombre?: string
): Promise<Resultado> {
  const sesion = await obtenerSesionAdmin();
  if (!sesion) return { ok: false, mensaje: 'No autorizado.' };

  const e = email.trim().toLowerCase();
  if (!EMAIL_RE.test(e)) {
    return { ok: false, mensaje: 'Correo con formato inválido.' };
  }
  if (e === sesion.email && !activo) {
    return {
      ok: false,
      mensaje: 'No puedes desactivar tu propio acceso (quedarías fuera).',
    };
  }

  const { error } = await supabaseAdmin()
    .from('admin_allowlist')
    .upsert(
      { email: e, activo, nombre: nombre?.trim() || null },
      { onConflict: 'email' }
    );
  if (error) return { ok: false, mensaje: error.message };

  revalidatePath('/admin/config');
  return {
    ok: true,
    mensaje: activo ? `${e} puede acceder al panel.` : `${e} desactivado.`,
  };
}
