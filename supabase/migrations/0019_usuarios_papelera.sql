-- =====================================================================
-- Migración 0019 — Papelera de usuarios (soft-delete del backoffice)
-- Fecha: 2026-08-04. Idempotente. schema_meta → 16.
--
-- El panel web mueve usuarios a papelera (ban + registro) en lugar de
-- borrarlos de inmediato. Desde la papelera se puede recuperar (quitar
-- ban) o eliminar definitivamente (mismo efecto que eliminar_mi_cuenta).
-- Requiere 0017 (es_admin) y 0018 (patrimonio comunitario en el borrado).
-- =====================================================================

DO $$
BEGIN
  IF to_regclass('public.admin_allowlist') IS NULL THEN
    RAISE EXCEPTION
      'Falta la migración 0017 (admin_allowlist). Aplícala antes de esta.';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.usuarios_papelera (
  user_id       uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email         text NOT NULL,
  snapshot      jsonb NOT NULL DEFAULT '{}'::jsonb,
  motivo        text,
  eliminado_por uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  eliminado_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_usuarios_papelera_fecha
  ON public.usuarios_papelera (eliminado_at DESC);

ALTER TABLE public.usuarios_papelera ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS usuarios_papelera_admin ON public.usuarios_papelera;
CREATE POLICY usuarios_papelera_admin ON public.usuarios_papelera
  FOR ALL USING (public.es_admin()) WITH CHECK (public.es_admin());

COMMENT ON TABLE public.usuarios_papelera IS
  'Soft-delete del backoffice: usuarios baneados pendientes de recuperar '
  'o de borrado definitivo. El backoffice usa service_role + Server Actions.';

INSERT INTO public.schema_meta (id, version)
VALUES (1, 16)
ON CONFLICT (id) DO UPDATE
SET version = GREATEST(public.schema_meta.version, 16),
    applied_at = NOW();
