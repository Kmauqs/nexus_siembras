-- Migración 0014 — Eliminar cuenta de usuario
--
-- RPC `eliminar_mi_cuenta()` (SECURITY DEFINER):
--   1. Anonimiza reportes comunitarios de patologías (conserva filas
--      públicas; quita vínculo con el usuario).
--   2. NO toca `variedades_comunitarias` (contribuciones al banco).
--   3. Borra datos privados (CASCADE al borrar auth.users cubre predios,
--      cultivos, shares, etc.; aquí se limpia storage del bucket).
--   4. Elimina el usuario de `auth.users`.
--
-- Además: `patologias_reportadas.owner_id` pasa a nullable + ON DELETE
-- SET NULL para que un borrado de auth no arrastre reportes ya
-- anonimizados (defensa en profundidad).
--
-- schema_meta → 11

-- 1) Permitir conservar reportes comunitarios sin dueño
ALTER TABLE public.patologias_reportadas
  ALTER COLUMN owner_id DROP NOT NULL;

ALTER TABLE public.patologias_reportadas
  DROP CONSTRAINT IF EXISTS patologias_reportadas_owner_id_fkey;

ALTER TABLE public.patologias_reportadas
  ADD CONSTRAINT patologias_reportadas_owner_id_fkey
  FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- 2) RPC principal
CREATE OR REPLACE FUNCTION public.eliminar_mi_cuenta()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, storage
AS $$
DECLARE
  uid uuid := auth.uid();
  n_reportes int := 0;
  n_variedades int := 0;
  n_predios_compartidos int := 0;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'No autenticado'
      USING ERRCODE = '42501';
  END IF;

  SELECT COUNT(*)::int INTO n_variedades
  FROM public.variedades_comunitarias
  WHERE created_by = uid;

  SELECT COUNT(*)::int INTO n_predios_compartidos
  FROM public.predio_shares ps
  WHERE ps.owner_id = uid
    AND ps.shared_with_id IS DISTINCT FROM uid
    AND ps.aceptado_at IS NOT NULL;

  -- Conservar reportes activos en la comunidad (vista pública).
  UPDATE public.patologias_reportadas
  SET
    owner_id = NULL,
    cliente_id = NULL,
    updated_at = NOW()
  WHERE owner_id = uid
    AND deleted_at IS NULL;
  GET DIAGNOSTICS n_reportes = ROW_COUNT;

  -- Reportes soft-deleted del usuario: sí se eliminan (ya no son públicos).
  DELETE FROM public.patologias_reportadas
  WHERE owner_id = uid
    AND deleted_at IS NOT NULL;

  -- Fotos en Storage asociadas al usuario (bucket patologias).
  BEGIN
    DELETE FROM storage.objects
    WHERE bucket_id = 'patologias'
      AND owner = uid;
  EXCEPTION
    WHEN undefined_table THEN
      NULL; -- entornos sin storage
    WHEN OTHERS THEN
      NULL; -- no bloquear el borrado de cuenta por storage
  END;

  -- Borrar auth.users → CASCADE de predios, cultivos, shares, etc.
  -- variedades_comunitarias NO tiene FK a auth.users → se conservan.
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
END;
$$;

REVOKE ALL ON FUNCTION public.eliminar_mi_cuenta() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.eliminar_mi_cuenta() TO authenticated;

COMMENT ON FUNCTION public.eliminar_mi_cuenta() IS
  'Elimina la cuenta del usuario autenticado: anonimiza reportes '
  'comunitarios de patologías, conserva variedades_comunitarias, '
  'borra datos privados vía CASCADE de auth.users y limpia storage.';

INSERT INTO public.schema_meta (id, version)
VALUES (1, 11)
ON CONFLICT (id) DO UPDATE
SET version = GREATEST(public.schema_meta.version, 11),
    applied_at = NOW();
