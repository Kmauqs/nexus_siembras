/** Clasificación de apps que comparten el proyecto Supabase NEXUS. */

export type AppOrigen = 'siembras' | 'fincontrol';

/** FINCONTROL usa tipos `fincontrol_*` en `feedback_encuestas`. */
export function origenDesdeTipoFeedback(tipo: string | null | undefined): AppOrigen {
  const t = (tipo ?? '').toLowerCase();
  if (t.startsWith('fincontrol')) return 'fincontrol';
  return 'siembras';
}

export function etiquetaApp(origen: AppOrigen): string {
  return origen === 'fincontrol' ? 'FINCONTROL' : 'NEXUS Siembras';
}

export function esFeedbackFincontrol(tipo: string | null | undefined): boolean {
  return origenDesdeTipoFeedback(tipo) === 'fincontrol';
}
