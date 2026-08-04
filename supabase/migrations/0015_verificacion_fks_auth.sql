-- =====================================================================
-- Migración 0015 — Verificación y corrección de FKs hacia auth.users
-- (Revisión C2-2, 2026-08-03). Idempotente.
--
-- Por qué: `eliminar_mi_cuenta()` (0014) hace `DELETE FROM auth.users`
-- confiando en que TODAS las FKs hacia auth.users tengan una acción
-- referencial (CASCADE o SET NULL). Los archivos de esquema las declaran
-- bien, pero la BD viva pudo crearse con versiones previas. Una sola FK
-- con NO ACTION haría fallar el borrado de cuenta con un error críptico.
--
-- Qué hace:
--   1. Recorre todas las FKs de `public` que referencian auth.users.
--   2. Si su acción ON DELETE no es CASCADE ('c') ni SET NULL ('n'),
--      la RE-CREA con la acción correcta según la convención:
--        · patologias_reportadas.owner_id            → SET NULL (0014)
--        · created_by_user_id / created_by (autoría) → SET NULL
--        · owner_id / shared_with_id (propiedad)     → CASCADE
--   3. Verificación final: si queda alguna FK sin acción, ABORTA con
--      EXCEPTION (el script falla ruidosamente, nunca en silencio).
--
-- schema_meta → 12 (el cliente sigue exigiendo v11: sin dependencia).
-- =====================================================================

DO $$
DECLARE
  fk RECORD;
  col text;
  accion text;
BEGIN
  FOR fk IN
    SELECT c.oid,
           c.conname,
           c.conrelid::regclass AS tabla,
           c.confdeltype
    FROM pg_constraint c
    WHERE c.contype = 'f'
      AND c.confrelid = 'auth.users'::regclass
      AND c.connamespace = 'public'::regnamespace
      AND c.confdeltype NOT IN ('c', 'n')  -- sin CASCADE ni SET NULL
  LOOP
    -- Columna local de la FK (todas las FKs a auth.users son de 1 columna).
    SELECT a.attname INTO col
    FROM pg_attribute a
    WHERE a.attrelid = fk.conrelid::regclass::oid
      AND a.attnum = (SELECT conkey[1] FROM pg_constraint WHERE oid = fk.oid);

    -- Acción correcta según la convención del proyecto.
    IF fk.tabla::text = 'patologias_reportadas'
       OR col IN ('created_by_user_id', 'created_by') THEN
      accion := 'SET NULL';
    ELSE
      accion := 'CASCADE';
    END IF;

    RAISE NOTICE 'Corrigiendo FK %.% (%): ON DELETE %',
      fk.tabla, col, fk.conname, accion;

    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', fk.tabla, fk.conname);
    EXECUTE format(
      'ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (%I) '
      'REFERENCES auth.users(id) ON DELETE %s',
      fk.tabla, fk.conname, col, accion);
  END LOOP;

  -- Verificación final dura: ninguna FK a auth.users puede quedar sin
  -- acción referencial. Si queda alguna, el script falla aquí.
  IF EXISTS (
    SELECT 1 FROM pg_constraint c
    WHERE c.contype = 'f'
      AND c.confrelid = 'auth.users'::regclass
      AND c.connamespace = 'public'::regnamespace
      AND c.confdeltype NOT IN ('c', 'n')
  ) THEN
    RAISE EXCEPTION
      'Quedan FKs hacia auth.users sin CASCADE/SET NULL — revisar manualmente';
  END IF;
END $$;

INSERT INTO public.schema_meta (id, version)
VALUES (1, 12)
ON CONFLICT (id) DO UPDATE
SET version = GREATEST(public.schema_meta.version, 12),
    applied_at = NOW();

-- ---------------------------------------------------------------------
-- Consulta de auditoría (solo lectura — ejecutar cuando se quiera):
-- confdeltype: c = CASCADE · n = SET NULL (ambos correctos)
-- ---------------------------------------------------------------------
SELECT c.conrelid::regclass AS tabla,
       (SELECT a.attname FROM pg_attribute a
         WHERE a.attrelid = c.conrelid AND a.attnum = c.conkey[1]) AS columna,
       c.confdeltype AS accion
FROM pg_constraint c
WHERE c.contype = 'f'
  AND c.confrelid = 'auth.users'::regclass
  AND c.connamespace = 'public'::regnamespace
ORDER BY 1;
