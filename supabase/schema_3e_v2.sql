-- =============================================================
-- NEXUS Siembras — Schema Postgres Fase 3e v2
-- Refinamiento de RLS por rol específico
-- =============================================================
--
-- Reglas de acceso por rol:
--
--   PROPIETARIO (dueño original + colaboradores con rol=propietario):
--     - Control total: crear/editar/borrar TODO
--     - Único que ve y gestiona: compras, análisis de suelo,
--       condiciones edafoclim, colaboradores
--
--   TRABAJADOR:
--     - Ver: predios, lotes, cultivos, eventos, tareas, inventario,
--       análisis (lectura), condiciones (lectura)
--     - Crear/editar: cultivos, eventos, tareas
--     - Editar: inventario (para consumir insumos al registrar tareas)
--     - NO puede: editar predio, editar lotes, ver o editar compras
--
--   CONSULTOR:
--     - Solo lectura de TODO lo del predio
--     - NO ve compras (información comercial reservada)
--     - NO ve colaboradores
-- =============================================================


-- =============================================================
-- Funciones helper por rol
-- =============================================================

-- Retorna el rol del usuario actual en el predio, o NULL si no tiene acceso.
CREATE OR REPLACE FUNCTION public.rol_en_predio(p_predio_id BIGINT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM public.predios WHERE id = p_predio_id AND owner_id = auth.uid())
      THEN 'propietario'
    ELSE (
      SELECT rol FROM public.predio_shares
      WHERE predio_id = p_predio_id
        AND shared_with_id = auth.uid()
        AND aceptado_at IS NOT NULL
      LIMIT 1
    )
  END;
$$;

-- Reemplaza puede_editar_predio: solo propietario o trabajador
CREATE OR REPLACE FUNCTION public.puede_editar_predio(p_predio_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.rol_en_predio(p_predio_id) IN ('propietario', 'trabajador');
$$;

-- Solo propietario puede editar predios/lotes/compras/análisis/condiciones
CREATE OR REPLACE FUNCTION public.es_propietario_predio(p_predio_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.rol_en_predio(p_predio_id) = 'propietario';
$$;

-- Ver (cualquier rol aceptado)
CREATE OR REPLACE FUNCTION public.puede_ver_predio(p_predio_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.rol_en_predio(p_predio_id) IS NOT NULL;
$$;


-- =============================================================
-- PREDIOS: solo propietario edita (colaboradores solo lectura)
-- =============================================================

DROP POLICY IF EXISTS predios_select ON public.predios;
DROP POLICY IF EXISTS predios_update ON public.predios;
DROP POLICY IF EXISTS predios_delete_owner ON public.predios;
DROP POLICY IF EXISTS predios_owner_select ON public.predios;
DROP POLICY IF EXISTS predios_owner_update ON public.predios;
DROP POLICY IF EXISTS predios_owner_delete ON public.predios;
DROP POLICY IF EXISTS predios_owner_insert ON public.predios;

CREATE POLICY predios_select ON public.predios FOR SELECT
  USING (owner_id = auth.uid() OR public.puede_ver_predio(id));

CREATE POLICY predios_insert ON public.predios FOR INSERT
  WITH CHECK (owner_id = auth.uid());

CREATE POLICY predios_update ON public.predios FOR UPDATE
  USING (owner_id = auth.uid() OR public.es_propietario_predio(id));

CREATE POLICY predios_delete ON public.predios FOR DELETE
  USING (owner_id = auth.uid());


-- =============================================================
-- LOTES: solo propietario edita (trabajador y consultor solo lectura)
-- =============================================================

DROP POLICY IF EXISTS lotes_select ON public.lotes;
DROP POLICY IF EXISTS lotes_insert ON public.lotes;
DROP POLICY IF EXISTS lotes_update ON public.lotes;
DROP POLICY IF EXISTS lotes_delete ON public.lotes;

CREATE POLICY lotes_select ON public.lotes FOR SELECT
  USING (owner_id = auth.uid() OR public.puede_ver_predio(predio_id));

CREATE POLICY lotes_insert ON public.lotes FOR INSERT
  WITH CHECK (owner_id = auth.uid() OR public.es_propietario_predio(predio_id));

CREATE POLICY lotes_update ON public.lotes FOR UPDATE
  USING (owner_id = auth.uid() OR public.es_propietario_predio(predio_id));

CREATE POLICY lotes_delete ON public.lotes FOR DELETE
  USING (owner_id = auth.uid() OR public.es_propietario_predio(predio_id));


-- =============================================================
-- CULTIVOS: trabajador y propietario editan; consultor solo lee
-- =============================================================

DROP POLICY IF EXISTS cultivos_select ON public.cultivos;
DROP POLICY IF EXISTS cultivos_insert ON public.cultivos;
DROP POLICY IF EXISTS cultivos_update ON public.cultivos;
DROP POLICY IF EXISTS cultivos_delete ON public.cultivos;

CREATE POLICY cultivos_select ON public.cultivos FOR SELECT
  USING (owner_id = auth.uid() OR public.puede_ver_predio(predio_id));

CREATE POLICY cultivos_insert ON public.cultivos FOR INSERT
  WITH CHECK (owner_id = auth.uid() OR public.puede_editar_predio(predio_id));

CREATE POLICY cultivos_update ON public.cultivos FOR UPDATE
  USING (owner_id = auth.uid() OR public.puede_editar_predio(predio_id));

CREATE POLICY cultivos_delete ON public.cultivos FOR DELETE
  USING (owner_id = auth.uid() OR public.puede_editar_predio(predio_id));


-- =============================================================
-- INVENTARIO: trabajador y propietario pueden actualizar
-- (para reflejar consumo de insumos al registrar tareas)
-- =============================================================

DROP POLICY IF EXISTS inventarios_select ON public.inventarios;
DROP POLICY IF EXISTS inventarios_insert ON public.inventarios;
DROP POLICY IF EXISTS inventarios_update ON public.inventarios;
DROP POLICY IF EXISTS inventarios_delete ON public.inventarios;

CREATE POLICY inventarios_select ON public.inventarios FOR SELECT
  USING (owner_id = auth.uid() OR public.puede_ver_predio(predio_id));

CREATE POLICY inventarios_insert ON public.inventarios FOR INSERT
  WITH CHECK (owner_id = auth.uid() OR public.puede_editar_predio(predio_id));

CREATE POLICY inventarios_update ON public.inventarios FOR UPDATE
  USING (owner_id = auth.uid() OR public.puede_editar_predio(predio_id));

CREATE POLICY inventarios_delete ON public.inventarios FOR DELETE
  USING (owner_id = auth.uid() OR public.es_propietario_predio(predio_id));


-- =============================================================
-- COMPRAS: SOLO PROPIETARIO (información comercial reservada)
-- Trabajador y consultor NO ven las compras.
-- =============================================================

DROP POLICY IF EXISTS compras_select ON public.compras;
DROP POLICY IF EXISTS compras_insert ON public.compras;
DROP POLICY IF EXISTS compras_update ON public.compras;
DROP POLICY IF EXISTS compras_delete ON public.compras;

CREATE POLICY compras_select ON public.compras FOR SELECT
  USING (owner_id = auth.uid() OR public.es_propietario_predio(predio_id));

CREATE POLICY compras_insert ON public.compras FOR INSERT
  WITH CHECK (owner_id = auth.uid() OR public.es_propietario_predio(predio_id));

CREATE POLICY compras_update ON public.compras FOR UPDATE
  USING (owner_id = auth.uid() OR public.es_propietario_predio(predio_id));

CREATE POLICY compras_delete ON public.compras FOR DELETE
  USING (owner_id = auth.uid() OR public.es_propietario_predio(predio_id));


-- =============================================================
-- ANÁLISIS DE SUELO: lectura para todos, edición solo propietario
-- =============================================================

DROP POLICY IF EXISTS analisis_suelo_select ON public.analisis_suelo;
DROP POLICY IF EXISTS analisis_suelo_insert ON public.analisis_suelo;
DROP POLICY IF EXISTS analisis_suelo_update ON public.analisis_suelo;
DROP POLICY IF EXISTS analisis_suelo_delete ON public.analisis_suelo;

CREATE POLICY analisis_suelo_select ON public.analisis_suelo FOR SELECT
  USING (owner_id = auth.uid() OR public.puede_ver_predio(predio_id));

CREATE POLICY analisis_suelo_insert ON public.analisis_suelo FOR INSERT
  WITH CHECK (owner_id = auth.uid() OR public.es_propietario_predio(predio_id));

CREATE POLICY analisis_suelo_update ON public.analisis_suelo FOR UPDATE
  USING (owner_id = auth.uid() OR public.es_propietario_predio(predio_id));

CREATE POLICY analisis_suelo_delete ON public.analisis_suelo FOR DELETE
  USING (owner_id = auth.uid() OR public.es_propietario_predio(predio_id));


-- =============================================================
-- CONDICIONES PREDIO: mismo criterio que análisis
-- =============================================================

DROP POLICY IF EXISTS condiciones_predio_select ON public.condiciones_predio;
DROP POLICY IF EXISTS condiciones_predio_insert ON public.condiciones_predio;
DROP POLICY IF EXISTS condiciones_predio_update ON public.condiciones_predio;
DROP POLICY IF EXISTS condiciones_predio_delete ON public.condiciones_predio;

CREATE POLICY condiciones_predio_select ON public.condiciones_predio FOR SELECT
  USING (owner_id = auth.uid() OR public.puede_ver_predio(predio_id));

CREATE POLICY condiciones_predio_insert ON public.condiciones_predio FOR INSERT
  WITH CHECK (owner_id = auth.uid() OR public.es_propietario_predio(predio_id));

CREATE POLICY condiciones_predio_update ON public.condiciones_predio FOR UPDATE
  USING (owner_id = auth.uid() OR public.es_propietario_predio(predio_id));

CREATE POLICY condiciones_predio_delete ON public.condiciones_predio FOR DELETE
  USING (owner_id = auth.uid() OR public.es_propietario_predio(predio_id));


-- =============================================================
-- EVENTOS DE CULTIVO: trabajador puede editar (via cultivo → predio)
-- =============================================================

DROP POLICY IF EXISTS eventos_cultivo_select ON public.eventos_cultivo;
DROP POLICY IF EXISTS eventos_cultivo_insert ON public.eventos_cultivo;
DROP POLICY IF EXISTS eventos_cultivo_update ON public.eventos_cultivo;
DROP POLICY IF EXISTS eventos_cultivo_delete ON public.eventos_cultivo;

CREATE POLICY eventos_cultivo_select ON public.eventos_cultivo FOR SELECT
  USING (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = eventos_cultivo.cultivo_id
        AND public.puede_ver_predio(c.predio_id)
    )
  );
CREATE POLICY eventos_cultivo_insert ON public.eventos_cultivo FOR INSERT
  WITH CHECK (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = eventos_cultivo.cultivo_id
        AND public.puede_editar_predio(c.predio_id)
    )
  );
CREATE POLICY eventos_cultivo_update ON public.eventos_cultivo FOR UPDATE
  USING (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = eventos_cultivo.cultivo_id
        AND public.puede_editar_predio(c.predio_id)
    )
  );
CREATE POLICY eventos_cultivo_delete ON public.eventos_cultivo FOR DELETE
  USING (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = eventos_cultivo.cultivo_id
        AND public.puede_editar_predio(c.predio_id)
    )
  );


-- =============================================================
-- TAREAS COMPLETADAS: trabajador puede registrar (necesario para su rol)
-- =============================================================

DROP POLICY IF EXISTS tareas_completadas_select ON public.tareas_completadas;
DROP POLICY IF EXISTS tareas_completadas_insert ON public.tareas_completadas;

CREATE POLICY tareas_completadas_select ON public.tareas_completadas FOR SELECT
  USING (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = tareas_completadas.cultivo_id
        AND public.puede_ver_predio(c.predio_id)
    )
  );

CREATE POLICY tareas_completadas_insert ON public.tareas_completadas FOR INSERT
  WITH CHECK (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = tareas_completadas.cultivo_id
        AND public.puede_editar_predio(c.predio_id)
    )
  );

-- =============================================================
-- FIN v2
-- =============================================================
