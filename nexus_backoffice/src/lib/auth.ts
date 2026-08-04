import 'server-only';
import { redirect } from 'next/navigation';
import { supabaseServer } from './supabase/server';
import { supabaseAdmin } from './supabase/admin';

export type AdminSesion = { userId: string; email: string };

/**
 * Devuelve la sesión si el usuario está autenticado Y su email está en
 * `admin_allowlist` (o es el bootstrap del .env). Si no, null.
 *
 * La verificación se hace SIEMPRE en el servidor: el cliente nunca
 * decide si alguien es admin.
 */
export async function obtenerSesionAdmin(): Promise<AdminSesion | null> {
  const sb = supabaseServer();
  const {
    data: { user },
  } = await sb.auth.getUser();
  if (!user?.email) return null;

  const email = user.email.toLowerCase();

  // Respaldo por si la migración 0017 aún no se aplicó.
  const bootstrap = (process.env.ADMIN_EMAIL_BOOTSTRAP ?? '').toLowerCase();
  if (bootstrap && email === bootstrap) {
    return { userId: user.id, email };
  }

  try {
    const { data } = await supabaseAdmin()
      .from('admin_allowlist')
      .select('email, activo')
      .ilike('email', email)
      .maybeSingle();
    if (data?.activo) return { userId: user.id, email };
  } catch {
    // Tabla inexistente: solo vale el bootstrap (ya evaluado arriba).
  }
  return null;
}

/** Igual que la anterior, pero redirige al login si no hay permiso. */
export async function requerirAdmin(): Promise<AdminSesion> {
  const sesion = await obtenerSesionAdmin();
  if (!sesion) redirect('/login?motivo=no-autorizado');
  return sesion;
}

/** ¿Este email puede pedir un código de acceso? (pre-chequeo del login) */
export async function emailAutorizado(email: string): Promise<boolean> {
  const e = email.trim().toLowerCase();
  if (!e) return false;
  const bootstrap = (process.env.ADMIN_EMAIL_BOOTSTRAP ?? '').toLowerCase();
  if (bootstrap && e === bootstrap) return true;
  try {
    const { data } = await supabaseAdmin()
      .from('admin_allowlist')
      .select('activo')
      .ilike('email', e)
      .maybeSingle();
    return data?.activo === true;
  } catch {
    return false;
  }
}
