-- 0022_inventario_categorias.sql
-- Categorías de inventario/compras, ubicación de herramientas y grado
-- poscosecha. Idempotente. schema_meta → 19.
-- Fecha: 2026-11-22.

ALTER TABLE public.inventarios
  ADD COLUMN IF NOT EXISTS categoria text,
  ADD COLUMN IF NOT EXISTS ubicacion text,
  ADD COLUMN IF NOT EXISTS grado_poscosecha text;

ALTER TABLE public.compras
  ADD COLUMN IF NOT EXISTS categoria text;

COMMENT ON COLUMN public.inventarios.categoria IS
  'insumos | semillas_esquejes | herramientas_equipos | poscosecha';
COMMENT ON COLUMN public.inventarios.ubicacion IS
  'Ubicación actual (herramientas / equipos)';
COMMENT ON COLUMN public.inventarios.grado_poscosecha IS
  'primera | segunda | descarte';
COMMENT ON COLUMN public.compras.categoria IS
  'Misma taxonomía que inventarios.categoria';

-- Backfill razonable desde tipo de compra (solo filas sin categoría).
UPDATE public.compras
SET categoria = CASE tipo
  WHEN 'semilla' THEN 'semillas_esquejes'
  WHEN 'abono' THEN 'insumos'
  WHEN 'pesticida' THEN 'insumos'
  WHEN 'herramienta' THEN 'herramientas_equipos'
  ELSE 'insumos'
END
WHERE categoria IS NULL AND tipo IS NOT NULL;

INSERT INTO public.schema_meta (id, version)
VALUES (1, 19)
ON CONFLICT (id) DO UPDATE
SET version = GREATEST(public.schema_meta.version, 19),
    applied_at = NOW();

-- SELECT version FROM public.schema_meta;  -- → ≥ 19
