'use server';

import { headers } from 'next/headers';
import { supabaseServer } from '@/lib/supabase/server';
import { emailAutorizado } from '@/lib/auth';
import { obtenerConfig } from '@/lib/datos';

export type ResultadoLogin = { ok: boolean; mensaje: string };

/** Origen público de la app (local o Netlify) para el redirect del magic link. */
function origenApp(): string {
  const h = headers();
  const host = h.get('x-forwarded-host') ?? h.get('host');
  const proto = h.get('x-forwarded-proto') ?? 'http';
  if (host) return `${proto}://${host}`;
  return process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000';
}

/**
 * Solicita el magic link por defecto de Supabase (plantilla Magic Link).
 *
 * Compatible con el plan gratuito: no hace falta personalizar el template
 * ni usar el código de 6 dígitos. `shouldCreateUser: false` evita cuentas
 * nuevas. La respuesta es deliberadamente la misma con email autorizado
 * o no (anti-enumeración).
 */
export async function solicitarMagicLink(
  _prev: ResultadoLogin | null,
  formData: FormData
): Promise<ResultadoLogin> {
  const email = String(formData.get('email') ?? '').trim().toLowerCase();
  if (!email || !email.includes('@')) {
    return { ok: false, mensaje: 'Escribe un correo válido.' };
  }

  const generico =
    'Si el correo está autorizado, recibirás un enlace de acceso ' +
    'en unos segundos. Revisa también la carpeta de correo no deseado.';

  if (!(await emailAutorizado(email))) {
    return { ok: true, mensaje: generico };
  }

  const redirectTo = `${origenApp()}/auth/callback`;
  const { error } = await supabaseServer().auth.signInWithOtp({
    email,
    options: {
      shouldCreateUser: false,
      emailRedirectTo: redirectTo,
    },
  });
  if (error) {
    return {
      ok: false,
      mensaje:
        error.message.includes('rate')
          ? 'Demasiados intentos. Espera un minuto e inténtalo de nuevo.'
          : `No se pudo enviar el enlace: ${error.message}`,
    };
  }
  return { ok: true, mensaje: generico };
}

/** @deprecated Usar solicitarMagicLink. Alias por compatibilidad de imports. */
export const solicitarCodigo = solicitarMagicLink;

export async function cerrarSesion(): Promise<void> {
  await supabaseServer().auth.signOut();
}

const PLACEHOLDER_EMAIL = 'email@domain.com';

/**
 * Correo del desarrollador para mostrarlo como pista en el login.
 * No sugiere el placeholder del repo (evita rellenar un correo falso).
 */
export async function emailSugerido(): Promise<string> {
  const cfg = await obtenerConfig();
  const email = (cfg.email_desarrollador ?? '').trim().toLowerCase();
  if (!email || email === PLACEHOLDER_EMAIL) return '';
  return cfg.email_desarrollador ?? '';
}
