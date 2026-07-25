-- =============================================================
-- NEXUS Siembras — Schema Postgres para Supabase (Fase 3d)
-- =============================================================
--
-- Cómo aplicar:
--   1. En el dashboard de Supabase → SQL Editor → New query.
--   2. Pegar TODO este archivo.
--   3. Run (parte inferior derecha).
--   4. Verificar en Table Editor que aparezcan las tablas.
--
-- Notas de diseño:
--   * Cada tabla tiene `owner_id UUID` FK a auth.users(id), rellenado
--     automáticamente por defecto con auth.uid() (usuario logueado).
--   * Row-Level Security (RLS) filtra por owner_id, garantizando que
--     cada usuario solo ve/edita sus propios datos.
--   * Timestamps `created_at` y `updated_at` autogestionados por trigger.
--   * IDs propios son BIGINT (mismo tipo que Drift local usa como INTEGER
--     autoincremental). Al sincronizar mapeamos local↔nube por (owner_id, cliente_id).
--   * `predio_shares` habilita compartir un predio con otro usuario
--     (fase futura de colaboración multi-usuario).
--
-- Este archivo es idempotente en la parte de tablas (CREATE TABLE IF NOT
-- EXISTS) pero NO en la parte de políticas (rerun genera error de duplicado).
-- Para reinstalar limpio: ejecutar `DROP SCHEMA public CASCADE; CREATE SCHEMA public;`
-- primero — CUIDADO: eso borra TODOS los datos.
-- =============================================================

-- Trigger genérico para updated_at ------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Función para inyectar owner_id automáticamente ---------------
CREATE OR REPLACE FUNCTION public.set_owner_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.owner_id IS NULL THEN
    NEW.owner_id = auth.uid();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================
-- PREDIOS
-- =============================================================
CREATE TABLE IF NOT EXISTS public.predios (
  id BIGSERIAL PRIMARY KEY,
  owner_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  cliente_id BIGINT,               -- ID local del cliente (para mapping)
  nombre TEXT NOT NULL,
  propietario TEXT,
  pais_iso2 TEXT,
  region_nombre TEXT,
  municipio_nombre TEXT,
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  alt_m DOUBLE PRECISION,
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (owner_id, cliente_id)
);

CREATE INDEX IF NOT EXISTS predios_owner_idx ON public.predios(owner_id);

DROP TRIGGER IF EXISTS predios_updated_at ON public.predios;
CREATE TRIGGER predios_updated_at BEFORE UPDATE ON public.predios
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS predios_owner_id ON public.predios;
CREATE TRIGGER predios_owner_id BEFORE INSERT ON public.predios
  FOR EACH ROW EXECUTE FUNCTION public.set_owner_id();

-- =============================================================
-- LOTES
-- =============================================================
CREATE TABLE IF NOT EXISTS public.lotes (
  id BIGSERIAL PRIMARY KEY,
  owner_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  cliente_id BIGINT,
  predio_id BIGINT NOT NULL REFERENCES public.predios(id) ON DELETE CASCADE,
  nombre TEXT NOT NULL,
  administrador TEXT,
  altitud_msnm DOUBLE PRECISION,
  area_m2 DOUBLE PRECISION,
  poligono_geojson TEXT,
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (owner_id, cliente_id)
);

CREATE INDEX IF NOT EXISTS lotes_predio_idx ON public.lotes(predio_id);

DROP TRIGGER IF EXISTS lotes_updated_at ON public.lotes;
CREATE TRIGGER lotes_updated_at BEFORE UPDATE ON public.lotes
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS lotes_owner_id ON public.lotes;
CREATE TRIGGER lotes_owner_id BEFORE INSERT ON public.lotes
  FOR EACH ROW EXECUTE FUNCTION public.set_owner_id();

-- =============================================================
-- PROVEEDORES (globales por usuario, no por predio)
-- =============================================================
CREATE TABLE IF NOT EXISTS public.proveedores (
  id BIGSERIAL PRIMARY KEY,
  owner_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  cliente_id BIGINT,
  nombre TEXT NOT NULL,
  nit TEXT,
  telefono TEXT,
  email TEXT,
  web TEXT,
  direccion TEXT,
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (owner_id, cliente_id)
);

DROP TRIGGER IF EXISTS proveedores_updated_at ON public.proveedores;
CREATE TRIGGER proveedores_updated_at BEFORE UPDATE ON public.proveedores
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS proveedores_owner_id ON public.proveedores;
CREATE TRIGGER proveedores_owner_id BEFORE INSERT ON public.proveedores
  FOR EACH ROW EXECUTE FUNCTION public.set_owner_id();

-- =============================================================
-- CULTIVOS
-- =============================================================
CREATE TABLE IF NOT EXISTS public.cultivos (
  id BIGSERIAL PRIMARY KEY,
  owner_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  cliente_id BIGINT,
  predio_id BIGINT NOT NULL REFERENCES public.predios(id) ON DELETE CASCADE,
  lote_id BIGINT REFERENCES public.lotes(id) ON DELETE SET NULL,
  planta_id_local BIGINT,                -- ID local del catálogo (no FK — catálogo no se sync)
  nombre_planta TEXT,                    -- Nombre denormalizado para sync sin catálogo
  nombre_lote TEXT,
  fecha_siembra DATE NOT NULL,
  fecha_cosecha_estimada DATE,
  area_base_m2 DOUBLE PRECISION,
  cantidad_semilla_base DOUBLE PRECISION,
  cantidad_semilla_unidad_base TEXT,
  hh_total DOUBLE PRECISION DEFAULT 0,
  hora_valor DOUBLE PRECISION,
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  alt_m DOUBLE PRECISION,
  finalizado_fecha DATE,
  notas TEXT,
  tipo_cultivo TEXT NOT NULL DEFAULT 'ciclo_unico',
  cosecha1_dias INTEGER,
  cosecha2_dias INTEGER,
  periodicidad_cosecha_dias INTEGER,
  esperanza_vida_dias INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (owner_id, cliente_id)
);

CREATE INDEX IF NOT EXISTS cultivos_predio_idx ON public.cultivos(predio_id);

DROP TRIGGER IF EXISTS cultivos_updated_at ON public.cultivos;
CREATE TRIGGER cultivos_updated_at BEFORE UPDATE ON public.cultivos
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS cultivos_owner_id ON public.cultivos;
CREATE TRIGGER cultivos_owner_id BEFORE INSERT ON public.cultivos
  FOR EACH ROW EXECUTE FUNCTION public.set_owner_id();

-- =============================================================
-- EVENTOS DE CULTIVO
-- =============================================================
CREATE TABLE IF NOT EXISTS public.eventos_cultivo (
  id BIGSERIAL PRIMARY KEY,
  owner_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  cliente_id BIGINT,
  cultivo_id BIGINT NOT NULL REFERENCES public.cultivos(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL,
  fecha_programada DATE,
  fecha_ejecutada DATE,
  descripcion TEXT,
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (owner_id, cliente_id)
);

CREATE INDEX IF NOT EXISTS eventos_cultivo_cultivo_idx ON public.eventos_cultivo(cultivo_id);

DROP TRIGGER IF EXISTS eventos_updated_at ON public.eventos_cultivo;
CREATE TRIGGER eventos_updated_at BEFORE UPDATE ON public.eventos_cultivo
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS eventos_owner_id ON public.eventos_cultivo;
CREATE TRIGGER eventos_owner_id BEFORE INSERT ON public.eventos_cultivo
  FOR EACH ROW EXECUTE FUNCTION public.set_owner_id();

-- =============================================================
-- TAREAS COMPLETADAS
-- =============================================================
CREATE TABLE IF NOT EXISTS public.tareas_completadas (
  id BIGSERIAL PRIMARY KEY,
  owner_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  cliente_id BIGINT,
  cultivo_id BIGINT NOT NULL REFERENCES public.cultivos(id) ON DELETE CASCADE,
  fecha DATE NOT NULL,
  hh DOUBLE PRECISION DEFAULT 0,
  actividades_json JSONB NOT NULL,
  insumos_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (owner_id, cliente_id)
);

CREATE INDEX IF NOT EXISTS tareas_cultivo_idx ON public.tareas_completadas(cultivo_id);

DROP TRIGGER IF EXISTS tareas_owner_id ON public.tareas_completadas;
CREATE TRIGGER tareas_owner_id BEFORE INSERT ON public.tareas_completadas
  FOR EACH ROW EXECUTE FUNCTION public.set_owner_id();

-- =============================================================
-- INVENTARIO
-- =============================================================
CREATE TABLE IF NOT EXISTS public.inventarios (
  id BIGSERIAL PRIMARY KEY,
  owner_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  cliente_id BIGINT,
  predio_id BIGINT NOT NULL REFERENCES public.predios(id) ON DELETE CASCADE,
  fecha DATE NOT NULL,
  codigo TEXT,
  descripcion TEXT NOT NULL,
  fabricante TEXT,
  cantidad_base DOUBLE PRECISION NOT NULL,
  unidad_base TEXT NOT NULL,
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (owner_id, cliente_id)
);

DROP TRIGGER IF EXISTS inventarios_updated_at ON public.inventarios;
CREATE TRIGGER inventarios_updated_at BEFORE UPDATE ON public.inventarios
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS inventarios_owner_id ON public.inventarios;
CREATE TRIGGER inventarios_owner_id BEFORE INSERT ON public.inventarios
  FOR EACH ROW EXECUTE FUNCTION public.set_owner_id();

-- =============================================================
-- COMPRAS
-- =============================================================
CREATE TABLE IF NOT EXISTS public.compras (
  id BIGSERIAL PRIMARY KEY,
  owner_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  cliente_id BIGINT,
  predio_id BIGINT NOT NULL REFERENCES public.predios(id) ON DELETE CASCADE,
  proveedor_id BIGINT REFERENCES public.proveedores(id) ON DELETE SET NULL,
  fecha DATE NOT NULL,
  descripcion1 TEXT NOT NULL,
  descripcion2 TEXT,
  valor_total DOUBLE PRECISION NOT NULL,
  cantidad_base DOUBLE PRECISION NOT NULL,
  unidad_base TEXT NOT NULL,
  codigo TEXT,
  factura TEXT,
  tipo TEXT,
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (owner_id, cliente_id)
);

DROP TRIGGER IF EXISTS compras_updated_at ON public.compras;
CREATE TRIGGER compras_updated_at BEFORE UPDATE ON public.compras
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS compras_owner_id ON public.compras;
CREATE TRIGGER compras_owner_id BEFORE INSERT ON public.compras
  FOR EACH ROW EXECUTE FUNCTION public.set_owner_id();

-- =============================================================
-- ANÁLISIS DE SUELO
-- =============================================================
CREATE TABLE IF NOT EXISTS public.analisis_suelo (
  id BIGSERIAL PRIMARY KEY,
  owner_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  cliente_id BIGINT,
  predio_id BIGINT NOT NULL REFERENCES public.predios(id) ON DELETE CASCADE,
  lote TEXT,
  fecha_muestreo DATE NOT NULL,
  laboratorio TEXT,
  profundidad_cm DOUBLE PRECISION,
  textura TEXT,
  densidad_g_cm3 DOUBLE PRECISION,
  conductividad_ms_cm DOUBLE PRECISION,
  ph DOUBLE PRECISION,
  materia_organica_pct DOUBLE PRECISION,
  n_ppm DOUBLE PRECISION,
  p_ppm DOUBLE PRECISION,
  k_ppm DOUBLE PRECISION,
  ca_meq DOUBLE PRECISION,
  mg_meq DOUBLE PRECISION,
  na_meq DOUBLE PRECISION,
  cic_meq DOUBLE PRECISION,
  s_ppm DOUBLE PRECISION,
  b_ppm DOUBLE PRECISION,
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (owner_id, cliente_id)
);

DROP TRIGGER IF EXISTS analisis_updated_at ON public.analisis_suelo;
CREATE TRIGGER analisis_updated_at BEFORE UPDATE ON public.analisis_suelo
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS analisis_owner_id ON public.analisis_suelo;
CREATE TRIGGER analisis_owner_id BEFORE INSERT ON public.analisis_suelo
  FOR EACH ROW EXECUTE FUNCTION public.set_owner_id();

-- =============================================================
-- CONDICIONES EDAFOCLIMÁTICAS DEL PREDIO (1 por predio)
-- =============================================================
CREATE TABLE IF NOT EXISTS public.condiciones_predio (
  id BIGSERIAL PRIMARY KEY,
  owner_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  predio_id BIGINT NOT NULL UNIQUE REFERENCES public.predios(id) ON DELETE CASCADE,
  altitud_msnm DOUBLE PRECISION,
  precipitacion_anual_mm DOUBLE PRECISION,
  temp_media_c DOUBLE PRECISION,
  temp_min_c DOUBLE PRECISION,
  temp_max_c DOUBLE PRECISION,
  humedad_relativa_pct DOUBLE PRECISION,
  zona_climatica TEXT,
  piso_termico TEXT,
  fuente TEXT,
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

DROP TRIGGER IF EXISTS condiciones_updated_at ON public.condiciones_predio;
CREATE TRIGGER condiciones_updated_at BEFORE UPDATE ON public.condiciones_predio
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS condiciones_owner_id ON public.condiciones_predio;
CREATE TRIGGER condiciones_owner_id BEFORE INSERT ON public.condiciones_predio
  FOR EACH ROW EXECUTE FUNCTION public.set_owner_id();

-- =============================================================
-- COMPARTIR PREDIO (colaboración multi-usuario, fase futura)
-- =============================================================
CREATE TABLE IF NOT EXISTS public.predio_shares (
  id BIGSERIAL PRIMARY KEY,
  predio_id BIGINT NOT NULL REFERENCES public.predios(id) ON DELETE CASCADE,
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,     -- dueño
  shared_with_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, -- invitado
  rol TEXT NOT NULL CHECK (rol IN ('propietario', 'trabajador', 'consultor')),
  invitado_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  aceptado_at TIMESTAMPTZ,
  UNIQUE (predio_id, shared_with_id)
);

-- =============================================================
-- ROW-LEVEL SECURITY
-- =============================================================
-- Cada tabla se filtra por owner_id = auth.uid()
-- (En fase futura, `predio_shares` extenderá el filtro para permitir
--  a colaboradores ver/editar predios ajenos según su rol.)

ALTER TABLE public.predios              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lotes                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.proveedores          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cultivos             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eventos_cultivo      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tareas_completadas   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventarios          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.compras              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analisis_suelo       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.condiciones_predio   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.predio_shares        ENABLE ROW LEVEL SECURITY;

-- Política genérica: dueño ve/edita todo lo suyo ---------------
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'predios','lotes','proveedores','cultivos','eventos_cultivo',
    'tareas_completadas','inventarios','compras','analisis_suelo',
    'condiciones_predio'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I_owner_select ON public.%I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_owner_insert ON public.%I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_owner_update ON public.%I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_owner_delete ON public.%I', t, t);

    EXECUTE format(
      'CREATE POLICY %I_owner_select ON public.%I FOR SELECT USING (owner_id = auth.uid())', t, t);
    EXECUTE format(
      'CREATE POLICY %I_owner_insert ON public.%I FOR INSERT WITH CHECK (owner_id = auth.uid())', t, t);
    EXECUTE format(
      'CREATE POLICY %I_owner_update ON public.%I FOR UPDATE USING (owner_id = auth.uid())', t, t);
    EXECUTE format(
      'CREATE POLICY %I_owner_delete ON public.%I FOR DELETE USING (owner_id = auth.uid())', t, t);
  END LOOP;
END $$;

-- Predio_shares: dueño ve todos los shares del predio que creó,
-- y el invitado ve solo los shares que lo mencionan.
DROP POLICY IF EXISTS predio_shares_read      ON public.predio_shares;
DROP POLICY IF EXISTS predio_shares_owner_ins ON public.predio_shares;
DROP POLICY IF EXISTS predio_shares_owner_del ON public.predio_shares;

CREATE POLICY predio_shares_read ON public.predio_shares
  FOR SELECT USING (owner_id = auth.uid() OR shared_with_id = auth.uid());

CREATE POLICY predio_shares_owner_ins ON public.predio_shares
  FOR INSERT WITH CHECK (owner_id = auth.uid());

CREATE POLICY predio_shares_owner_del ON public.predio_shares
  FOR DELETE USING (owner_id = auth.uid());

-- =============================================================
-- REALTIME (opcional, para pull sync push por cambios)
-- =============================================================
-- Descomenta si quieres que el cliente reciba cambios en vivo:
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.predios;
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.cultivos;
-- (repetir para las tablas que necesites)

-- =============================================================
-- FIN
-- =============================================================
