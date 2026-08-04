import Link from 'next/link';
import { requerirAdmin } from '@/lib/auth';
import { cerrarSesion } from '../login/acciones';
import { NavAdmin } from './nav';

export default async function AdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const sesion = await requerirAdmin(); // redirige si no es admin

  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-30 bg-nexus-800 text-white shadow">
        <div className="mx-auto flex max-w-7xl items-center justify-between gap-4 px-5 py-3">
          <Link href="/admin" className="flex items-center gap-2">
            <span className="text-2xl" aria-hidden>🌱</span>
            <div className="leading-tight">
              <p className="font-bold">NEXUS Siembras</p>
              <p className="text-[11px] text-nexus-100">Administración</p>
            </div>
          </Link>

          <div className="flex items-center gap-3">
            <span className="hidden text-xs text-nexus-100 sm:inline">
              {sesion.email}
            </span>
            <Link
              href="/"
              className="btn bg-white/10 px-3 py-1.5 text-xs text-white hover:bg-white/20"
            >
              Sitio público
            </Link>
            <form action={async () => {
              'use server';
              await cerrarSesion();
            }}>
              <button className="btn bg-white/10 px-3 py-1.5 text-xs text-white hover:bg-white/20">
                Salir
              </button>
            </form>
          </div>
        </div>
        <NavAdmin />
      </header>

      <main className="mx-auto max-w-7xl px-5 py-6">{children}</main>
    </div>
  );
}
