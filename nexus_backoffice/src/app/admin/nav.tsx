'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const ITEMS = [
  { href: '/admin', label: 'Inicio', icono: '📈' },
  { href: '/admin/usuarios', label: 'Usuarios', icono: '👥' },
  { href: '/admin/datos', label: 'Datos', icono: '🗂️' },
  { href: '/admin/feedback', label: 'Feedback', icono: '💬' },
  { href: '/admin/config', label: 'Configuración', icono: '⚙️' },
];

export function NavAdmin() {
  const path = usePathname();
  return (
    <nav className="border-t border-white/10 bg-nexus-900/40">
      <div className="mx-auto flex max-w-7xl gap-1 overflow-x-auto px-3">
        {ITEMS.map((it) => {
          const activo =
            it.href === '/admin' ? path === '/admin' : path.startsWith(it.href);
          return (
            <Link
              key={it.href}
              href={it.href}
              className={`whitespace-nowrap border-b-2 px-4 py-2.5 text-sm transition ${
                activo
                  ? 'border-white font-semibold text-white'
                  : 'border-transparent text-nexus-100 hover:text-white'
              }`}
            >
              <span className="mr-1" aria-hidden>{it.icono}</span>
              {it.label}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
