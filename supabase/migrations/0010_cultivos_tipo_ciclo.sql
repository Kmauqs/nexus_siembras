-- Tipo de ciclo productivo en cultivos (ciclo único vs perenne)
ALTER TABLE public.cultivos
  ADD COLUMN IF NOT EXISTS tipo_cultivo TEXT NOT NULL DEFAULT 'ciclo_unico',
  ADD COLUMN IF NOT EXISTS cosecha1_dias INTEGER,
  ADD COLUMN IF NOT EXISTS cosecha2_dias INTEGER,
  ADD COLUMN IF NOT EXISTS periodicidad_cosecha_dias INTEGER,
  ADD COLUMN IF NOT EXISTS esperanza_vida_dias INTEGER;

COMMENT ON COLUMN public.cultivos.tipo_cultivo IS
  'ciclo_unico | perenne';
COMMENT ON COLUMN public.cultivos.cosecha1_dias IS
  'Días desde fecha base fenológica hasta Cosecha 1 (ciclo único)';
COMMENT ON COLUMN public.cultivos.cosecha2_dias IS
  'Días desde fecha base fenológica hasta Cosecha 2 (ciclo único)';
COMMENT ON COLUMN public.cultivos.periodicidad_cosecha_dias IS
  'Días entre cosechas periódicas (cultivo perenne)';
COMMENT ON COLUMN public.cultivos.esperanza_vida_dias IS
  'Esperanza de vida del cultivo hasta renovación (cultivo perenne)';
