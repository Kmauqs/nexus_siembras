-- =====================================================================
-- Migración 0008 — Banco comunitario de variedades (Fase B1, 2026-07-20)
-- Tabla pública alimentada por la comunidad para autocompletar el modal
-- "Nueva variedad". Ejecutar DESPUÉS de 0007. Idempotente.
--
-- Diseño:
--   - Lectura: cualquier usuario autenticado.
--   - Escritura: SOLO vía RPC `contribuir_variedad` (SECURITY DEFINER):
--     upsert por (nombre, especie) que incrementa el contador de aportes
--     y completa campos vacíos sin machacar los existentes. Sin policies
--     de INSERT/UPDATE directas — nadie puede editar o borrar aportes
--     ajenos.
--   - Anónimo de cara a la comunidad: `created_by` se guarda solo para
--     auditoría (no se expone en la búsqueda de la app).
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.variedades_comunitarias (
  id               bigserial PRIMARY KEY,
  nombre_comun     text NOT NULL,
  especie          text,
  metodo_siembra   text,        -- directa | germinador
  germinador_dias  int,
  cosecha_min_dias int,
  cosecha_max_dias int,
  tipo_abono1      text,
  tipo_abono2      text,
  abono2_dias      int,
  fuente           text,        -- fuente agronómica declarada
  contribuciones   int NOT NULL DEFAULT 1,
  created_by       uuid DEFAULT auth.uid(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- Clave natural: nombre + especie, sin distinguir mayúsculas.
CREATE UNIQUE INDEX IF NOT EXISTS variedades_comunitarias_natural_key
  ON public.variedades_comunitarias
  (lower(nombre_comun), lower(coalesce(especie, '')));

ALTER TABLE public.variedades_comunitarias ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS variedades_read ON public.variedades_comunitarias;
CREATE POLICY variedades_read ON public.variedades_comunitarias
  FOR SELECT USING (auth.role() = 'authenticated');
-- Sin policies INSERT/UPDATE/DELETE: escritura solo por la RPC.

CREATE OR REPLACE FUNCTION public.contribuir_variedad(
  p_nombre       text,
  p_especie      text DEFAULT NULL,
  p_metodo       text DEFAULT NULL,
  p_germinador   int  DEFAULT NULL,
  p_cosecha_min  int  DEFAULT NULL,
  p_cosecha_max  int  DEFAULT NULL,
  p_abono1       text DEFAULT NULL,
  p_abono2       text DEFAULT NULL,
  p_abono2_dias  int  DEFAULT NULL,
  p_fuente       text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'contribuir_variedad requiere sesión';
  END IF;
  IF p_nombre IS NULL OR length(trim(p_nombre)) < 2 THEN
    RETURN; -- aporte sin nombre útil: ignorar en silencio
  END IF;
  INSERT INTO variedades_comunitarias AS v (
    nombre_comun, especie, metodo_siembra, germinador_dias,
    cosecha_min_dias, cosecha_max_dias, tipo_abono1, tipo_abono2,
    abono2_dias, fuente, created_by
  ) VALUES (
    trim(p_nombre),
    nullif(trim(coalesce(p_especie, '')), ''),
    p_metodo, p_germinador, p_cosecha_min, p_cosecha_max,
    nullif(trim(coalesce(p_abono1, '')), ''),
    nullif(trim(coalesce(p_abono2, '')), ''),
    p_abono2_dias,
    nullif(trim(coalesce(p_fuente, '')), ''),
    auth.uid()
  )
  ON CONFLICT (lower(nombre_comun), lower(coalesce(especie, '')))
  DO UPDATE SET
    contribuciones   = v.contribuciones + 1,
    -- Completar huecos con el nuevo aporte, sin machacar lo existente.
    metodo_siembra   = coalesce(v.metodo_siembra,   excluded.metodo_siembra),
    germinador_dias  = coalesce(v.germinador_dias,  excluded.germinador_dias),
    cosecha_min_dias = coalesce(v.cosecha_min_dias, excluded.cosecha_min_dias),
    cosecha_max_dias = coalesce(v.cosecha_max_dias, excluded.cosecha_max_dias),
    tipo_abono1      = coalesce(v.tipo_abono1,      excluded.tipo_abono1),
    tipo_abono2      = coalesce(v.tipo_abono2,      excluded.tipo_abono2),
    abono2_dias      = coalesce(v.abono2_dias,      excluded.abono2_dias),
    fuente           = coalesce(v.fuente,           excluded.fuente),
    updated_at       = now();
END $$;

REVOKE ALL ON FUNCTION public.contribuir_variedad FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.contribuir_variedad TO authenticated;

-- Versión de esquema. NOTA: el cliente sigue requiriendo v7 mínimo —
-- el banco de variedades degrada con gracia si la tabla no existe.
INSERT INTO public.schema_meta (id, version)
VALUES (1, 8)
ON CONFLICT (id) DO UPDATE SET version = 8, applied_at = now();

-- Verificación:
-- SELECT version FROM public.schema_meta;                       -- → 8
-- SELECT count(*) FROM public.variedades_comunitarias;          -- → 0
