'use server';

import { supabaseServer } from '@/lib/supabase/server';
import { emailAutorizado } from '@/lib/auth';
import { obtenerConfig } from '@/lib/datos';

export type ResultadoLogin = { ok: boolean; mensaje: string };

/**
 * Paso 1 — Solicitar código de 6 dígitos.
 *
 * Solo se envía si el email está autorizado (allowlist en BD o bootstrap
 * del .env). `shouldCreateUser: false` evita que alguien cree cuentas
 * nuevas desde aquí.
 *
 * Nota: el mensaje de respuesta es deliberadamente el mismo para email
 * autorizado y no autorizado, para no revelar quién es administrador.
 */
export async function solicitarCodigo(
  _prev: ResultadoLogin | null,
  formData: FormData
): Promise<ResultadoLogin> {
  const email = String(formData.get('email') ?? '').trim().toLowerCase();
  if (!email || !email.includes('@')) {
    return { ok: false, mensaje: 'Escribe un correo válido.' };
  }

  const generico =
    'Si el correo está autorizado, recibirás un código de 6 dígitos ' +
    'en unos segundos.';

  if (!(await emailAutorizado(email))) {
    // Respuesta idéntica al caso exitoso (anti-enumeración).
    return { ok: true, mensaje: generico };
  }

  const { error } = await supabaseServer().auth.signInWithOtp({
    email,
    options: { shouldCreateUser: false },
  });
  if (error) {
    return {
      ok: false,
      mensaje:
        error.message.includes('rate')
          ? 'Demasiados intentos. Espera un minuto e inténtalo de nuevo.'
          : `No se pudo enviar el código: ${error.message}`,
    };
  }
  return { ok: true, mensaje: generico };
}

/** Paso 2 — Verificar el código y abrir sesión. */
export async function verificarCodigo(
  _prev: ResultadoLogin | null,
  formData: FormData
): Promise<ResultadoLogin> {
  const email = String(formData.get('email') ?? '').trim().toLowerCase();
  const token = String(formData.get('codigo') ?? '').replace(/\D/g, '');

  if (token.length !== 6) {
    return { ok: false, mensaje: 'El código debe tener 6 dígitos.' };
  }

  const { error } = await supabaseServer().auth.verifyOtp({
    email,
    token,
    type: 'email',
  });
  if (error) {
    return {
      ok: false,
      mensaje: 'Código incorrecto o vencido. Solicita uno nuevo.',
    };
  }

  // Doble verificación: la sesión existe, pero ¿sigue autorizado?
  if (!(await emailAutorizado(email))) {
    await supabaseServer().auth.signOut();
    return { ok: false, mensaje: 'Esta cuenta no tiene acceso al panel.' };
  }

  return { ok: true, mensaje: 'Acceso concedido.' };
}

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
