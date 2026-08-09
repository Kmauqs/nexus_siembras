import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

/**
 * Refresca la sesión de Supabase en cada request y bloquea /admin sin
 * sesión. La verificación de "es admin" (allowlist) se hace además en el
 * layout del panel — el middleware es la primera barrera, no la única.
 */
export async function middleware(request: NextRequest) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim();

  if (!url || !anon) {
    return new NextResponse(
      [
        '<!doctype html><html lang="es"><body style="font-family:system-ui;padding:2rem;max-width:40rem">',
        '<h1>Falta configuración de Supabase</h1>',
        '<p>Crea <code>.env.local</code> en <code>nexus_backoffice/</code> a partir de ',
        '<code>.env.example</code> y reinicia <code>npm run dev</code>.</p>',
        '<pre style="background:#f4f4f5;padding:1rem;border-radius:8px">',
        'cp .env.example .env.local\n',
        '# completar NEXT_PUBLIC_SUPABASE_URL\n',
        '# completar NEXT_PUBLIC_SUPABASE_ANON_KEY\n',
        '# completar SUPABASE_SERVICE_ROLE_KEY\n',
        '# completar ADMIN_EMAIL_BOOTSTRAP\n',
        'npm run dev',
        '</pre>',
        '<p>Next.js no carga <code>.env.example</code>; solo ',
        '<code>.env.local</code> / <code>.env</code>.</p>',
        '</body></html>',
      ].join(''),
      {
        status: 500,
        headers: { 'content-type': 'text/html; charset=utf-8' },
      }
    );
  }

  let response = NextResponse.next({ request });

  const supabase = createServerClient(url, anon, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (
        items: { name: string; value: string; options?: object }[]
      ) => {
        items.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        items.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options)
        );
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user && request.nextUrl.pathname.startsWith('/admin')) {
    const dest = request.nextUrl.clone();
    dest.pathname = '/login';
    dest.searchParams.set('motivo', 'no-autorizado');
    return NextResponse.redirect(dest);
  }

  return response;
}

export const config = {
  matcher: ['/admin/:path*', '/login', '/auth/callback'],
};
