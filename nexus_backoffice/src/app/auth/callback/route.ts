import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';
import { emailAutorizado } from '@/lib/auth';

/**
 * Destino del magic link de Supabase (`emailRedirectTo`).
 * Intercambia el `code` por sesión en cookies y comprueba allowlist.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const code = url.searchParams.get('code');
  const next = url.searchParams.get('next') ?? '/admin';
  const origin = url.origin;

  if (!code) {
    return NextResponse.redirect(`${origin}/login?motivo=enlace-invalido`);
  }

  const cookieStore = cookies();
  let destino = `${origin}${next.startsWith('/') ? next : `/${next}`}`;

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => cookieStore.getAll(),
        setAll: (items) => {
          items.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options)
          );
        },
      },
    }
  );

  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    return NextResponse.redirect(`${origin}/login?motivo=enlace-invalido`);
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();
  const email = (user?.email ?? '').trim().toLowerCase();

  if (!email || !(await emailAutorizado(email))) {
    await supabase.auth.signOut();
    destino = `${origin}/login?motivo=no-autorizado`;
  }

  const response = NextResponse.redirect(destino);
  cookieStore.getAll().forEach((c) => {
    response.cookies.set(c.name, c.value);
  });
  return response;
}
