import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

/**
 * Cliente con la sesión del usuario (anon key + cookies). Respeta RLS.
 * Se usa para saber QUIÉN está logueado en el backoffice.
 */
export function supabaseServer() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => cookieStore.getAll(),
        setAll: (items) => {
          try {
            items.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            );
          } catch {
            // Llamado desde un Server Component: el middleware refresca
            // la sesión, así que se puede ignorar.
          }
        },
      },
    }
  );
}
