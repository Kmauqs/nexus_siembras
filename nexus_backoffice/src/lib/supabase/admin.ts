import 'server-only'; // ← rompe el build si alguien lo importa en el cliente
import { createClient } from '@supabase/supabase-js';

/**
 * Cliente con service_role: SALTA RLS. Uso exclusivo del servidor
 * (Server Components, Server Actions, Route Handlers).
 *
 * El import de 'server-only' garantiza a nivel de compilación que esta
 * clave nunca termine en un bundle del navegador.
 */
export function supabaseAdmin() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new Error(
      'Faltan NEXT_PUBLIC_SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY. ' +
        'Configúralas en .env.local o en Netlify.'
    );
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
