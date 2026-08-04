'use server';

import { revalidatePath } from 'next/cache';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { obtenerSesionAdmin } from '@/lib/auth';

export type Resultado = { ok: boolean; mensaje: string };

/** Marca/desmarca como atendido y guarda notas de gestión. */
export async function actualizarFeedback(
  id: number,
  cambios: { atendido?: boolean; notas_gestion?: string }
): Promise<Resultado> {
  if (!(await obtenerSesionAdmin())) {
    return { ok: false, mensaje: 'No autorizado.' };
  }
  const patch: Record<string, unknown> = {};
  if (typeof cambios.atendido === 'boolean') patch.atendido = cambios.atendido;
  if (typeof cambios.notas_gestion === 'string') {
    patch.notas_gestion = cambios.notas_gestion.trim() || null;
  }
  if (!Object.keys(patch).length) {
    return { ok: false, mensaje: 'Nada que actualizar.' };
  }

  const { error } = await supabaseAdmin()
    .from('feedback_encuestas')
    .update(patch)
    .eq('id', id);
  if (error) return { ok: false, mensaje: error.message };

  revalidatePath('/admin/feedback');
  revalidatePath('/admin');
  return { ok: true, mensaje: 'Feedback actualizado.' };
}

/** Marca varios como atendidos de una vez. */
export async function marcarLoteAtendido(
  ids: number[]
): Promise<Resultado> {
  if (!(await obtenerSesionAdmin())) {
    return { ok: false, mensaje: 'No autorizado.' };
  }
  if (!ids.length) return { ok: false, mensaje: 'Sin selección.' };

  const { error } = await supabaseAdmin()
    .from('feedback_encuestas')
    .update({ atendido: true })
    .in('id', ids);
  if (error) return { ok: false, mensaje: error.message };

  revalidatePath('/admin/feedback');
  revalidatePath('/admin');
  return { ok: true, mensaje: `${ids.length} marcado(s) como atendido(s).` };
}
