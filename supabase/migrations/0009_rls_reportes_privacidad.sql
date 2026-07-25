-- =====================================================================
-- Migración 0009 — Privacidad de patologias_reportadas
-- (revisión de código 2026-07-20, hallazgo #6). Idempotente.
--
-- Antes: la policy SELECT de la TABLA BASE permitía a cualquier usuario
-- autenticado leer todas las filas (incluido owner_id, que vincula el
-- reporte con la cuenta). La vista anonimizada
-- `patologias_reportadas_publica` ya existía pero nada impedía saltársela.
--
-- Ahora: la tabla base solo es legible por su dueño; la lectura
-- comunitaria (mapa de calor global) debe hacerse por la VISTA, que
-- expone únicamente campos anonimizados y filas con consentimiento.
-- El cliente Flutter actual no lee la tabla remota todavía (el heatmap
-- usa la copia local) — cuando se implemente la lectura comunitaria,
-- usar `patologias_reportadas_publica`.
-- =====================================================================

DROP POLICY IF EXISTS patologias_reportadas_read
  ON public.patologias_reportadas;
CREATE POLICY patologias_reportadas_read ON public.patologias_reportadas
  FOR SELECT USING (owner_id = auth.uid() AND deleted_at IS NULL);

-- La vista pública anonimizada conserva su GRANT a authenticated
-- (definida en schema_3e.sql). Postgres evalúa las vistas con los
-- permisos del dueño de la vista (security definer implícito de vistas
-- clásicas), por lo que sigue funcionando aunque la tabla base ya no
-- sea legible directamente. Se re-otorga por idempotencia:
GRANT SELECT ON public.patologias_reportadas_publica TO authenticated;

INSERT INTO public.schema_meta (id, version)
VALUES (1, 9)
ON CONFLICT (id) DO UPDATE SET version = 9, applied_at = now();

-- Verificación:
-- SELECT version FROM public.schema_meta;  -- → 9
-- Como usuario B: SELECT count(*) FROM patologias_reportadas;          -- → solo las propias
-- Como usuario B: SELECT count(*) FROM patologias_reportadas_publica;  -- → todas las anónimas
