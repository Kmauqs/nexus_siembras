/** Utilidades de formato compartidas por el sitio y el backoffice. */

const NOMBRE_PAIS: Record<string, string> = {
  CO: 'Colombia', MX: 'México', BR: 'Brasil', AR: 'Argentina',
  PE: 'Perú', EC: 'Ecuador', CL: 'Chile', BO: 'Bolivia',
  PY: 'Paraguay', UY: 'Uruguay', VE: 'Venezuela', GT: 'Guatemala',
  HN: 'Honduras', SV: 'El Salvador', NI: 'Nicaragua', CR: 'Costa Rica',
  PA: 'Panamá', DO: 'Rep. Dominicana', CU: 'Cuba', PR: 'Puerto Rico',
  ES: 'España', US: 'Estados Unidos', ND: 'Sin declarar',
};

export function nombrePais(iso2?: string | null): string {
  if (!iso2) return 'Sin declarar';
  return NOMBRE_PAIS[iso2.toUpperCase()] ?? iso2.toUpperCase();
}

/** Bandera emoji a partir del ISO2 (ND → globo). */
export function banderaPais(iso2?: string | null): string {
  const c = (iso2 ?? '').toUpperCase();
  if (c.length !== 2 || c === 'ND') return '🌎';
  return String.fromCodePoint(
    ...[...c].map((ch) => 0x1f1e6 + ch.charCodeAt(0) - 65)
  );
}

export function fecha(v?: string | null, conHora = false): string {
  if (!v) return '—';
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return '—';
  const f = d.toLocaleDateString('es-CO', {
    year: 'numeric', month: 'short', day: '2-digit',
  });
  if (!conHora) return f;
  return `${f} ${d.toLocaleTimeString('es-CO', {
    hour: '2-digit', minute: '2-digit',
  })}`;
}

export function haceCuanto(v?: string | null): string {
  if (!v) return 'nunca';
  const ms = Date.now() - new Date(v).getTime();
  const min = Math.floor(ms / 60000);
  if (min < 1) return 'ahora';
  if (min < 60) return `hace ${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `hace ${h} h`;
  const d = Math.floor(h / 24);
  if (d < 30) return `hace ${d} d`;
  const m = Math.floor(d / 30);
  return m < 12 ? `hace ${m} mes(es)` : `hace ${Math.floor(m / 12)} año(s)`;
}

export const numero = (n?: number | null): string =>
  (n ?? 0).toLocaleString('es-CO');

/** Paleta consistente para los gráficos (verdes de la app + apoyos). */
export const COLORES_GRAFICO = [
  '#1B7A3E', '#2E9E63', '#74C795', '#0F5132', '#8B6F47',
  '#2563EB', '#7C3AED', '#D97706', '#B91C1C', '#6B7280',
];
