-- =====================================================================
-- Migración 0020 — RLS de escritura admin (cierre P2 code-review)
-- Fecha: 2026-08-04. Idempotente. schema_meta → 17.
--
-- Las tablas `admin_allowlist` y `feedback_config` solo eran tocables con
-- service_role. El backoffice ahora escribe con el JWT del admin + RLS
-- (`es_admin()`), de modo que la 4.ª capa de seguridad documentada sí
-- aplica a esas rutas. service_role queda solo para Auth Admin API y
-- lecturas agregadas públicas.
-- =====================================================================

DO $$
BEGIN
  IF to_regclass('public.admin_allowlist') IS NULL
     OR to_regclass('public.feedback_config') IS NULL THEN
    RAISE EXCEPTION
      'Faltan tablas de 0016/0017. Aplica esas migraciones antes de la 0020.';
  END IF;
END $$;

ALTER TABLE public.admin_allowlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_allowlist_admin ON public.admin_allowlist;
CREATE POLICY admin_allowlist_admin ON public.admin_allowlist
  FOR ALL USING (public.es_admin()) WITH CHECK (public.es_admin());

DROP POLICY IF EXISTS feedback_config_admin ON public.feedback_config;
CREATE POLICY feedback_config_admin ON public.feedback_config
  FOR ALL USING (public.es_admin()) WITH CHECK (public.es_admin());

COMMENT ON POLICY admin_allowlist_admin ON public.admin_allowlist IS
  'Solo admins (es_admin) gestionan la allowlist desde el panel.';
COMMENT ON POLICY feedback_config_admin ON public.feedback_config IS
  'Solo admins leen/editan el destino de notificaciones de feedback.';

INSERT INTO public.schema_meta (id, version)
VALUES (1, 17)
ON CONFLICT (id) DO UPDATE
SET version = GREATEST(public.schema_meta.version, 17),
    applied_at = NOW();
