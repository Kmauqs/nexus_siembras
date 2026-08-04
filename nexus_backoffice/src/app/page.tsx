import Link from 'next/link';
import { Card, Kpi, Marca } from '@/components/ui';
import { GraficoCircular } from '@/components/charts';
import { HeatmapPatologias } from '@/components/heatmap';
import {
  obtenerConfig, obtenerHeatmap, obtenerStats, obtenerUsuariosPorPais,
} from '@/lib/datos';
import { banderaPais, nombrePais, numero } from '@/lib/formato';

// Datos frescos en cada visita (son agregados livianos).
export const revalidate = 300;

const VERSION_APP = '0.2.8';

export default async function Home() {
  const [stats, porPais, heat, config] = await Promise.all([
    obtenerStats(),
    obtenerUsuariosPorPais(),
    obtenerHeatmap(),
    obtenerConfig(),
  ]);

  const github =
    config.github_url ?? 'https://github.com/nexuscreatio/nexus-siembras';

  const datosPie = porPais.slice(0, 8).map((p) => ({
    nombre: nombrePais(p.pais_iso2),
    valor: Number(p.usuarios),
  }));

  const desatendidas = heat.filter((p) => p.estado === 'desatendida').length;
  const activos = heat.length - desatendidas;
  const diasDesatendida = config.patologia_dias_desatendida ?? '60';

  return (
    <main className="min-h-screen">
      {/* Encabezado con la identidad de la app */}
      <header className="bg-nexus-800 text-white">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-5 py-4">
          <div className="flex items-center gap-3">
            <span className="text-3xl" aria-hidden>🌱</span>
            <div className="leading-tight">
              <p className="text-lg font-bold">NEXUS Siembras</p>
              <p className="text-xs text-nexus-100">Control agropecuario</p>
            </div>
          </div>
          <Link href="/login" className="btn bg-white/15 text-white hover:bg-white/25">
            Ingresar al panel
          </Link>
        </div>
      </header>

      <div className="mx-auto max-w-6xl space-y-6 px-5 py-8">
        {/* Card de la app + GitHub */}
        <Card className="border-nexus-200 bg-gradient-to-br from-nexus-50 to-white">
          <div className="grid gap-6 md:grid-cols-[1.4fr_1fr]">
            <div>
              <Marca />
              <p className="mt-3 text-sm leading-relaxed text-slate-700">
                Aplicación de control agropecuario para{' '}
                <strong>pequeños productores</strong>. Registra cultivos por
                predio y lote con georreferenciación, controla inventario y
                compras, reporta patologías con foto y GPS, y genera reportes
                en PDF/CSV. Funciona <strong>sin conexión</strong> y sincroniza
                cuando vuelve el internet.
              </p>
              <ul className="mt-3 grid gap-1 text-sm text-slate-600 sm:grid-cols-2">
                <li>· Android y Windows</li>
                <li>· Multi-usuario con roles</li>
                <li>· Base de datos local cifrada</li>
                <li>· Catálogo comunitario de variedades</li>
              </ul>
              <div className="mt-4 flex flex-wrap items-center gap-3">
                <a
                  href={github}
                  target="_blank"
                  rel="noreferrer"
                  className="btn-primario"
                >
                  <svg width="18" height="18" viewBox="0 0 16 16" fill="currentColor" aria-hidden>
                    <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8z" />
                  </svg>
                  Ver proyecto en GitHub
                </a>
                <span className="chip bg-nexus-100 text-nexus-800">
                  Versión {VERSION_APP}
                </span>
                <span className="chip bg-amber-100 text-amber-800">
                  En pruebas con usuarios
                </span>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3 self-start">
              <Kpi etiqueta="Usuarios" valor={numero(stats.usuarios)} acento />
              <Kpi
                etiqueta="Activos (30 d)"
                valor={numero(stats.usuarios_activos_30d)}
              />
              <Kpi etiqueta="Cultivos" valor={numero(stats.cultivos)} />
              <Kpi etiqueta="Países" valor={numero(stats.paises)} />
            </div>
          </div>
        </Card>

        <div className="grid gap-6 lg:grid-cols-2">
          {/* Distribución por país */}
          <Card titulo="Usuarios por país" icono={<span>🌎</span>}>
            <GraficoCircular datos={datosPie} />
            {porPais.length > 8 && (
              <p className="mt-2 text-center text-xs text-slate-500">
                Mostrando los 8 países con más usuarios de {porPais.length}.
              </p>
            )}
          </Card>

          {/* Tabla resumen general */}
          <Card titulo="Estadísticas generales" icono={<span>📊</span>}>
            <div className="overflow-hidden rounded-lg border border-slate-200">
              <table className="tabla">
                <thead>
                  <tr>
                    <th>Indicador</th>
                    <th className="text-right">Cantidad</th>
                  </tr>
                </thead>
                <tbody>
                  {[
                    ['Usuarios registrados', stats.usuarios],
                    ['Usuarios activos (últimos 30 días)', stats.usuarios_activos_30d],
                    ['Predios gestionados', stats.predios],
                    ['Lotes registrados', stats.lotes],
                    ['Cultivos gestionados', stats.cultivos],
                    ['Cultivos en curso', stats.cultivos_activos],
                    ['Variedades en el banco comunitario', stats.variedades],
                    ['Reportes de patologías', stats.reportes_patologias],
                    ['Tratamientos en catálogo', stats.tratamientos],
                    ['Países con presencia', stats.paises],
                  ].map(([etiqueta, valor]) => (
                    <tr key={etiqueta as string}>
                      <td>{etiqueta}</td>
                      <td className="text-right font-semibold text-nexus-800">
                        {numero(valor as number)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {porPais.length > 0 && (
              <div className="mt-3 flex flex-wrap gap-1.5">
                {porPais.slice(0, 12).map((p) => (
                  <span key={p.pais_iso2} className="chip bg-slate-100 text-slate-700">
                    {banderaPais(p.pais_iso2)} {nombrePais(p.pais_iso2)}{' '}
                    <strong>{p.usuarios}</strong>
                  </span>
                ))}
              </div>
            )}
          </Card>
        </div>

        {/* Mapa de calor comunitario */}
        <Card
          titulo="Mapa de calor — patologías reportadas"
          icono={<span>🐛</span>}
        >
          <p className="mb-3 text-sm text-slate-600">
            Reportes anónimos compartidos por la comunidad. Los colores
            indican concentración; el rojo señala focos con severidad
            avanzada.
          </p>
          <HeatmapPatologias puntos={heat} />
          <div className="mt-3 flex flex-wrap items-center gap-4 text-xs text-slate-600">
            <span className="flex items-center gap-1.5">
              <span className="inline-block h-3 w-3 rounded-full bg-nexus-600" />
              Foco activo
            </span>
            <span className="flex items-center gap-1.5">
              <span className="inline-block h-3 w-3 rounded-full bg-slate-300" />
              Desatendida — sin actividad en {diasDesatendida} días
            </span>
            <span className="text-slate-400">
              {activos} activo(s) · {desatendidas} desatendida(s)
            </span>
          </div>
          <p className="mt-2 text-xs text-slate-500">
            Los reportes se conservan como patrimonio de la comunidad, incluso
            si su autor deja de usar la app. Datos anonimizados: no incluyen
            identidad del productor ni nombre del predio.
          </p>
        </Card>

        <footer className="flex flex-col items-center gap-1 py-6 text-center text-xs text-slate-500">
          <p>NEXUS Siembras · NEXUS CREATIO</p>
          <p>
            Contacto:{' '}
            <a
              className="text-nexus-700 underline"
              href={`mailto:${config.contacto_soporte ?? ''}`}
            >
              {config.contacto_soporte ?? 'soporte'}
            </a>
          </p>
        </footer>
      </div>
    </main>
  );
}
