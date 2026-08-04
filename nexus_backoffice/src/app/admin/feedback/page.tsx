import { Card, Kpi } from '@/components/ui';
import { GraficoCircular } from '@/components/charts';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { ListaFeedback, type FeedbackItem } from './lista';

export const dynamic = 'force-dynamic';

export default async function FeedbackPage({
  searchParams,
}: {
  searchParams: { usuario?: string };
}) {
  const { data } = await supabaseAdmin()
    .from('feedback_encuestas')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(1000);

  const items = (data ?? []) as FeedbackItem[];
  const pendientes = items.filter((f) => !f.atendido).length;
  const conCalif = items.filter((f) => f.calificacion !== null);
  const promedio = conCalif.length
    ? (
        conCalif.reduce((s, f) => s + (f.calificacion ?? 0), 0) /
        conCalif.length
      ).toFixed(1)
    : '—';

  // Distribución por tipo para el gráfico.
  const porTipo = Object.entries(
    items.reduce<Record<string, number>>((acc, f) => {
      acc[f.tipo] = (acc[f.tipo] ?? 0) + 1;
      return acc;
    }, {})
  ).map(([nombre, valor]) => ({ nombre, valor }));

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi etiqueta="Total recibidos" valor={items.length} />
        <Kpi
          etiqueta="Sin atender"
          valor={pendientes}
          acento={pendientes > 0}
        />
        <Kpi etiqueta="Calificación media" valor={`${promedio} / 5`} />
        <Kpi
          etiqueta="Con posible error"
          valor={
            items.filter(
              (f) =>
                f.tipo === 'bug' ||
                (f.calificacion !== null && f.calificacion <= 2)
            ).length
          }
        />
      </div>

      {porTipo.length > 1 && (
        <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
          <Card titulo="Por tipo de encuesta" icono={<span>🍰</span>}>
            <GraficoCircular datos={porTipo} altura={240} />
          </Card>
          <Card titulo="Cómo usar esta pantalla" icono={<span>💡</span>}>
            <ul className="space-y-2 text-sm text-slate-700">
              <li>
                <strong>Filtra</strong> por estado, tipo, plataforma o
                usuario para enfocarte en lo pendiente.
              </li>
              <li>
                <strong>Marca como atendido</strong> cuando hayas resuelto o
                respondido; usa las notas para dejar registro de la decisión
                (útil al revisar meses después).
              </li>
              <li>
                <strong>Responde por correo</strong> con el botón de cada
                tarjeta: abre tu cliente con el asunto y contexto ya escritos.
              </li>
              <li>
                <strong>Exporta a CSV</strong> para analizar tendencias o
                compartir con el equipo.
              </li>
            </ul>
          </Card>
        </div>
      )}

      <Card titulo="Feedback recibido" icono={<span>💬</span>}>
        <ListaFeedback
          items={items}
          filtroUsuarioInicial={searchParams.usuario ?? ''}
        />
      </Card>
    </div>
  );
}
