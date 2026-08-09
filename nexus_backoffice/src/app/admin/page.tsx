import Link from 'next/link';
import { Card, Chip, Kpi, Vacio } from '@/components/ui';
import { GraficoBarras, GraficoLineas } from '@/components/charts';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { supabaseServer } from '@/lib/supabase/server';
import { obtenerStats, obtenerUsuariosPorPais } from '@/lib/datos';
import { fecha, haceCuanto, nombrePais, numero } from '@/lib/formato';

export const dynamic = 'force-dynamic';

type SerieUso = {
  dia: string;
  usuarios_nuevos: number;
  cultivos: number;
  reportes: number;
  feedbacks: number;
};

type FeedbackFila = {
  id: number;
  created_at: string;
  tipo: string;
  calificacion: number | null;
  comentario: string | null;
  email_usuario: string | null;
  app_version: string | null;
  plataforma: string | null;
  atendido: boolean;
};

export default async function AdminInicio() {
  const sbAdmin = supabaseAdmin();
  // Las RPCs que llaman es_admin() necesitan el JWT del usuario logueado;
  // service_role no lleva email → devolvería series vacías.
  const sbSesion = supabaseServer();

  const [stats, porPais, serieRes, feedbackRes, pendientesRes] =
    await Promise.all([
      obtenerStats(),
      obtenerUsuariosPorPais(),
      sbSesion.rpc('admin_series_uso', { p_dias: 30 }),
      sbAdmin
        .from('feedback_encuestas')
        .select(
          'id, created_at, tipo, calificacion, comentario, email_usuario, app_version, plataforma, atendido'
        )
        .order('created_at', { ascending: false })
        .limit(8),
      sbAdmin
        .from('feedback_encuestas')
        .select('id', { count: 'exact', head: true })
        .eq('atendido', false),
    ]);

  const serie = ((serieRes.data ?? []) as SerieUso[]).map((s) => ({
    ...s,
    dia: s.dia?.slice(5) ?? '', // MM-DD
  }));
  const feedbacks = (feedbackRes.data ?? []) as FeedbackFila[];
  const pendientes = pendientesRes.count ?? 0;

  // Feedback con señales de problema: calificación baja o tipo bug.
  const conErrores = feedbacks.filter(
    (f) => f.tipo === 'bug' || (f.calificacion !== null && f.calificacion <= 2)
  );

  const rankingPaises = porPais.slice(0, 7).map((p) => ({
    nombre: nombrePais(p.pais_iso2),
    valor: Number(p.usuarios),
  }));

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi
          etiqueta="Usuarios"
          valor={numero(stats.usuarios)}
          detalle={`${stats.usuarios_activos_30d} activos en 30 días`}
          acento
        />
        <Kpi
          etiqueta="Cultivos"
          valor={numero(stats.cultivos)}
          detalle={`${stats.cultivos_activos} en curso`}
        />
        <Kpi
          etiqueta="Reportes patologías"
          valor={numero(stats.reportes_patologias)}
        />
        <Kpi
          etiqueta="Feedback sin atender"
          valor={numero(pendientes)}
          detalle={pendientes > 0 ? 'requiere revisión' : 'todo al día'}
          acento={pendientes > 0}
        />
      </div>

      <Card titulo="Uso de la app — últimos 30 días" icono={<span>📈</span>}>
        {serie.length ? (
          <GraficoLineas
            datos={serie as unknown as Record<string, string | number>[]}
            series={[
              { clave: 'usuarios_nuevos', etiqueta: 'Usuarios nuevos' },
              { clave: 'cultivos', etiqueta: 'Cultivos creados' },
              { clave: 'reportes', etiqueta: 'Reportes patología' },
              { clave: 'feedbacks', etiqueta: 'Feedback' },
            ]}
          />
        ) : (
          <Vacio texto="Sin actividad registrada en el período (o falta aplicar la migración 0017)." />
        )}
      </Card>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card titulo="Usuarios por país" icono={<span>🌎</span>}>
          <GraficoBarras datos={rankingPaises} />
        </Card>

        <Card
          titulo="Feedback con posibles errores"
          icono={<span>🐞</span>}
          accion={
            <Link href="/admin/feedback" className="btn-sutil text-xs">
              Ver todo →
            </Link>
          }
        >
          {conErrores.length === 0 ? (
            <Vacio texto="Sin reportes de error recientes. 🎉" />
          ) : (
            <ul className="space-y-2">
              {conErrores.map((f) => (
                <li
                  key={f.id}
                  className="rounded-lg border border-red-100 bg-red-50/50 p-3"
                >
                  <div className="flex items-center justify-between gap-2">
                    <div className="flex items-center gap-2">
                      <Chip tono="rojo">{f.tipo}</Chip>
                      {f.calificacion !== null && (
                        <span className="text-xs text-amber-700">
                          {'★'.repeat(f.calificacion)}
                          {'☆'.repeat(5 - f.calificacion)}
                        </span>
                      )}
                    </div>
                    <span className="text-xs text-slate-500">
                      {haceCuanto(f.created_at)}
                    </span>
                  </div>
                  <p className="mt-1 text-sm text-slate-700">
                    {f.comentario ?? '(sin comentario)'}
                  </p>
                  <p className="mt-1 text-xs text-slate-500">
                    {f.email_usuario ?? 'anónimo'} · {f.plataforma ?? '—'} ·{' '}
                    v{f.app_version ?? '—'}
                  </p>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      <Card
        titulo="Feedback reciente"
        icono={<span>💬</span>}
        accion={
          <Link href="/admin/feedback" className="btn-sutil text-xs">
            Gestionar →
          </Link>
        }
      >
        {feedbacks.length === 0 ? (
          <Vacio texto="Todavía no se ha recibido feedback." />
        ) : (
          <div className="overflow-x-auto">
            <table className="tabla">
              <thead>
                <tr>
                  <th>Fecha</th>
                  <th>Tipo</th>
                  <th>Calif.</th>
                  <th>Comentario</th>
                  <th>Usuario</th>
                  <th>Estado</th>
                </tr>
              </thead>
              <tbody>
                {feedbacks.map((f) => (
                  <tr key={f.id}>
                    <td className="whitespace-nowrap text-xs">
                      {fecha(f.created_at, true)}
                    </td>
                    <td><Chip>{f.tipo}</Chip></td>
                    <td className="whitespace-nowrap text-amber-600">
                      {f.calificacion ? '★'.repeat(f.calificacion) : '—'}
                    </td>
                    <td className="max-w-md">
                      {f.comentario ?? <em className="text-slate-400">sin texto</em>}
                    </td>
                    <td className="text-xs">{f.email_usuario ?? 'anónimo'}</td>
                    <td>
                      {f.atendido ? (
                        <Chip tono="verde">atendido</Chip>
                      ) : (
                        <Chip tono="ambar">pendiente</Chip>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}
