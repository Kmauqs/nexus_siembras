-- =====================================================================
-- Migración 0018 — Patrimonio comunitario y estado de los reportes
-- Fecha: 2026-08-04. Idempotente. schema_meta → 15.
--
-- Regla de negocio (decisión 2026-08-04): lo que la comunidad aporta es
-- patrimonio de la comunidad y NO se elimina cuando el autor se va.
--
--   1. VARIEDADES: se conservan siempre. Al borrarse la cuenta, solo se
--      anonimiza `created_by` (ya no había FK, así que nunca hubo riesgo
--      de CASCADE; ahora además se limpia el UUID huérfano).
--   2. REPORTES DE PATOLOGÍAS: nunca se borran — ni al eliminar la
--      cuenta ni desde el backoffice. Se anonimizan y siguen alimentando
--      el mapa comunitario. Se retiran los DELETE de las migraciones
--      0014 y 0017 redefiniendo esas funciones.
--   3. ESTADO DEL REPORTE: un reporte se considera «desatendido» (se
--      pinta gris) tras N días sin actividad — ni del administrador ni
--      de la comunidad en coordenadas cercanas. Un reporte nuevo cerca
--      «reactiva» a sus vecinos: el foco sigue vivo.
--
-- Parámetros configurables desde el backoffice (app_config):
--   · patologia_dias_desatendida  (por defecto 60)
--   · patologia_radio_km          (por defecto 5)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Columnas de actividad
-- ---------------------------------------------------------------------
ALTER TABLE public.patologias_reportadas
  ADD COLUMN IF NOT EXISTS ultima_actividad_at timestamptz;

ALTER TABLE public.patologias_reportadas
  ADD COLUMN IF NOT EXISTS atendido_por_admin_at timestamptz;

ALTER TABLE public.patologias_reportadas
  ADD COLUMN IF NOT EXISTS notas_admin text;

-- Backfill: la actividad inicial es la propia creación del reporte.
UPDATE public.patologias_reportadas
SET ultima_actividad_at = coalesce(updated_at, created_at, now())
WHERE ultima_actividad_at IS NULL;

ALTER TABLE public.patologias_reportadas
  ALTER COLUMN ultima_actividad_at SET DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_patologias_actividad
  ON public.patologias_reportadas (ultima_actividad_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_patologias_coords
  ON public.patologias_reportadas (lat, lng)
  WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------
-- 2. Parámetros configurables
-- ---------------------------------------------------------------------
INSERT INTO public.app_config (clave, valor, descripcion, tipo) VALUES
  ('patologia_dias_desatendida', '60',
   'Días sin actividad tras los cuales un reporte de patología se marca como desatendido (gris en el mapa).',
   'numero'),
  ('patologia_radio_km', '5',
   'Radio en km dentro del cual un reporte nuevo reactiva a los reportes vecinos.',
   'numero')
ON CONFLICT (clave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.config_num(p_clave text, p_default numeric)
RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT coalesce(
    (SELECT nullif(valor, '')::numeric FROM public.app_config
      WHERE clave = p_clave),
    p_default);
$$;

-- ---------------------------------------------------------------------
-- 3. Estado derivado del reporte
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.estado_reporte(p_ultima_actividad timestamptz)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT CASE
    WHEN p_ultima_actividad IS NULL THEN 'desatendida'
    WHEN p_ultima_actividad >
         now() - (public.config_num('patologia_dias_desatendida', 60)
                  || ' days')::interval
      THEN 'activa'
    ELSE 'desatendida'
  END;
$$;

COMMENT ON FUNCTION public.estado_reporte(timestamptz) IS
  'activa | desatendida — según los días sin actividad configurados.';

-- ---------------------------------------------------------------------
-- 4. Propagación de actividad por proximidad
--    Un reporte nuevo refresca a los vecinos dentro del radio: el foco
--    sigue vigente aunque los reportes originales sean antiguos.
--    Distancia por bounding box (usa el índice) — sin dependencia de
--    PostGIS. 1° lat ≈ 111.045 km; la longitud se corrige por latitud.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.propagar_actividad_patologia()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  radio_km numeric := public.config_num('patologia_radio_km', 5);
  d_lat numeric;
  d_lng numeric;
BEGIN
  IF NEW.lat IS NULL OR NEW.lng IS NULL THEN
    RETURN NEW;
  END IF;

  d_lat := radio_km / 111.045;
  -- cos(lat) evita que el radio se ensanche cerca de los polos.
  d_lng := radio_km / (111.045 * greatest(cos(radians(NEW.lat)), 0.01));

  UPDATE public.patologias_reportadas
  SET ultima_actividad_at = now()
  WHERE id <> NEW.id
    AND deleted_at IS NULL
    AND lat BETWEEN NEW.lat - d_lat AND NEW.lat + d_lat
    AND lng BETWEEN NEW.lng - d_lng AND NEW.lng + d_lng;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_propagar_actividad
  ON public.patologias_reportadas;
CREATE TRIGGER trg_propagar_actividad
  AFTER INSERT ON public.patologias_reportadas
  FOR EACH ROW EXECUTE FUNCTION public.propagar_actividad_patologia();

-- Acción explícita del administrador: revisar/atender un reporte.
CREATE OR REPLACE FUNCTION public.admin_atender_patologia(
  p_id bigint,
  p_notas text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.es_admin() THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;
  UPDATE public.patologias_reportadas
  SET ultima_actividad_at   = now(),
      atendido_por_admin_at = now(),
      notas_admin           = coalesce(p_notas, notas_admin),
      updated_at            = now()
  WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reporte inexistente' USING ERRCODE = 'P0002';
  END IF;
  RETURN jsonb_build_object('ok', true, 'id', p_id);
END $$;

GRANT EXECUTE ON FUNCTION public.admin_atender_patologia(bigint, text)
  TO authenticated;

-- ---------------------------------------------------------------------
-- 5. Vista pública con el estado incluido
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW public.patologias_reportadas_publica AS
SELECT
  id,
  patologia_nombre,
  patologia_cientifico,
  planta_nombre,
  lat,
  lng,
  alt_m,
  fecha_deteccion,
  severidad,
  sintomas,
  foto_url,
  pais_iso2,
  region_nombre,
  municipio_nombre,
  clima_temp_c,
  clima_humedad_pct,
  created_at,
  ultima_actividad_at,
  atendido_por_admin_at IS NOT NULL AS atendido_por_admin,
  public.estado_reporte(ultima_actividad_at) AS estado
FROM public.patologias_reportadas
WHERE deleted_at IS NULL;

GRANT SELECT ON public.patologias_reportadas_publica TO anon, authenticated;

-- Heatmap con estado (lo consume el mapa público y el de la app).
CREATE OR REPLACE FUNCTION public.stats_heatmap_patologias()
RETURNS TABLE (
  lat double precision, lng double precision,
  patologia_nombre text, severidad text,
  pais_iso2 text, fecha_deteccion date,
  estado text, dias_sin_actividad int
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth
AS $$
  SELECT r.lat, r.lng, r.patologia_nombre, r.severidad,
         r.pais_iso2, r.fecha_deteccion,
         public.estado_reporte(r.ultima_actividad_at),
         extract(day FROM now() - coalesce(r.ultima_actividad_at,
                                           r.created_at))::int
  FROM public.patologias_reportadas r
  WHERE r.deleted_at IS NULL
    AND r.lat IS NOT NULL AND r.lng IS NOT NULL
  ORDER BY r.ultima_actividad_at DESC NULLS LAST
  LIMIT 2000;
$$;

GRANT EXECUTE ON FUNCTION public.stats_heatmap_patologias()
  TO anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. Eliminación de cuenta SIN borrar patrimonio comunitario
--    (redefine 0014 y 0017: se quitan los DELETE de reportes)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.eliminar_mi_cuenta()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, storage
AS $$
DECLARE
  uid uuid := auth.uid();
  n_reportes int := 0;
  n_variedades int := 0;
  n_predios_compartidos int := 0;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'No autenticado' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO n_predios_compartidos
  FROM public.predio_shares ps
  WHERE ps.owner_id = uid
    AND ps.shared_with_id IS DISTINCT FROM uid
    AND ps.aceptado_at IS NOT NULL;

  -- Variedades: patrimonio de la comunidad. Se conservan; solo se
  -- desvincula al autor.
  UPDATE public.variedades_comunitarias
  SET created_by = NULL
  WHERE created_by = uid;
  GET DIAGNOSTICS n_variedades = ROW_COUNT;

  -- Reportes: TODOS se conservan (incluidos los soft-deleted por el
  -- usuario, que se reactivan como aporte comunitario anónimo).
  UPDATE public.patologias_reportadas
  SET owner_id   = NULL,
      cliente_id = NULL,
      updated_at = now()
  WHERE owner_id = uid;
  GET DIAGNOSTICS n_reportes = ROW_COUNT;

  -- Las fotos NO se borran: son parte del reporte comunitario. Solo se
  -- desvincula el propietario del objeto en Storage.
  BEGIN
    UPDATE storage.objects SET owner = NULL
    WHERE bucket_id = 'patologias' AND owner = uid;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  DELETE FROM auth.users WHERE id = uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se pudo eliminar el usuario de Auth'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'reportes_anonimizados', n_reportes,
    'variedades_comunitarias_conservadas', n_variedades,
    'predios_con_colaboradores', n_predios_compartidos
  );
END $$;

REVOKE ALL ON FUNCTION public.eliminar_mi_cuenta() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.eliminar_mi_cuenta() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_eliminar_usuario(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, storage
AS $$
DECLARE
  n_reportes int := 0;
  n_variedades int := 0;
  v_email text;
BEGIN
  IF NOT public.es_admin() THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id requerido' USING ERRCODE = '22004';
  END IF;
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Usa la app para eliminar tu propia cuenta'
      USING ERRCODE = '42501';
  END IF;

  SELECT email INTO v_email FROM auth.users WHERE id = p_user_id;
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'Usuario inexistente' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.variedades_comunitarias
  SET created_by = NULL WHERE created_by = p_user_id;
  GET DIAGNOSTICS n_variedades = ROW_COUNT;

  UPDATE public.patologias_reportadas
  SET owner_id = NULL, cliente_id = NULL, updated_at = now()
  WHERE owner_id = p_user_id;
  GET DIAGNOSTICS n_reportes = ROW_COUNT;

  BEGIN
    UPDATE storage.objects SET owner = NULL
    WHERE bucket_id = 'patologias' AND owner = p_user_id;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'ok', true,
    'email', v_email,
    'reportes_conservados', n_reportes,
    'variedades_conservadas', n_variedades
  );
END $$;

REVOKE ALL ON FUNCTION public.admin_eliminar_usuario(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_eliminar_usuario(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 7. Blindaje: nadie puede BORRAR reportes de patologías.
--    Ni usuarios ni admin — el patrimonio comunitario solo se archiva
--    (deleted_at) en casos de moderación, nunca se destruye.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS patologias_reportadas_delete
  ON public.patologias_reportadas;
DROP POLICY IF EXISTS patologias_reportadas_admin
  ON public.patologias_reportadas;

-- El admin puede leer y editar (moderar), pero no borrar.
CREATE POLICY patologias_reportadas_admin_rw ON public.patologias_reportadas
  FOR SELECT USING (public.es_admin() OR owner_id = auth.uid()
                    OR deleted_at IS NULL);
CREATE POLICY patologias_reportadas_admin_update ON public.patologias_reportadas
  FOR UPDATE USING (public.es_admin() OR owner_id = auth.uid())
  WITH CHECK (public.es_admin() OR owner_id = auth.uid());
-- (Sin policy FOR DELETE ⇒ el borrado queda prohibido por RLS.)

COMMENT ON COLUMN public.patologias_reportadas.ultima_actividad_at IS
  'Última señal de vida del foco: reporte nuevo en el radio configurado '
  'o intervención del administrador. Alimenta estado_reporte().';

INSERT INTO public.schema_meta (id, version)
VALUES (1, 15)
ON CONFLICT (id) DO UPDATE
SET version = GREATEST(public.schema_meta.version, 15),
    applied_at = NOW();

-- Verificación:
-- SELECT estado, count(*) FROM public.patologias_reportadas_publica
--   GROUP BY estado;
-- SELECT clave, valor FROM public.app_config
--   WHERE clave LIKE 'patologia_%';
