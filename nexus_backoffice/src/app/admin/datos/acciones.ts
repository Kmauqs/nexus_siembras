'use server';

import { revalidatePath } from 'next/cache';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { obtenerSesionAdmin } from '@/lib/auth';

export type Tabla =
  | 'variedades_comunitarias'
  | 'patologias_reportadas'
  | 'patologia_tratamientos';

export type Resultado = { ok: boolean; mensaje: string };

/** Campos editables por tabla (whitelist: nunca aceptar claves libres). */
const CAMPOS: Record<Tabla, string[]> = {
  variedades_comunitarias: [
    'nombre_comun', 'especie', 'metodo_siembra', 'germinador_dias',
    'cosecha_min_dias', 'cosecha_max_dias', 'tipo_abono1', 'tipo_abono2',
    'abono2_dias', 'fuente',
  ],
  patologias_reportadas: [
    'patologia_nombre', 'patologia_cientifico', 'planta_nombre',
    'severidad', 'sintomas', 'pais_iso2', 'region_nombre',
    'municipio_nombre', 'notas_admin',
  ],
  patologia_tratamientos: [
    'patologia_nombre', 'patologia_cientifico', 'pais_iso2', 'tipo',
    'titulo', 'descripcion', 'producto', 'dosis', 'frecuencia',
    'amigable_ambiente', 'fuente', 'fuente_url',
  ],
};

const NUMERICOS = new Set([
  'germinador_dias', 'cosecha_min_dias', 'cosecha_max_dias', 'abono2_dias',
]);
const BOOLEANOS = new Set(['amigable_ambiente']);

function sanear(tabla: Tabla, entrada: Record<string, unknown>) {
  const out: Record<string, unknown> = {};
  for (const campo of CAMPOS[tabla]) {
    if (!(campo in entrada)) continue;
    const v = entrada[campo];
    if (v === '' || v === null || v === undefined) {
      out[campo] = null;
    } else if (NUMERICOS.has(campo)) {
      const n = Number(v);
      out[campo] = Number.isFinite(n) ? n : null;
    } else if (BOOLEANOS.has(campo)) {
      out[campo] = v === true || v === 'true';
    } else {
      out[campo] = String(v).trim();
    }
  }
  return out;
}

export async function guardarFila(
  tabla: Tabla,
  id: number | null,
  valores: Record<string, unknown>
): Promise<Resultado> {
  if (!(await obtenerSesionAdmin())) {
    return { ok: false, mensaje: 'No autorizado.' };
  }
  const datos = sanear(tabla, valores);
  if (Object.keys(datos).length === 0) {
    return { ok: false, mensaje: 'Nada que guardar.' };
  }

  const sb = supabaseAdmin();
  const { error } =
    id === null
      ? await sb.from(tabla).insert(datos)
      : await sb.from(tabla).update(datos).eq('id', id);

  if (error) return { ok: false, mensaje: error.message };
  revalidatePath('/admin/datos');
  return {
    ok: true,
    mensaje: id === null ? 'Registro creado.' : 'Cambios guardados.',
  };
}

export async function eliminarFila(
  tabla: Tabla,
  id: number
): Promise<Resultado> {
  if (!(await obtenerSesionAdmin())) {
    return { ok: false, mensaje: 'No autorizado.' };
  }

  // Patrimonio comunitario (decisión 2026-08-04): los reportes de
  // patologías NO se borran nunca — son de la comunidad, no de quien los
  // creó. Para contenido inadecuado usa "Ocultar" (archiva sin destruir).
  if (tabla === 'patologias_reportadas') {
    return {
      ok: false,
      mensaje:
        'Los reportes de patologías no se eliminan: son patrimonio de la ' +
        'comunidad. Usa "Ocultar" si el contenido es inadecuado.',
    };
  }

  const { error } = await supabaseAdmin().from(tabla).delete().eq('id', id);
  if (error) return { ok: false, mensaje: error.message };
  revalidatePath('/admin/datos');
  return { ok: true, mensaje: 'Registro eliminado.' };
}

/**
 * Moderación de un reporte: lo oculta del mapa público sin destruirlo
 * (o lo restaura). Reservado para contenido inadecuado o duplicado.
 */
export async function moderarReporte(
  id: number,
  ocultar: boolean
): Promise<Resultado> {
  if (!(await obtenerSesionAdmin())) {
    return { ok: false, mensaje: 'No autorizado.' };
  }
  const { error } = await supabaseAdmin()
    .from('patologias_reportadas')
    .update({
      deleted_at: ocultar ? new Date().toISOString() : null,
      updated_at: new Date().toISOString(),
    })
    .eq('id', id);
  if (error) return { ok: false, mensaje: error.message };
  revalidatePath('/admin/datos');
  return {
    ok: true,
    mensaje: ocultar
      ? 'Reporte oculto del mapa público (conservado en la base).'
      : 'Reporte restaurado al mapa público.',
  };
}

/**
 * Marca un reporte como atendido: reinicia su contador de inactividad,
 * de modo que vuelve a aparecer como «activa» en el mapa.
 */
export async function atenderReporte(
  id: number,
  notas?: string
): Promise<Resultado> {
  if (!(await obtenerSesionAdmin())) {
    return { ok: false, mensaje: 'No autorizado.' };
  }
  const ahora = new Date().toISOString();
  const { error } = await supabaseAdmin()
    .from('patologias_reportadas')
    .update({
      ultima_actividad_at: ahora,
      atendido_por_admin_at: ahora,
      updated_at: ahora,
      ...(notas ? { notas_admin: notas } : {}),
    })
    .eq('id', id);
  if (error) return { ok: false, mensaje: error.message };
  revalidatePath('/admin/datos');
  revalidatePath('/');
  return {
    ok: true,
    mensaje: 'Reporte atendido: vuelve a contar como foco activo.',
  };
}
