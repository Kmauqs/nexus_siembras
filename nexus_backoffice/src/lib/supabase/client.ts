'use client';
import { createBrowserClient } from '@supabase/ssr';

/** Cliente del navegador (anon key). Solo para login/logout. */
export function supabaseBrowser() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
