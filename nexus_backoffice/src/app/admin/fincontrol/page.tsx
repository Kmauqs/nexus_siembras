import Link from 'next/link';
import { Card, Chip, Kpi, Vacio } from '@/components/ui';
import { GraficoLineas } from '@/components/charts';
import { fecha, haceCuanto, numero } from '@/lib/formato';
import {
  listarFeedbackRecienteFincontrol,
  obtenerSerieFeedbackFincontrol,
  obtenerStatsFincontrol,
} from '@/lib/fincontrol';

export const dynamic = 'force-dynamic';

export default async function AdminFincontrolPage() {
  const [stats, serie, recientes] = await Promise.all([
    obtenerStatsFincontrol(),
    obtenerSerieFeedbackFincontrol(30),
    listarFeedbackRecienteFincontrol(10),
  ]);

  return (
    <div className="space-y-6">
      <div className="rounded-xl border border-nexus-100 bg-nexus-50/60 p-4 text-sm text-nexus-900">
        <p className="font-semibold">FINCONTROL · beta cerrada</p>
        <p className="mt-1 text-nexus-800/90">
          Comparte Auth y el proyecto Supabase con NEXUS Siembras. El feedback
          llega a <code className="text-xs">feedback_encuestas</code> con tipos{' '}
          <code className="text-xs">fincontrol_*</code>. A futuro ambas apps se
          integrarán (costos agropecuarios ↔ finanzas del hogar).
        </p>
      </div>

      {!stats.disponible ? (
        <Card titulo="Dominio FINCONTROL" icono={<span>🏦</span>}>
          <Vacio texto="No se detectaron tablas de FINCONTROL en este proyecto Supabase (households / memberships). Aplica las migraciones de FINCONTROL sobre el mismo proyecto si aún faltan." />
        </Card>
      ) : (
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Kpi
            etiqueta="Hogares"
            valor={numero(stats.households)}
            detalle={`${numero(stats.miembros)} membresías`}
            acento
          />
          <Kpi
            etiqueta="Movimientos (30 d)"
            valor={numero(stats.movimientos_30d)}
            detalle="tabla transactions"
          />
          <Kpi
            etiqueta="Feedback"
            valor={numero(stats.feedback_total)}
            detalle={
              stats.calificacion_media != null
                ? `media ${stats.calificacion_media.toFixed(1)} / 5`
                : 'sin calificaciones'
            }
          />
          <Kpi
            etiqueta="Feedback pendiente"
            valor={numero(stats.feedback_pendiente)}
            detalle={
              stats.feedback_pendiente > 0 ? 'requiere revisión' : 'al día'
            }
            acento={stats.feedback_pendiente > 0}
          />
        </div>
      )}

      <Card titulo="Feedback FINCONTROL — 30 días" icono={<span>📈</span>}>
        {serie.some((s) => s.feedbacks > 0) ? (
          <GraficoLineas
            datos={serie as unknown as Record<string, string | number>[]}
            series={[
              { clave: 'feedbacks', etiqueta: 'Feedback' },
              { clave: 'bugs', etiqueta: 'Sync / incidencias' },
            ]}
          />
        ) : (
          <Vacio texto="Sin feedback FINCONTROL en el período." />
        )}
      </Card>

      <Card
        titulo="Últimos comentarios FINCONTROL"
        icono={<span>💬</span>}
        accion={
          <Link
            href="/admin/feedback?app=fincontrol"
            className="btn-sutil text-xs"
          >
            Gestionar →
          </Link>
        }
      >
        {recientes.length === 0 ? (
          <Vacio texto="Todavía no hay feedback de FINCONTROL." />
        ) : (
          <ul className="space-y-2">
            {recientes.map((f) => {
              const row = f as {
                id: number;
                created_at: string;
                tipo: string;
                calificacion: number | null;
                comentario: string | null;
                email_usuario: string | null;
                atendido: boolean;
              };
              return (
                <li
                  key={row.id}
                  className="rounded-lg border border-slate-100 bg-white p-3"
                >
                  <div className="flex items-center justify-between gap-2">
                    <div className="flex items-center gap-2">
                      <Chip>{row.tipo}</Chip>
                      {row.atendido ? (
                        <Chip tono="verde">atendido</Chip>
                      ) : (
                        <Chip tono="ambar">pendiente</Chip>
                      )}
                    </div>
                    <span className="text-xs text-slate-500">
                      {haceCuanto(row.created_at)}
                    </span>
                  </div>
                  <p className="mt-1 text-sm text-slate-700">
                    {row.comentario ?? '(sin comentario)'}
                  </p>
                  <p className="mt-1 text-xs text-slate-500">
                    {row.email_usuario ?? 'anónimo'} ·{' '}
                    {fecha(row.created_at, true)}
                    {row.calificacion != null
                      ? ` · ${'★'.repeat(row.calificacion)}`
                      : ''}
                  </p>
                </li>
              );
            })}
          </ul>
        )}
      </Card>

      <Card titulo="Administración" icono={<span>🛠️</span>}>
        <ul className="list-disc space-y-2 pl-5 text-sm text-slate-700">
          <li>
            <Link className="text-nexus-700 underline" href="/admin/feedback?app=fincontrol">
              Bandeja de feedback filtrada a FINCONTROL
            </Link>{' '}
            — marcar atendido, notas y export CSV.
          </li>
          <li>
            <Link className="text-nexus-700 underline" href="/admin/usuarios">
              Usuarios
            </Link>{' '}
            — Auth compartido; la papelera afecta ambas apps.
          </li>
          <li>
            <Link className="text-nexus-700 underline" href="/admin/config">
              Configuración
            </Link>{' '}
            — email de notificación de feedback (compartido).
          </li>
        </ul>
      </Card>
    </div>
  );
}
