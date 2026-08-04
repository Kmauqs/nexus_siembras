import type { ReactNode } from 'react';

export function Card({
  titulo,
  icono,
  accion,
  children,
  className = '',
}: {
  titulo?: string;
  icono?: ReactNode;
  accion?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={`card ${className}`}>
      {(titulo || accion) && (
        <header className="mb-3 flex items-start justify-between gap-3">
          {titulo && (
            <h2 className="card-title">
              {icono}
              {titulo}
            </h2>
          )}
          {accion}
        </header>
      )}
      {children}
    </section>
  );
}

export function Kpi({
  etiqueta,
  valor,
  detalle,
  acento = false,
}: {
  etiqueta: string;
  valor: string | number;
  detalle?: string;
  acento?: boolean;
}) {
  return (
    <div
      className={`rounded-xl border p-4 ${
        acento
          ? 'border-nexus-200 bg-nexus-50'
          : 'border-slate-200 bg-white'
      }`}
    >
      <p className="text-xs uppercase tracking-wide text-slate-500">
        {etiqueta}
      </p>
      <p className="mt-1 text-2xl font-bold text-nexus-800">{valor}</p>
      {detalle && <p className="text-xs text-slate-500">{detalle}</p>}
    </div>
  );
}

const TONOS = {
  verde: 'bg-nexus-100 text-nexus-800',
  gris: 'bg-slate-100 text-slate-600',
  ambar: 'bg-amber-100 text-amber-800',
  rojo: 'bg-red-100 text-red-800',
  azul: 'bg-blue-100 text-blue-800',
} as const;

export function Chip({
  children,
  tono = 'gris',
}: {
  children: ReactNode;
  tono?: keyof typeof TONOS;
}) {
  return <span className={`chip ${TONOS[tono]}`}>{children}</span>;
}

export function Vacio({ texto }: { texto: string }) {
  return (
    <p className="py-6 text-center text-sm text-slate-400">{texto}</p>
  );
}

/** Marca de la app, reutilizada en la web pública y en el backoffice. */
export function Marca({ compacta = false }: { compacta?: boolean }) {
  return (
    <div className="flex items-center gap-2">
      <span className="text-2xl" aria-hidden>
        🌱
      </span>
      <div className="leading-tight">
        <p className="font-bold text-nexus-800">NEXUS Siembras</p>
        {!compacta && (
          <p className="text-xs text-slate-500">Control agropecuario</p>
        )}
      </div>
    </div>
  );
}
