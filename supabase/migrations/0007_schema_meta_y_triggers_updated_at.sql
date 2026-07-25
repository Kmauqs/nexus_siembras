-- =====================================================================
-- Migración 0007 — Auditoría 2026-07-19 (S6 + P5)
-- Ejecutar en el SQL Editor del dashboard de Supabase DESPUÉS de haber
-- aplicado, en orden: schema.sql → schema_3e.sql → schema_3e_v2..v4 →
-- schema_3g.sql → fix_predio_shares_updated_at.sql (ver README.md).
-- Idempotente: puede re-ejecutarse sin efectos adversos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. S6 — Tabla de versión de esquema.
-- El cliente (SyncService._verificarSchemaRemoto) la consulta antes de
-- sincronizar y bloquea el sync si el servidor está desactualizado
-- respecto a `SyncService.schemaRemotoRequerido`.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.schema_meta (
  id      int PRIMARY KEY DEFAULT 1 CHECK (id = 1),  -- singleton
  version int NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.schema_meta (id, version)
VALUES (1, 7)
ON CONFLICT (id) DO UPDATE SET version = 7, applied_at = now();

ALTER TABLE public.schema_meta ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS schema_meta_read ON public.schema_meta;
CREATE POLICY schema_meta_read ON public.schema_meta
  FOR SELECT USING (auth.role() = 'authenticated');
-- Sin policies INSERT/UPDATE/DELETE: solo modificable como service_role
-- desde el dashboard (al aplicar migraciones).

-- ---------------------------------------------------------------------
-- 2. P5 — `updated_at` autoritativo del servidor.
-- Problema: el last-write-wins comparaba timestamps de relojes de
-- dispositivos distintos; un teléfono con la hora ADELANTADA machacaba
-- sistemáticamente los cambios de los demás colaboradores.
-- Solución: LEAST(valor_cliente, now()) — un cliente no puede fechar
-- sus escrituras en el futuro del servidor. Se usa LEAST y no now()
-- directo para no romper la detección de "eco" del cliente (el pull de
-- la propia fila recién subida no debe parecer más nueva y provocar
-- re-push infinito en clientes con reloj atrasado).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cap_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := LEAST(COALESCE(NEW.updated_at, now()), now());
  RETURN NEW;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'predios', 'lotes', 'proveedores', 'cultivos', 'eventos_cultivo',
    'inventarios', 'compras', 'analisis_suelo', 'condiciones_predio',
    'predio_shares'
    -- tareas_completadas: inmutables, sin columna updated_at → excluida.
  ]
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_cap_updated_at ON public.%I', t);
    EXECUTE format(
      'CREATE TRIGGER trg_cap_updated_at BEFORE INSERT OR UPDATE ON public.%I
       FOR EACH ROW EXECUTE FUNCTION public.cap_updated_at()', t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 3. Verificación
-- ---------------------------------------------------------------------
-- SELECT version, applied_at FROM public.schema_meta;         -- → 7
-- SELECT tgname, tgrelid::regclass FROM pg_trigger
--   WHERE tgname = 'trg_cap_updated_at';                      -- → 10 filas
