import { Card } from '@/components/ui';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { obtenerConfig } from '@/lib/datos';
import { EditorTablas, type Columna } from './editor';
import type { Tabla } from './acciones';

export const dynamic = 'force-dynamic';

const COLUMNAS: Record<Tabla, Columna[]> = {
  variedades_comunitarias: [
    { campo: 'nombre_comun', etiqueta: 'Nombre común', ancho: 'w-44' },
    { campo: 'especie', etiqueta: 'Especie' },
    { campo: 'metodo_siembra', etiqueta: 'Método', tipo: 'select',
      opciones: ['directa', 'germinador'] },
    { campo: 'germinador_dias', etiqueta: 'Germ. días', tipo: 'numero' },
    { campo: 'cosecha_min_dias', etiqueta: 'Cosecha min', tipo: 'numero' },
    { campo: 'cosecha_max_dias', etiqueta: 'Cosecha max', tipo: 'numero' },
    { campo: 'tipo_abono1', etiqueta: 'Abono 1' },
    { campo: 'tipo_abono2', etiqueta: 'Abono 2' },
    { campo: 'abono2_dias', etiqueta: 'Días abono 2', tipo: 'numero' },
    { campo: 'fuente', etiqueta: 'Fuente' },
    { campo: 'contribuciones', etiqueta: 'Aportes', soloLectura: true },
  ],
  patologias_reportadas: [
    { campo: 'estado', etiqueta: 'Estado', soloLectura: true, tipo: 'estado' },
    { campo: 'patologia_nombre', etiqueta: 'Patología', ancho: 'w-44' },
    { campo: 'patologia_cientifico', etiqueta: 'Científico' },
    { campo: 'planta_nombre', etiqueta: 'Planta' },
    { campo: 'severidad', etiqueta: 'Severidad', tipo: 'select',
      opciones: ['inicial', 'avanzada'] },
    { campo: 'sintomas', etiqueta: 'Síntomas', tipo: 'texto-largo' },
    { campo: 'pais_iso2', etiqueta: 'País' },
    { campo: 'municipio_nombre', etiqueta: 'Municipio' },
    { campo: 'notas_admin', etiqueta: 'Notas admin', tipo: 'texto-largo' },
    { campo: 'fecha_deteccion', etiqueta: 'Detección', soloLectura: true },
  ],
  patologia_tratamientos: [
    { campo: 'patologia_nombre', etiqueta: 'Patología', ancho: 'w-40' },
    { campo: 'pais_iso2', etiqueta: 'País' },
    { campo: 'tipo', etiqueta: 'Tipo', tipo: 'select',
      opciones: ['preventivo', 'cultural', 'biologico', 'integrado', 'quimico'] },
    { campo: 'titulo', etiqueta: 'Título', ancho: 'w-48' },
    { campo: 'descripcion', etiqueta: 'Descripción', tipo: 'texto-largo' },
    { campo: 'producto', etiqueta: 'Producto' },
    { campo: 'dosis', etiqueta: 'Dosis' },
    { campo: 'frecuencia', etiqueta: 'Frecuencia' },
    { campo: 'amigable_ambiente', etiqueta: 'Sostenible', tipo: 'bool' },
    { campo: 'fuente', etiqueta: 'Fuente' },
    { campo: 'fuente_url', etiqueta: 'URL fuente' },
  ],
};

export default async function DatosPage() {
  const sb = supabaseAdmin();

  const [variedades, reportes, tratamientos, config] = await Promise.all([
    sb.from('variedades_comunitarias').select('*')
      .order('contribuciones', { ascending: false }).limit(500),
    // Sin filtro de deleted_at: el admin ve también los ocultos para
    // poder restaurarlos (los reportes nunca se destruyen).
    sb.from('patologias_reportadas')
      .select('*')
      .order('ultima_actividad_at', { ascending: true, nullsFirst: true })
      .limit(500),
    sb.from('patologia_tratamientos').select('*')
      .order('patologia_nombre').limit(500),
    obtenerConfig(),
  ]);

  const diasDesatendida = Number(config.patologia_dias_desatendida ?? 60) || 60;

  return (
    <div className="space-y-6">
      <Card titulo="Gestión de datos comunitarios" icono={<span>🗂️</span>}>
        <p className="text-sm text-slate-600">
          Edición directa de las tablas alimentadas por la comunidad. Los
          cambios se reflejan en la app de todos los usuarios: corrige
          nombres, completa datos agronómicos o modera contenido.
        </p>
        <div className="mt-3 rounded-lg border border-nexus-200 bg-nexus-50 p-3 text-sm text-nexus-900">
          <p className="font-semibold">🌱 Patrimonio comunitario</p>
          <ul className="mt-1 space-y-1 text-[13px]">
            <li>
              · Las <strong>variedades</strong> y los{' '}
              <strong>reportes de patologías</strong> se conservan aunque
              su autor elimine la cuenta (quedan anónimos).
            </li>
            <li>
              · Los reportes <strong>no se borran nunca</strong>. Si un
              contenido es inadecuado, usa <em>Ocultar</em>: sale del mapa
              público pero permanece en la base.
            </li>
            <li>
              · Un reporte pasa a{' '}
              <span className="chip bg-slate-200 text-slate-600">
                desatendida
              </span>{' '}
              tras los días configurados sin actividad. Se reactiva solo si
              alguien reporta cerca, o si lo marcas como{' '}
              <em>atendido</em>.
            </li>
          </ul>
        </div>
      </Card>

      <EditorTablas
        diasDesatendida={diasDesatendida}
        tablas={[
          {
            id: 'variedades_comunitarias',
            titulo: 'Banco comunitario de variedades',
            icono: '🌿',
            columnas: COLUMNAS.variedades_comunitarias,
            filas: variedades.data ?? [],
            permiteCrear: true,
          },
          {
            id: 'patologias_reportadas',
            titulo: 'Reportes de patologías (vista pública)',
            icono: '🐛',
            columnas: COLUMNAS.patologias_reportadas,
            filas: reportes.data ?? [],
            permiteCrear: false,
          },
          {
            id: 'patologia_tratamientos',
            titulo: 'Tratamientos por patología',
            icono: '💊',
            columnas: COLUMNAS.patologia_tratamientos,
            filas: tratamientos.data ?? [],
            permiteCrear: true,
          },
        ]}
      />
    </div>
  );
}
