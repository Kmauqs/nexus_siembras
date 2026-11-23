import 'server-only';
import { supabaseAdmin } from './supabase/admin';
import { esFeedbackFincontrol } from './apps';

export type StatsFincontrol = {
  households: number;
  miembros: number;
  movimientos_30d: number;
  feedback_total: number;
  feedback_pendiente: number;
  calificacion_media: number | null;
  disponible: boolean;
};

export type SerieFeedbackDia = {
  dia: string;
  feedbacks: number;
  bugs: number;
};

type FeedbackFila = {
  created_at: string;
  tipo: string;
  calificacion: number | null;
  atendido: boolean;
};

/**
 * Agregados de FINCONTROL para el panel. Las tablas de finanzas viven en el
 * mismo proyecto Supabase; si aún no están aplicadas, `disponible` queda false.
 */
export async function obtenerStatsFincontrol(): Promise<StatsFincontrol> {
  const vacio: StatsFincontrol = {
    households: 0,
    miembros: 0,
    movimientos_30d: 0,
    feedback_total: 0,
    feedback_pendiente: 0,
    calificacion_media: null,
    disponible: false,
  };

  const sb = supabaseAdmin();
  const hace30 = new Date();
  hace30.setDate(hace30.getDate() - 30);

  try {
    const [hh, mem, tx, fb] = await Promise.all([
      sb.from('households').select('id', { count: 'exact', head: true }),
      sb.from('memberships').select('id', { count: 'exact', head: true }),
      sb
        .from('transactions')
        .select('id', { count: 'exact', head: true })
        .gte('created_at', hace30.toISOString()),
      sb
        .from('feedback_encuestas')
        .select('tipo, calificacion, atendido')
        .ilike('tipo', 'fincontrol%'),
    ]);

    // Si households falla (tabla ausente), no hay dominio FINCONTROL.
    if (hh.error) return vacio;

    const feedbacks = (fb.data ?? []) as Pick<
      FeedbackFila,
      'tipo' | 'calificacion' | 'atendido'
    >[];
    const conCalif = feedbacks.filter((f) => f.calificacion != null);
    const media =
      conCalif.length > 0
        ? conCalif.reduce((s, f) => s + (f.calificacion ?? 0), 0) /
          conCalif.length
        : null;

    return {
      households: hh.count ?? 0,
      miembros: mem.error ? 0 : (mem.count ?? 0),
      movimientos_30d: tx.error ? 0 : (tx.count ?? 0),
      feedback_total: feedbacks.length,
      feedback_pendiente: feedbacks.filter((f) => !f.atendido).length,
      calificacion_media: media,
      disponible: true,
    };
  } catch {
    return vacio;
  }
}

/** Serie diaria de feedback FINCONTROL (últimos N días) desde feedback_encuestas. */
export async function obtenerSerieFeedbackFincontrol(
  dias = 30
): Promise<SerieFeedbackDia[]> {
  const sb = supabaseAdmin();
  const desde = new Date();
  desde.setDate(desde.getDate() - dias);
  try {
    const { data, error } = await sb
      .from('feedback_encuestas')
      .select('created_at, tipo')
      .ilike('tipo', 'fincontrol%')
      .gte('created_at', desde.toISOString())
      .order('created_at', { ascending: true });
    if (error) return [];

    const mapa = new Map<string, SerieFeedbackDia>();
    for (let i = 0; i < dias; i++) {
      const d = new Date(desde);
      d.setDate(desde.getDate() + i);
      const key = d.toISOString().slice(0, 10);
      mapa.set(key, { dia: key.slice(5), feedbacks: 0, bugs: 0 });
    }
    for (const row of (data ?? []) as FeedbackFila[]) {
      const key = row.created_at.slice(0, 10);
      const slot = mapa.get(key);
      if (!slot) continue;
      slot.feedbacks += 1;
      if (row.tipo.includes('bug') || row.tipo === 'fincontrol_sync') {
        slot.bugs += 1;
      }
    }
    return Array.from(mapa.values());
  } catch {
    return [];
  }
}

export async function listarFeedbackRecienteFincontrol(limit = 12) {
  const sb = supabaseAdmin();
  try {
    const { data } = await sb
      .from('feedback_encuestas')
      .select(
        'id, created_at, tipo, calificacion, comentario, email_usuario, app_version, plataforma, atendido'
      )
      .ilike('tipo', 'fincontrol%')
      .order('created_at', { ascending: false })
      .limit(limit);
    return (data ?? []).filter((f) =>
      esFeedbackFincontrol((f as { tipo: string }).tipo)
    );
  } catch {
    return [];
  }
}
