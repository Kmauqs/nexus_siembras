-- =============================================================
-- NEXUS Siembras — Schema Postgres Fase 3e v4
-- Fix RLS: auto-aceptación de shares + backfill existentes
-- =============================================================
--
-- Problema: rol_en_predio() filtra por `aceptado_at IS NOT NULL`.
-- Si por alguna razón un share tiene aceptado_at=null (bug pasado o
-- inserción manual), las policies SELECT/UPDATE de cultivos, lotes,
-- inventarios, etc. no ven ese predio → el colaborador no baja el
-- contenido asociado.
--
-- Fix:
--   1. Asegurar que el trigger autoaceptar_share existe.
--   2. Backfill: setear aceptado_at = COALESCE(aceptado_at, invitado_at, NOW())
--      para todos los shares existentes.
--   3. Simplificar rol_en_predio: si el share existe, se considera aceptado.
-- =============================================================

-- 1. Trigger de auto-aceptación (idempotente)
CREATE OR REPLACE FUNCTION public.autoaceptar_share()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.aceptado_at IS NULL THEN
    NEW.aceptado_at := NOW();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS predio_shares_autoaceptar ON public.predio_shares;
CREATE TRIGGER predio_shares_autoaceptar
  BEFORE INSERT ON public.predio_shares
  FOR EACH ROW EXECUTE FUNCTION public.autoaceptar_share();

-- 2. Backfill: aceptar todos los shares existentes que no lo estén
UPDATE public.predio_shares
SET aceptado_at = COALESCE(aceptado_at, invitado_at, NOW())
WHERE aceptado_at IS NULL;

-- 3. Simplificar rol_en_predio: si hay share, ya es aceptado
CREATE OR REPLACE FUNCTION public.rol_en_predio(p_predio_id BIGINT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN EXISTS (
      SELECT 1 FROM public.predios
      WHERE id = p_predio_id AND owner_id = auth.uid()
    ) THEN 'propietario'
    ELSE (
      SELECT rol FROM public.predio_shares
      WHERE predio_id = p_predio_id
        AND shared_with_id = auth.uid()
      LIMIT 1
    )
  END;
$$;

-- Verificación: cuenta shares con aceptado_at populado
SELECT
  COUNT(*) FILTER (WHERE aceptado_at IS NOT NULL) AS aceptados,
  COUNT(*) FILTER (WHERE aceptado_at IS NULL) AS pendientes
FROM public.predio_shares;

-- FIN
