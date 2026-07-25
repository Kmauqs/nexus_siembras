-- =============================================================
-- NEXUS Siembras — Schema Postgres Fase 3e v3
-- RPC para obtener email de usuario por UUID
-- =============================================================
--
-- Necesario para que la app muestre el email real del colaborador
-- en lugar del UUID truncado ("(usuario 879782a3)").
-- SECURITY DEFINER porque auth.users está protegido por RLS.
-- =============================================================

CREATE OR REPLACE FUNCTION public.email_de_usuario(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_email TEXT;
BEGIN
  SELECT email INTO v_email FROM auth.users WHERE id = p_user_id;
  RETURN v_email;
END;
$$;

REVOKE ALL ON FUNCTION public.email_de_usuario(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.email_de_usuario(UUID) TO authenticated;

-- =============================================================
-- FIN v3
-- =============================================================
