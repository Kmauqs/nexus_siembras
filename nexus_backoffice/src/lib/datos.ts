import 'server-only';
import { supabaseAdmin } from './supabase/admin';
import type { PuntoPatologia } from '@/components/heatmap';

export type StatsPublicas = {
  usuarios: number;
  usuarios_activos_30d: number;
  predios: number;
  lotes: number;
  cultivos: number;
  cultivos_activos: number;
  variedades: number;
  reportes_patologias: number;
  tratamientos: number;
  paises: number;
};

const STATS_VACIAS: StatsPublicas = {
  usuarios: 0, usuarios_activos_30d: 0, predios: 0, lotes: 0,
  cultivos: 0, cultivos_activos: 0, variedades: 0,
  reportes_patologias: 0, tratamientos: 0, paises: 0,
};

/** Agregados generales. Nunca lanza: si falla, devuelve ceros. */
export async function obtenerStats(): Promise<StatsPublicas> {
  try {
    const { data, error } = await supabaseAdmin().rpc('stats_publicas');
    if (error) throw error;
    return { ...STATS_VACIAS, ...(data as Partial<StatsPublicas>) };
  } catch {
    return STATS_VACIAS;
  }
}

export type FilaPais = { pais_iso2: string; usuarios: number; predios: number };

export async function obtenerUsuariosPorPais(): Promise<FilaPais[]> {
  try {
    const { data, error } = await supabaseAdmin().rpc(
      'stats_usuarios_por_pais'
    );
    if (error) throw error;
    return (data ?? []) as FilaPais[];
  } catch {
    return [];
  }
}

export async function obtenerHeatmap(): Promise<PuntoPatologia[]> {
  try {
    const { data, error } = await supabaseAdmin().rpc(
      'stats_heatmap_patologias'
    );
    if (error) throw error;
    return (data ?? []) as PuntoPatologia[];
  } catch {
    return [];
  }
}

/** Config centralizada (app_config) como mapa clave→valor. */
export async function obtenerConfig(): Promise<Record<string, string>> {
  try {
    const { data, error } = await supabaseAdmin()
      .from('app_config')
      .select('clave, valor');
    if (error) throw error;
    return Object.fromEntries(
      (data ?? []).map((r) => [r.clave as string, (r.valor ?? '') as string])
    );
  } catch {
    return {};
  }
}
