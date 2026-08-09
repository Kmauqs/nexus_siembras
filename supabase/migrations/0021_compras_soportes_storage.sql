-- =====================================================================
-- Migración 0021 — Soportes de compras en Supabase Storage
-- Fecha: 2026-08-06. Idempotente. schema_meta → 18.
--
-- Problema: el comprobante (PDF/foto) solo vivía en disco local
-- (`compras.soporte_path` del cliente). Al sincronizar, los co-propietarios
-- veían la fila de la compra pero no el archivo → el ZIP "completo" omitía
-- facturas cargadas por otras cuentas.
--
-- Esquema recomendado (y el que aplica esta migración):
--   1. Binario en Storage (bucket privado `compras-soportes`).
--   2. Metadatos en `public.compras`:
--        soporte_storage_path  — object key en el bucket
--        soporte_nombre         — nombre de archivo para ZIP/UI
--        soporte_tipo          — MIME (application/pdf | image/*)
--   3. Path del objeto: `{predio_id}/{compra_id}/{nombre_archivo}`
--   4. RLS Storage = `es_propietario_predio(predio_id)` (misma regla que
--      la tabla compras: dueño + co-propietarios).
--
-- Alternativas descartadas:
--   - BYTEA/base64 en Postgres: infla filas, backups y sync JSON.
--   - Bucket público: expone facturas comerciales.
--   - Tabla hija `compra_adjuntos`: innecesaria mientras haya 1 soporte/compra.
-- =====================================================================

DO $$
BEGIN
  IF to_regclass('public.compras') IS NULL THEN
    RAISE EXCEPTION 'Falta public.compras. Aplica schema.sql antes de 0021.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'es_propietario_predio'
  ) THEN
    RAISE EXCEPTION
      'Falta es_propietario_predio(). Aplica schema_3e_v2.sql antes de 0021.';
  END IF;
END $$;

ALTER TABLE public.compras
  ADD COLUMN IF NOT EXISTS soporte_storage_path text,
  ADD COLUMN IF NOT EXISTS soporte_nombre text,
  ADD COLUMN IF NOT EXISTS soporte_tipo text;

COMMENT ON COLUMN public.compras.soporte_storage_path IS
  'Object key en bucket compras-soportes: {predio_id}/{compra_id}/{nombre}';
COMMENT ON COLUMN public.compras.soporte_nombre IS
  'Nombre de archivo del comprobante (para UI y ZIP).';
COMMENT ON COLUMN public.compras.soporte_tipo IS
  'MIME del comprobante (application/pdf o image/*).';

CREATE INDEX IF NOT EXISTS idx_compras_soporte_storage
  ON public.compras (soporte_storage_path)
  WHERE soporte_storage_path IS NOT NULL AND deleted_at IS NULL;

-- Bucket privado (no listar públicamente).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'compras-soportes',
  'compras-soportes',
  false,
  20971520, -- 20 MiB
  ARRAY[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/jpg'
  ]::text[]
)
ON CONFLICT (id) DO UPDATE
SET
  public = false,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Policies Storage: primer segmento del path = predio_id remoto.
DROP POLICY IF EXISTS compras_soportes_select ON storage.objects;
CREATE POLICY compras_soportes_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'compras-soportes'
    AND (storage.foldername(name))[1] ~ '^[0-9]+$'
    AND public.es_propietario_predio(((storage.foldername(name))[1])::bigint)
  );

DROP POLICY IF EXISTS compras_soportes_insert ON storage.objects;
CREATE POLICY compras_soportes_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'compras-soportes'
    AND (storage.foldername(name))[1] ~ '^[0-9]+$'
    AND public.es_propietario_predio(((storage.foldername(name))[1])::bigint)
  );

DROP POLICY IF EXISTS compras_soportes_update ON storage.objects;
CREATE POLICY compras_soportes_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'compras-soportes'
    AND (storage.foldername(name))[1] ~ '^[0-9]+$'
    AND public.es_propietario_predio(((storage.foldername(name))[1])::bigint)
  )
  WITH CHECK (
    bucket_id = 'compras-soportes'
    AND (storage.foldername(name))[1] ~ '^[0-9]+$'
    AND public.es_propietario_predio(((storage.foldername(name))[1])::bigint)
  );

DROP POLICY IF EXISTS compras_soportes_delete ON storage.objects;
CREATE POLICY compras_soportes_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'compras-soportes'
    AND (storage.foldername(name))[1] ~ '^[0-9]+$'
    AND public.es_propietario_predio(((storage.foldername(name))[1])::bigint)
  );

INSERT INTO public.schema_meta (id, version)
VALUES (1, 18)
ON CONFLICT (id) DO UPDATE
SET version = GREATEST(public.schema_meta.version, 18),
    applied_at = NOW();

-- Verificación:
-- SELECT version FROM public.schema_meta;  -- → ≥ 18
-- SELECT id, public FROM storage.buckets WHERE id = 'compras-soportes';
