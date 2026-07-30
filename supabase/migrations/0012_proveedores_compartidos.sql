-- Proveedores visibles para colaboradores con rol propietario o trabajador
-- en predios compartidos (directorio común del equipo del predio).

CREATE OR REPLACE FUNCTION public.puede_ver_proveedor(p_owner_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_owner_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.predios p
    WHERE public.rol_en_predio(p.id) IN ('propietario', 'trabajador')
      AND (
        p.owner_id = p_owner_id
        OR EXISTS (
          SELECT 1 FROM public.predio_shares ps
          WHERE ps.predio_id = p.id
            AND ps.shared_with_id = p_owner_id
            AND ps.rol IN ('propietario', 'trabajador')
        )
      )
  );
$$;

DROP POLICY IF EXISTS proveedores_owner_select ON public.proveedores;
DROP POLICY IF EXISTS proveedores_select ON public.proveedores;

CREATE POLICY proveedores_select ON public.proveedores
  FOR SELECT USING (public.puede_ver_proveedor(owner_id));

-- INSERT/UPDATE/DELETE siguen siendo del dueño del registro (owner_id).
