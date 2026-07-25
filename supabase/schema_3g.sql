-- =============================================================
-- NEXUS Siembras — Schema Postgres Fase 3g
-- Trazabilidad de tareas completadas por usuario
-- =============================================================
--
-- Añade `created_by_user_id UUID` a `tareas_completadas` con un trigger
-- BEFORE INSERT que la autopobla desde `auth.uid()` cuando el cliente no
-- envía el valor explícitamente.
--
-- Esto permite:
--   - Dashboard: desglose de HH por usuario que las registró.
--   - Cronograma: mostrar autor en cada tarjeta de tarea.
--   - Auditoría: saber qué colaborador aplicó cada abono, poda, etc.
--
-- Comportamiento:
--   - Filas existentes (legacy) quedan con created_by_user_id = NULL.
--   - En modo local (sin sesión) el cliente envía NULL → el trigger no
--     tiene auth.uid() disponible (retorna NULL) → queda NULL.
--   - Al sincronizar desde local con sesión, el sync sube el UUID real.
-- =============================================================

-- 1. Añadir columna (idempotente)
ALTER TABLE public.tareas_completadas
  ADD COLUMN IF NOT EXISTS created_by_user_id UUID
    REFERENCES auth.users(id) ON DELETE SET NULL;

-- 2. Índice para consultas de desglose por usuario
CREATE INDEX IF NOT EXISTS idx_tareas_completadas_created_by
  ON public.tareas_completadas(created_by_user_id);

-- 3. Trigger: autopoblar con auth.uid() si el cliente no lo envió
CREATE OR REPLACE FUNCTION public.autopopular_tarea_autor()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.created_by_user_id IS NULL THEN
    NEW.created_by_user_id := auth.uid();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS tareas_completadas_autor
  ON public.tareas_completadas;
CREATE TRIGGER tareas_completadas_autor
  BEFORE INSERT ON public.tareas_completadas
  FOR EACH ROW EXECUTE FUNCTION public.autopopular_tarea_autor();

-- 4. Verificación: cuenta filas con y sin autor
SELECT
  COUNT(*) FILTER (WHERE created_by_user_id IS NOT NULL) AS con_autor,
  COUNT(*) FILTER (WHERE created_by_user_id IS NULL)     AS sin_autor_legacy
FROM public.tareas_completadas;

-- FIN
