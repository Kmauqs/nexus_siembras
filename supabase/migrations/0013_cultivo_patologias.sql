-- =====================================================================
-- Migración 0013 — Sync de patologías por cultivo entre colaboradores
-- Reportes en `cultivo_patologias` visibles/editables para propietario
-- y trabajador del predio (misma regla que cultivos).
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.cultivo_patologias (
  id BIGSERIAL PRIMARY KEY,
  owner_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  cliente_id BIGINT,
  cultivo_id BIGINT NOT NULL REFERENCES public.cultivos(id) ON DELETE CASCADE,
  -- Catálogo local no se synca: denormalizamos nombre/tipo para el peer.
  patologia_nombre TEXT NOT NULL DEFAULT '',
  patologia_cientifico TEXT,
  patologia_tipo TEXT,
  fecha_deteccion DATE NOT NULL,
  severidad TEXT,
  fuente_diagnostico TEXT,
  confianza DOUBLE PRECISION,
  resuelta_at TIMESTAMPTZ,
  cura_fecha DATE,
  intervenciones_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  notas TEXT,
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  alt_m DOUBLE PRECISION,
  compartida BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (owner_id, cliente_id)
);

CREATE INDEX IF NOT EXISTS cultivo_patologias_cultivo_idx
  ON public.cultivo_patologias(cultivo_id);
CREATE INDEX IF NOT EXISTS cultivo_patologias_updated_at_idx
  ON public.cultivo_patologias(updated_at DESC);

DROP TRIGGER IF EXISTS cultivo_patologias_updated_at ON public.cultivo_patologias;
CREATE TRIGGER cultivo_patologias_updated_at
  BEFORE UPDATE ON public.cultivo_patologias
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS cultivo_patologias_owner_id ON public.cultivo_patologias;
CREATE TRIGGER cultivo_patologias_owner_id
  BEFORE INSERT ON public.cultivo_patologias
  FOR EACH ROW EXECUTE FUNCTION public.set_owner_id();

-- Cap de reloj (auditoría P5), si existe la función.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'cap_updated_at'
  ) THEN
    DROP TRIGGER IF EXISTS trg_cap_updated_at ON public.cultivo_patologias;
    CREATE TRIGGER trg_cap_updated_at
      BEFORE INSERT OR UPDATE ON public.cultivo_patologias
      FOR EACH ROW EXECUTE FUNCTION public.cap_updated_at();
  END IF;
END $$;

ALTER TABLE public.cultivo_patologias ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cultivo_patologias_select ON public.cultivo_patologias;
DROP POLICY IF EXISTS cultivo_patologias_insert ON public.cultivo_patologias;
DROP POLICY IF EXISTS cultivo_patologias_update ON public.cultivo_patologias;
DROP POLICY IF EXISTS cultivo_patologias_delete ON public.cultivo_patologias;
DROP POLICY IF EXISTS cultivo_patologias_owner_select ON public.cultivo_patologias;
DROP POLICY IF EXISTS cultivo_patologias_owner_insert ON public.cultivo_patologias;
DROP POLICY IF EXISTS cultivo_patologias_owner_update ON public.cultivo_patologias;
DROP POLICY IF EXISTS cultivo_patologias_owner_delete ON public.cultivo_patologias;

CREATE POLICY cultivo_patologias_select ON public.cultivo_patologias
  FOR SELECT USING (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = cultivo_id
        AND public.puede_ver_predio(c.predio_id)
    )
  );

CREATE POLICY cultivo_patologias_insert ON public.cultivo_patologias
  FOR INSERT WITH CHECK (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = cultivo_id
        AND public.puede_editar_predio(c.predio_id)
    )
  );

CREATE POLICY cultivo_patologias_update ON public.cultivo_patologias
  FOR UPDATE USING (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = cultivo_id
        AND public.puede_editar_predio(c.predio_id)
    )
  );

CREATE POLICY cultivo_patologias_delete ON public.cultivo_patologias
  FOR DELETE USING (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cultivos c
      WHERE c.id = cultivo_id
        AND public.puede_editar_predio(c.predio_id)
    )
  );

INSERT INTO public.schema_meta (id, version)
VALUES (1, 10)
ON CONFLICT (id) DO UPDATE SET version = GREATEST(public.schema_meta.version, 10),
  applied_at = now();
