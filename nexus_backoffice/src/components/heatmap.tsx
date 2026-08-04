'use client';

import { useEffect, useRef } from 'react';

export type PuntoPatologia = {
  lat: number;
  lng: number;
  patologia_nombre: string | null;
  severidad: string | null;
  pais_iso2: string | null;
  fecha_deteccion: string | null;
  /** 'activa' | 'desatendida' — calculado por estado_reporte() en la BD. */
  estado?: string | null;
  dias_sin_actividad?: number | null;
};

/** Escapa texto para insertarlo en HTML de Leaflet (evita XSS). */
function escHtml(valor: string | number | null | undefined): string {
  return String(valor ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Mapa de calor de patologías reportadas (Leaflet + leaflet.heat).
 *
 * Se carga dinámicamente en el cliente: Leaflet toca `window`, así que no
 * puede ejecutarse durante el render del servidor. Los datos llegan ya
 * anonimizados desde `stats_heatmap_patologias()`.
 */
export function HeatmapPatologias({
  puntos,
  altura = 420,
}: {
  puntos: PuntoPatologia[];
  altura?: number;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const mapaRef = useRef<unknown>(null);

  useEffect(() => {
    let cancelado = false;

    (async () => {
      const L = (await import('leaflet')).default;
      await import('leaflet.heat');
      if (cancelado || !ref.current || mapaRef.current) return;

      // Centro: promedio de los puntos, o LATAM por defecto.
      const centro: [number, number] = puntos.length
        ? [
            puntos.reduce((s, p) => s + p.lat, 0) / puntos.length,
            puntos.reduce((s, p) => s + p.lng, 0) / puntos.length,
          ]
        : [4.6, -74.1];

      const mapa = L.map(ref.current, {
        center: centro,
        zoom: puntos.length ? 6 : 4,
        scrollWheelZoom: false,
      });
      mapaRef.current = mapa;

      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; OpenStreetMap',
        maxZoom: 18,
      }).addTo(mapa);

      if (puntos.length) {
        // Solo los focos ACTIVOS alimentan el mapa de calor: un reporte
        // desatendido (60+ días sin señales) ya no representa un foco
        // vigente, así que no debe teñir el mapa de rojo.
        const activos = puntos.filter((p) => p.estado !== 'desatendida');
        const datos = activos.map((p) => [
          p.lat,
          p.lng,
          p.severidad === 'avanzada' ? 1 : 0.6,
        ]);
        if (datos.length) {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          (L as any)
            .heatLayer(datos, {
              radius: 26,
              blur: 18,
              maxZoom: 12,
              gradient: {
                0.2: '#74C795',
                0.45: '#D97706',
                0.75: '#B91C1C',
              },
            })
            .addTo(mapa);
        }

        // Marcadores: gris para desatendidos, verde para activos.
        puntos.slice(0, 400).forEach((p) => {
          const desatendida = p.estado === 'desatendida';
          L.circleMarker([p.lat, p.lng], {
            radius: 4,
            color: desatendida ? '#94A3B8' : '#0F5132',
            weight: 1,
            fillColor: desatendida ? '#CBD5E1' : '#1B7A3E',
            fillOpacity: desatendida ? 0.5 : 0.35,
          })
            .bindPopup(
              `<strong>${escHtml(p.patologia_nombre ?? 'Sin identificar')}</strong><br/>` +
                `Severidad: ${escHtml(p.severidad ?? 'n/d')}<br/>` +
                `${escHtml(p.fecha_deteccion)}<br/>` +
                (desatendida
                  ? `<span style="color:#64748B">Desatendida — ` +
                    `${escHtml(p.dias_sin_actividad ?? '?')} días sin actividad</span>`
                  : `<span style="color:#1B7A3E">Foco activo</span>`)
            )
            .addTo(mapa);
        });

        const bounds = L.latLngBounds(
          puntos.map((p) => [p.lat, p.lng] as [number, number])
        );
        mapa.fitBounds(bounds, { padding: [30, 30], maxZoom: 10 });
      }
    })();

    return () => {
      cancelado = true;
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const m = mapaRef.current as any;
      if (m) {
        m.remove();
        mapaRef.current = null;
      }
    };
  }, [puntos]);

  if (!puntos.length) {
    return (
      <div
        className="flex items-center justify-center rounded-lg bg-slate-100 text-sm text-slate-400"
        style={{ height: altura }}
      >
        Aún no hay reportes de patologías georreferenciados.
      </div>
    );
  }

  return <div ref={ref} style={{ height: altura }} className="rounded-lg" />;
}
