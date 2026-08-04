-- =====================================================================
-- Migración 0017 — Backoffice de gestión web
-- Fecha: 2026-08-04. Idempotente. schema_meta → 14.
--
-- Provee:
--   1. `app_config`  — parámetros centralizados de la app (incluye el
--      email del desarrollador que recibe copia de los feedback).
--   2. `admin_allowlist` — quién puede entrar al backoffice.
--   3. `es_admin()` — helper de autorización.
--   4. RPCs de estadísticas públicas (agregados, sin datos personales).
--   5. RPCs de administración (usuarios, borrado) protegidas por admin.
--   6. Policies de gestión sobre las tablas editables desde el backoffice.
--
-- Seguridad: las RPCs de admin verifican `es_admin()` con el JWT del
-- usuario; el backoffice además usa service_role SOLO en el servidor
-- (Server Actions de Next.js). Nunca en el navegador.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Configuración centralizada de la app
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_config (
  clave       text PRIMARY KEY,
  valor       text,
  descripcion text,
  tipo        text NOT NULL DEFAULT 'texto'  -- texto|email|numero|bool|json
    CHECK (tipo IN ('texto', 'email', 'numero', 'bool', 'json')),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

-- Placeholders deliberados (no commitear correos reales). Tras aplicar,
-- sustituir manualmente — ver nexus_backoffice/README.md §2.4.
INSERT INTO public.app_config (clave, valor, descripcion, tipo) VALUES
  ('email_desarrollador', 'email@domain.com',
   'Correo que recibe copia de los feedback de usuarios.', 'email'),
  ('feedback_notificar', 'true',
   'Enviar aviso por email al recibir un feedback nuevo.', 'bool'),
  ('app_version_minima', '0.2.0',
   'Versión mínima soportada; por debajo se sugiere actualizar.', 'texto'),
  ('sync_schema_requerido', '11',
   'Versión de esquema remoto que exige el cliente para sincronizar.', 'numero'),
  ('banco_variedades_activo', 'true',
   'Habilita el banco comunitario de variedades en la app.', 'bool'),
  ('mapa_comunitario_activo', 'true',
   'Habilita el mapa de calor comunitario de patologías.', 'bool'),
  ('github_url', 'https://github.com/nexuscreatio/nexus-siembras',
   'Repositorio público mostrado en la web.', 'texto'),
  ('contacto_soporte', 'email@domain.com',
   'Correo de soporte mostrado a los usuarios.', 'email')
ON CONFLICT (clave) DO NOTHING;   -- nunca pisar valores ya editados

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

-- La app (usuarios autenticados) puede LEER la config pública.
DROP POLICY IF EXISTS app_config_read ON public.app_config;
CREATE POLICY app_config_read ON public.app_config
  FOR SELECT USING (auth.role() = 'authenticated');

-- ---------------------------------------------------------------------
-- 2. Allowlist de administradores del backoffice
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_allowlist (
  email      text PRIMARY KEY,
  nombre     text,
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Placeholder: reemplazar por el email real del admin (README §2.4).
INSERT INTO public.admin_allowlist (email, nombre)
VALUES ('email@domain.com', 'Administrador')
ON CONFLICT (email) DO NOTHING;

ALTER TABLE public.admin_allowlist ENABLE ROW LEVEL SECURITY;
-- Sin policies: solo service_role la consulta/edita.

CREATE OR REPLACE FUNCTION public.es_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_allowlist a
    WHERE a.activo
      AND lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

GRANT EXECUTE ON FUNCTION public.es_admin() TO authenticated;

-- ---------------------------------------------------------------------
-- 3. Estadísticas públicas (agregados — sin datos personales)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.stats_publicas()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth
AS $$
  SELECT jsonb_build_object(
    'usuarios',        (SELECT count(*) FROM auth.users),
    'usuarios_activos_30d', (
      SELECT count(*) FROM auth.users
      WHERE last_sign_in_at > now() - interval '30 days'),
    'predios',         (SELECT count(*) FROM public.predios
                          WHERE deleted_at IS NULL),
    'lotes',           (SELECT count(*) FROM public.lotes
                          WHERE deleted_at IS NULL),
    'cultivos',        (SELECT count(*) FROM public.cultivos
                          WHERE deleted_at IS NULL),
    'cultivos_activos',(SELECT count(*) FROM public.cultivos
                          WHERE deleted_at IS NULL
                            AND finalizado_fecha IS NULL),
    'variedades',      (SELECT count(*) FROM public.variedades_comunitarias),
    'reportes_patologias', (SELECT count(*) FROM public.patologias_reportadas
                              WHERE deleted_at IS NULL),
    'tratamientos',    (SELECT count(*) FROM public.patologia_tratamientos),
    'paises',          (SELECT count(DISTINCT pais_iso2) FROM public.predios
                          WHERE pais_iso2 IS NOT NULL AND deleted_at IS NULL)
  );
$$;

-- Usuarios por país (derivado de sus predios). Un usuario cuenta en cada
-- país donde tenga predios; 'ND' si no declaró país.
CREATE OR REPLACE FUNCTION public.stats_usuarios_por_pais()
RETURNS TABLE (pais_iso2 text, usuarios bigint, predios bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth
AS $$
  SELECT coalesce(p.pais_iso2, 'ND') AS pais_iso2,
         count(DISTINCT p.owner_id)  AS usuarios,
         count(*)                    AS predios
  FROM public.predios p
  WHERE p.deleted_at IS NULL
  GROUP BY 1
  ORDER BY 2 DESC;
$$;

-- Puntos del mapa de calor (anonimizados: sin owner, sin id de usuario).
CREATE OR REPLACE FUNCTION public.stats_heatmap_patologias()
RETURNS TABLE (
  lat double precision, lng double precision,
  patologia_nombre text, severidad text,
  pais_iso2 text, fecha_deteccion date
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth
AS $$
  SELECT r.lat, r.lng, r.patologia_nombre, r.severidad,
         r.pais_iso2, r.fecha_deteccion
  FROM public.patologias_reportadas r
  WHERE r.deleted_at IS NULL
    AND r.lat IS NOT NULL AND r.lng IS NOT NULL
  ORDER BY r.fecha_deteccion DESC
  LIMIT 2000;
$$;

GRANT EXECUTE ON FUNCTION public.stats_publicas() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.stats_usuarios_por_pais() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.stats_heatmap_patologias() TO anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Administración de usuarios (solo admin)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_listar_usuarios()
RETURNS TABLE (
  user_id uuid, email text, created_at timestamptz,
  last_sign_in_at timestamptz,
  pais text, region text, ciudad text,
  predios bigint, lotes bigint, cultivos bigint,
  feedbacks bigint, feedbacks_pendientes bigint
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth
AS $$
  SELECT
    u.id,
    u.email::text,
    u.created_at,
    u.last_sign_in_at,
    (SELECT p.pais_iso2 FROM public.predios p
      WHERE p.owner_id = u.id AND p.deleted_at IS NULL
      ORDER BY p.created_at LIMIT 1),
    (SELECT p.region_nombre FROM public.predios p
      WHERE p.owner_id = u.id AND p.deleted_at IS NULL
      ORDER BY p.created_at LIMIT 1),
    (SELECT p.municipio_nombre FROM public.predios p
      WHERE p.owner_id = u.id AND p.deleted_at IS NULL
      ORDER BY p.created_at LIMIT 1),
    (SELECT count(*) FROM public.predios p
      WHERE p.owner_id = u.id AND p.deleted_at IS NULL),
    (SELECT count(*) FROM public.lotes l
      WHERE l.owner_id = u.id AND l.deleted_at IS NULL),
    (SELECT count(*) FROM public.cultivos c
      WHERE c.owner_id = u.id AND c.deleted_at IS NULL),
    (SELECT count(*) FROM public.feedback_encuestas f
      WHERE f.user_id = u.id),
    (SELECT count(*) FROM public.feedback_encuestas f
      WHERE f.user_id = u.id AND NOT f.atendido)
  FROM auth.users u
  WHERE public.es_admin()          -- sin admin no devuelve filas
  ORDER BY u.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.admin_listar_usuarios() TO authenticated;

-- Eliminar un usuario cualquiera (mismo comportamiento que
-- `eliminar_mi_cuenta`: anonimiza lo comunitario, borra lo privado por
-- CASCADE). IRREVERSIBLE — el backoffice pide doble confirmación.
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
  -- Un admin no puede borrarse a sí mismo desde el backoffice.
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Usa la app para eliminar tu propia cuenta'
      USING ERRCODE = '42501';
  END IF;

  SELECT email INTO v_email FROM auth.users WHERE id = p_user_id;
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'Usuario inexistente' USING ERRCODE = 'P0002';
  END IF;

  SELECT count(*) INTO n_variedades
  FROM public.variedades_comunitarias WHERE created_by = p_user_id;

  UPDATE public.patologias_reportadas
  SET owner_id = NULL, cliente_id = NULL, updated_at = now()
  WHERE owner_id = p_user_id AND deleted_at IS NULL;
  GET DIAGNOSTICS n_reportes = ROW_COUNT;

  DELETE FROM public.patologias_reportadas
  WHERE owner_id = p_user_id AND deleted_at IS NOT NULL;

  BEGIN
    DELETE FROM storage.objects
    WHERE bucket_id = 'patologias' AND owner = p_user_id;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'ok', true,
    'email', v_email,
    'reportes_anonimizados', n_reportes,
    'variedades_conservadas', n_variedades
  );
END $$;

REVOKE ALL ON FUNCTION public.admin_eliminar_usuario(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_eliminar_usuario(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 5. Series de uso para los gráficos del panel admin
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_series_uso(p_dias int DEFAULT 30)
RETURNS TABLE (
  dia date, usuarios_nuevos bigint, cultivos bigint,
  reportes bigint, feedbacks bigint
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth
AS $$
  WITH dias AS (
    SELECT generate_series(
      (current_date - (p_dias - 1))::date, current_date, '1 day')::date AS dia
  )
  SELECT d.dia,
    (SELECT count(*) FROM auth.users u
      WHERE u.created_at::date = d.dia),
    (SELECT count(*) FROM public.cultivos c
      WHERE c.created_at::date = d.dia AND c.deleted_at IS NULL),
    (SELECT count(*) FROM public.patologias_reportadas r
      WHERE r.created_at::date = d.dia AND r.deleted_at IS NULL),
    (SELECT count(*) FROM public.feedback_encuestas f
      WHERE f.created_at::date = d.dia)
  FROM dias d
  WHERE public.es_admin()
  ORDER BY d.dia;
$$;

GRANT EXECUTE ON FUNCTION public.admin_series_uso(int) TO authenticated;

-- ---------------------------------------------------------------------
-- 6. Policies de gestión sobre las tablas editables del backoffice
--    (variedades comunitarias, reportes de patologías, tratamientos).
--    El admin puede corregir/moderar contenido comunitario.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS variedades_admin ON public.variedades_comunitarias;
CREATE POLICY variedades_admin ON public.variedades_comunitarias
  FOR ALL USING (public.es_admin()) WITH CHECK (public.es_admin());

DROP POLICY IF EXISTS patologias_reportadas_admin ON public.patologias_reportadas;
CREATE POLICY patologias_reportadas_admin ON public.patologias_reportadas
  FOR ALL USING (public.es_admin()) WITH CHECK (public.es_admin());

ALTER TABLE public.patologia_tratamientos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tratamientos_read ON public.patologia_tratamientos;
CREATE POLICY tratamientos_read ON public.patologia_tratamientos
  FOR SELECT USING (auth.role() = 'authenticated');
DROP POLICY IF EXISTS tratamientos_admin ON public.patologia_tratamientos;
CREATE POLICY tratamientos_admin ON public.patologia_tratamientos
  FOR ALL USING (public.es_admin()) WITH CHECK (public.es_admin());

DROP POLICY IF EXISTS feedback_admin ON public.feedback_encuestas;
CREATE POLICY feedback_admin ON public.feedback_encuestas
  FOR ALL USING (public.es_admin()) WITH CHECK (public.es_admin());

DROP POLICY IF EXISTS app_config_admin ON public.app_config;
CREATE POLICY app_config_admin ON public.app_config
  FOR ALL USING (public.es_admin()) WITH CHECK (public.es_admin());

COMMENT ON TABLE public.app_config IS
  'Parámetros centralizados de la app, editables desde el backoffice web.';
COMMENT ON TABLE public.admin_allowlist IS
  'Emails autorizados a entrar al backoffice (login por código OTP).';

INSERT INTO public.schema_meta (id, version)
VALUES (1, 14)
ON CONFLICT (id) DO UPDATE
SET version = GREATEST(public.schema_meta.version, 14),
    applied_at = NOW();

-- Verificación:
-- SELECT public.stats_publicas();
-- SELECT * FROM public.stats_usuarios_por_pais();
-- SELECT clave, valor FROM public.app_config ORDER BY clave;
