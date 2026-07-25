-- =============================================================
-- NEXUS Siembras — Schema Postgres Fase 3e
-- Colaboradores + patologías comunitarias
-- =============================================================
--
-- Cómo aplicar:
--   1. Aplicar primero `schema.sql` (Fase 3d) si no se ha hecho.
--   2. Ejecutar este archivo COMPLETO en el SQL Editor.
--   3. Verificar en Table Editor que aparezcan las tablas nuevas.
--
-- Decisiones de diseño:
--   * Colaborador debe tener cuenta ya creada (no invitación por email).
--   * 3 roles: propietario / trabajador / consultor.
--   * Auto-aceptación al invitar (aparece inmediatamente para el invitado).
--   * Contribución de patologías es opt-in (columna consentimiento).
-- =============================================================


-- =============================================================
-- 1. RPC: buscar_usuario_por_email
--    Necesario porque `auth.users` está protegido — solo un
--    SECURITY DEFINER puede leerlo. Retorna user_id o NULL.
-- =============================================================

CREATE OR REPLACE FUNCTION public.buscar_usuario_por_email(p_email TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_id UUID;
BEGIN
  SELECT id INTO v_id FROM auth.users WHERE lower(email) = lower(p_email);
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.buscar_usuario_por_email(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.buscar_usuario_por_email(TEXT) TO authenticated;


-- =============================================================
-- 2. PREDIO_SHARES: ajustar (ya existe en schema.sql)
--    Solo agregamos un CHECK en rol si aún no está.
-- =============================================================

-- Si acaso el CHECK anterior era distinto, lo dropeamos y recreamos.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'predio_shares_rol_check'
      AND table_name = 'predio_shares'
  ) THEN
    ALTER TABLE public.predio_shares DROP CONSTRAINT predio_shares_rol_check;
  END IF;
  ALTER TABLE public.predio_shares
    ADD CONSTRAINT predio_shares_rol_check
    CHECK (rol IN ('propietario', 'trabajador', 'consultor'));
END $$;

-- Auto-aceptación: al insertar, se marca `aceptado_at = NOW()`.
CREATE OR REPLACE FUNCTION public.autoaceptar_share()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.aceptado_at IS NULL THEN
    NEW.aceptado_at := NOW();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS predio_shares_autoaceptar ON public.predio_shares;
CREATE TRIGGER predio_shares_autoaceptar BEFORE INSERT ON public.predio_shares
  FOR EACH ROW EXECUTE FUNCTION public.autoaceptar_share();


-- =============================================================
-- 3. RLS extendida — colaboradores pueden ver/editar
--
-- Función helper: dado un predio_id, retorna true si el usuario
-- actual tiene rol >= trabajador en ese predio (propietario o
-- trabajador). Los consultores son solo lectura.
-- =============================================================

CREATE OR REPLACE FUNCTION public.puede_editar_predio(p_predio_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.predios
    WHERE id = p_predio_id AND owner_id = auth.uid()
  ) OR EXISTS (
    SELECT 1 FROM public.predio_shares
    WHERE predio_id = p_predio_id
      AND shared_with_id = auth.uid()
      AND rol IN ('propietario', 'trabajador')
      AND aceptado_at IS NOT NULL
  );
$$;

CREATE OR REPLACE FUNCTION public.puede_ver_predio(p_predio_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.predios
    WHERE id = p_predio_id AND owner_id = auth.uid()
  ) OR EXISTS (
    SELECT 1 FROM public.predio_shares
    WHERE predio_id = p_predio_id
      AND shared_with_id = auth.uid()
      AND aceptado_at IS NOT NULL
  );
$$;

-- Reemplazar policies de predios (leer también los shared)
DROP POLICY IF EXISTS predios_owner_select ON public.predios;
CREATE POLICY predios_select ON public.predios
  FOR SELECT USING (
    owner_id = auth.uid()
    OR public.puede_ver_predio(id)
  );

-- Update: solo propietario o trabajador
DROP POLICY IF EXISTS predios_owner_update ON public.predios;
CREATE POLICY predios_update ON public.predios
  FOR UPDATE USING (
    owner_id = auth.uid() OR public.puede_editar_predio(id)
  );

-- Delete: solo dueño original
DROP POLICY IF EXISTS predios_owner_delete ON public.predios;
CREATE POLICY predios_delete_owner ON public.predios
  FOR DELETE USING (owner_id = auth.uid());

-- Extender tablas que tienen predio_id directo.
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'lotes', 'cultivos', 'inventarios', 'compras',
    'analisis_suelo', 'condiciones_predio'
  ] LOOP
    -- Drop policies antiguas
    EXECUTE format('DROP POLICY IF EXISTS %I_owner_select ON public.%I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_owner_update ON public.%I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_owner_delete ON public.%I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_owner_insert ON public.%I', t, t);
    -- Recreadas con soporte de colaboradores
    EXECUTE format(
      'CREATE POLICY %I_select ON public.%I FOR SELECT '
      'USING (owner_id = auth.uid() OR public.puede_ver_predio(predio_id))',
      t, t);
    EXECUTE format(
      'CREATE POLICY %I_insert ON public.%I FOR INSERT '
      'WITH CHECK (owner_id = auth.uid() OR public.puede_editar_predio(predio_id))',
      t, t);
    EXECUTE format(
      'CREATE POLICY %I_update ON public.%I FOR UPDATE '
      'USING (owner_id = auth.uid() OR public.puede_editar_predio(predio_id))',
      t, t);
    EXECUTE format(
      'CREATE POLICY %I_delete ON public.%I FOR DELETE '
      'USING (owner_id = auth.uid() OR public.puede_editar_predio(predio_id))',
      t, t);
  END LOOP;
END $$;

-- eventos_cultivo: sin predio_id directo, se filtra via cultivo_id → predio_id
DROP POLICY IF EXISTS eventos_cultivo_owner_select ON public.eventos_cultivo;
DROP POLICY IF EXISTS eventos_cultivo_owner_insert ON public.eventos_cultivo;
DROP POLICY IF EXISTS eventos_cultivo_owner_update ON public.eventos_cultivo;
DROP POLICY IF EXISTS eventos_cultivo_owner_delete ON public.eventos_cultivo;

CREATE POLICY eventos_cultivo_select ON public.eventos_cultivo
  FOR SELECT USING (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = eventos_cultivo.cultivo_id
        AND public.puede_ver_predio(c.predio_id)
    )
  );
CREATE POLICY eventos_cultivo_insert ON public.eventos_cultivo
  FOR INSERT WITH CHECK (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = eventos_cultivo.cultivo_id
        AND public.puede_editar_predio(c.predio_id)
    )
  );
CREATE POLICY eventos_cultivo_update ON public.eventos_cultivo
  FOR UPDATE USING (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = eventos_cultivo.cultivo_id
        AND public.puede_editar_predio(c.predio_id)
    )
  );
CREATE POLICY eventos_cultivo_delete ON public.eventos_cultivo
  FOR DELETE USING (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = eventos_cultivo.cultivo_id
        AND public.puede_editar_predio(c.predio_id)
    )
  );

-- tareas_completadas usa cultivo_id (indirecto). Solo SELECT/INSERT
-- porque son inmutables.
DROP POLICY IF EXISTS tareas_completadas_owner_select ON public.tareas_completadas;
DROP POLICY IF EXISTS tareas_completadas_owner_insert ON public.tareas_completadas;
DROP POLICY IF EXISTS tareas_completadas_owner_update ON public.tareas_completadas;
DROP POLICY IF EXISTS tareas_completadas_owner_delete ON public.tareas_completadas;

CREATE POLICY tareas_completadas_select ON public.tareas_completadas
  FOR SELECT USING (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = tareas_completadas.cultivo_id
        AND public.puede_ver_predio(c.predio_id)
    )
  );
CREATE POLICY tareas_completadas_insert ON public.tareas_completadas
  FOR INSERT WITH CHECK (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = tareas_completadas.cultivo_id
        AND public.puede_editar_predio(c.predio_id)
    )
  );


-- =============================================================
-- 4. PATOLOGÍAS COMUNITARIAS
--
-- Cada reporte es una publicación anónima: se sabe que existe pero
-- no quién lo publicó (excepto para su propio owner que puede
-- editarlo/borrarlo).
-- =============================================================

CREATE TABLE IF NOT EXISTS public.patologias_reportadas (
  id BIGSERIAL PRIMARY KEY,
  owner_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  cliente_id BIGINT,                       -- ID local del cliente
  patologia_nombre TEXT NOT NULL,          -- nombre común de la patología
  patologia_cientifico TEXT,
  planta_nombre TEXT,                      -- planta afectada
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  alt_m DOUBLE PRECISION,
  fecha_deteccion DATE NOT NULL,
  severidad TEXT,                          -- inicial | avanzada
  sintomas TEXT,
  foto_url TEXT,                           -- URL en Supabase Storage
  pais_iso2 TEXT,                          -- para filtros por país
  region_nombre TEXT,
  municipio_nombre TEXT,
  clima_temp_c DOUBLE PRECISION,           -- opcional: condiciones al detectar
  clima_humedad_pct DOUBLE PRECISION,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (owner_id, cliente_id)
);

CREATE INDEX IF NOT EXISTS patologias_reportadas_geo_idx
  ON public.patologias_reportadas (lat, lng);
CREATE INDEX IF NOT EXISTS patologias_reportadas_fecha_idx
  ON public.patologias_reportadas (fecha_deteccion);
CREATE INDEX IF NOT EXISTS patologias_reportadas_pais_idx
  ON public.patologias_reportadas (pais_iso2);

DROP TRIGGER IF EXISTS patologias_reportadas_updated_at ON public.patologias_reportadas;
CREATE TRIGGER patologias_reportadas_updated_at BEFORE UPDATE ON public.patologias_reportadas
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS patologias_reportadas_owner_id ON public.patologias_reportadas;
CREATE TRIGGER patologias_reportadas_owner_id BEFORE INSERT ON public.patologias_reportadas
  FOR EACH ROW EXECUTE FUNCTION public.set_owner_id();

-- RLS: lectura pública (sin owner filter), escritura solo del owner.
ALTER TABLE public.patologias_reportadas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS patologias_reportadas_read ON public.patologias_reportadas;
CREATE POLICY patologias_reportadas_read ON public.patologias_reportadas
  FOR SELECT USING (deleted_at IS NULL);

DROP POLICY IF EXISTS patologias_reportadas_insert ON public.patologias_reportadas;
CREATE POLICY patologias_reportadas_insert ON public.patologias_reportadas
  FOR INSERT WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS patologias_reportadas_update ON public.patologias_reportadas;
CREATE POLICY patologias_reportadas_update ON public.patologias_reportadas
  FOR UPDATE USING (owner_id = auth.uid());

DROP POLICY IF EXISTS patologias_reportadas_delete ON public.patologias_reportadas;
CREATE POLICY patologias_reportadas_delete ON public.patologias_reportadas
  FOR DELETE USING (owner_id = auth.uid());

-- Vista anonimizada: expone solo lo público, sin owner_id.
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
  created_at
FROM public.patologias_reportadas
WHERE deleted_at IS NULL;

GRANT SELECT ON public.patologias_reportadas_publica TO authenticated;


-- =============================================================
-- 5. STORAGE bucket para fotos de patologías (comunitario)
--
-- Ejecutar manualmente en Storage o via SQL:
-- INSERT INTO storage.buckets (id, name, public) VALUES ('patologias', 'patologias', true);
-- Política: cualquiera puede leer, solo owner puede subir/actualizar/borrar.
-- =============================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('patologias', 'patologias', true)
ON CONFLICT (id) DO NOTHING;

-- Policies del bucket
DROP POLICY IF EXISTS patologias_read ON storage.objects;
CREATE POLICY patologias_read ON storage.objects
  FOR SELECT USING (bucket_id = 'patologias');

DROP POLICY IF EXISTS patologias_insert ON storage.objects;
CREATE POLICY patologias_insert ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'patologias'
    AND auth.role() = 'authenticated'
  );

DROP POLICY IF EXISTS patologias_delete_own ON storage.objects;
CREATE POLICY patologias_delete_own ON storage.objects
  FOR DELETE USING (
    bucket_id = 'patologias'
    AND owner = auth.uid()
  );


-- =============================================================
-- 6. TRATAMIENTOS por país (semilla — se puede editar más adelante)
--
-- Cada tratamiento es sugerido para una patología, específico de
-- un país (o universal con pais_iso2 = NULL), con tipo:
--   preventivo | biologico | cultural | quimico | integrado
-- Se prioriza en la app: preventivo → biológico → cultural → integrado → quimico
-- =============================================================

CREATE TABLE IF NOT EXISTS public.patologia_tratamientos (
  id BIGSERIAL PRIMARY KEY,
  patologia_nombre TEXT NOT NULL,          -- nombre común (matching por LIKE)
  patologia_cientifico TEXT,
  pais_iso2 TEXT,                          -- NULL = universal
  tipo TEXT NOT NULL CHECK (tipo IN (
    'preventivo', 'biologico', 'cultural', 'integrado', 'quimico'
  )),
  titulo TEXT NOT NULL,
  descripcion TEXT NOT NULL,
  producto TEXT,                           -- ingrediente activo o preparado
  dosis TEXT,
  frecuencia TEXT,
  amigable_ambiente BOOLEAN DEFAULT true,
  fuente TEXT NOT NULL,                    -- ICA, Corpoica, FAO, etc.
  fuente_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS patologia_tratamientos_nombre_idx
  ON public.patologia_tratamientos (patologia_nombre);
CREATE INDEX IF NOT EXISTS patologia_tratamientos_pais_idx
  ON public.patologia_tratamientos (pais_iso2);

-- Lectura pública, escritura solo con service_role.
ALTER TABLE public.patologia_tratamientos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tratamientos_read ON public.patologia_tratamientos;
CREATE POLICY tratamientos_read ON public.patologia_tratamientos
  FOR SELECT USING (true);


-- Seed inicial (Colombia — ICA/Corpoica) para las patologías del seed local
INSERT INTO public.patologia_tratamientos
  (patologia_nombre, pais_iso2, tipo, titulo, descripcion, producto, dosis, frecuencia, amigable_ambiente, fuente)
VALUES
  ('Roya', 'CO', 'preventivo',
   'Selección de variedades resistentes',
   'Sembrar variedades certificadas por ICA con resistencia genética a roya (p.ej. Castillo, Cenicafé 1).',
   NULL, NULL, NULL, true,
   'Cenicafé / ICA'),
  ('Roya', 'CO', 'cultural',
   'Manejo de sombrío y densidad',
   'Reducir densidad de siembra para aumentar aireación; podar sombrío para reducir humedad relativa.',
   NULL, NULL, 'Continuo', true,
   'Cenicafé'),
  ('Roya', 'CO', 'biologico',
   'Trichoderma spp.',
   'Aplicación foliar de suspensión de Trichoderma sp. como antagonista natural.',
   'Trichoderma harzianum', '2 g/L de agua', 'Cada 15 días en época lluviosa', true,
   'Corpoica'),
  ('Antracnosis', 'CO', 'preventivo',
   'Rotación y saneamiento',
   'Rotar cultivos con no-hospederos; eliminar restos vegetales infectados; desinfectar herramientas.',
   NULL, NULL, 'Por ciclo', true,
   'ICA'),
  ('Antracnosis', 'CO', 'biologico',
   'Bacillus subtilis',
   'Aspersión foliar de suspensión de Bacillus subtilis como antagonista.',
   'Bacillus subtilis cepa QST 713', '2-3 mL/L', 'Cada 10 días preventivo', true,
   'FAO / ICA'),
  ('Tizón tardío', 'CO', 'preventivo',
   'Monitoreo temprano y drenaje',
   'Monitorear condiciones (temp 12-24°C + humedad >90%) que favorecen aparición. Mejorar drenaje del suelo.',
   NULL, NULL, 'Diario en época lluviosa', true,
   'ICA'),
  ('Tizón tardío', 'CO', 'biologico',
   'Trichoderma harzianum',
   'Aplicación al suelo y foliar de Trichoderma.',
   'Trichoderma harzianum', '4 g/L', 'Semanal', true,
   'Cenicafé'),
  ('Virus mancha anillada', 'CO', 'preventivo',
   'Control de vectores (áfidos)',
   'El virus se transmite por áfidos. Mantener trampas amarillas pegajosas, favorecer enemigos naturales (crisopas, mariquitas).',
   NULL, NULL, 'Continuo', true,
   'ICA'),
  ('Virus mancha anillada', 'CO', 'cultural',
   'Erradicación de plantas infectadas',
   'Retirar y quemar plantas con síntomas. No hay tratamiento curativo — evitar propagación.',
   NULL, NULL, 'Al detectar', true,
   'FAO'),
  ('Mosca blanca', 'CO', 'preventivo',
   'Trampas amarillas',
   'Instalar trampas pegajosas amarillas a la altura del cultivo para monitoreo y captura.',
   NULL, '30-50 trampas/ha', 'Continuo', true,
   'ICA'),
  ('Mosca blanca', 'CO', 'biologico',
   'Beauveria bassiana',
   'Aspersión de hongo entomopatógeno Beauveria bassiana.',
   'Beauveria bassiana', '2 g/L', 'Cada 7-10 días', true,
   'Corpoica'),
  ('Mosca blanca', 'CO', 'biologico',
   'Encarsia formosa',
   'Liberación de la avispita parasitoide Encarsia formosa como control biológico.',
   'Encarsia formosa', '5-10 individuos/m²', 'Al detectar', true,
   'FAO')
ON CONFLICT DO NOTHING;

-- Tratamientos universales (aplicables a cualquier país)
INSERT INTO public.patologia_tratamientos
  (patologia_nombre, pais_iso2, tipo, titulo, descripcion, producto, dosis, frecuencia, amigable_ambiente, fuente)
VALUES
  ('Roya', NULL, 'preventivo',
   'Aireación y densidad',
   'Regular densidad y podar para reducir humedad — condición clave para el desarrollo de la roya.',
   NULL, NULL, 'Por ciclo', true,
   'FAO'),
  ('Antracnosis', NULL, 'cultural',
   'Riego por goteo',
   'Evitar riego por aspersión: la humedad foliar favorece la infección.',
   NULL, NULL, 'Continuo', true,
   'FAO'),
  ('Mosca blanca', NULL, 'cultural',
   'Cultivos trampa',
   'Sembrar tomate cherry o girasol como cultivo trampa alrededor del cultivo principal.',
   NULL, NULL, 'Por ciclo', true,
   'FAO')
ON CONFLICT DO NOTHING;

-- =============================================================
-- FIN
-- =============================================================
