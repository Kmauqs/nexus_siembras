-- =============================================================
-- Limpieza puntual de duplicados generados por el bug de sync
-- previo (colaborador editaba fila ajena → upsert por owner+cliente
-- creaba nueva fila con su owner_id).
--
-- Ejecutar SOLO desde el dashboard como service_role.
-- =============================================================

-- 1. Diagnóstico: cuántos lotes duplicados hay
SELECT predio_id, nombre, COUNT(*) as duplicados
FROM public.lotes
GROUP BY predio_id, nombre
HAVING COUNT(*) > 1;

-- 2. Elimina duplicados: para cada (predio_id, nombre) mantiene el MÁS ANTIGUO
-- (el que creó el propietario original), borra los demás.
WITH duplicados AS (
  SELECT id, ROW_NUMBER() OVER (
    PARTITION BY predio_id, nombre
    ORDER BY created_at ASC
  ) as rn
  FROM public.lotes
  WHERE deleted_at IS NULL
)
DELETE FROM public.lotes WHERE id IN (
  SELECT id FROM duplicados WHERE rn > 1
);

-- 3. Aplicar el mismo criterio a otras tablas si hubo duplicados
-- (cultivos, inventarios, etc.). Descomenta según necesites.
--
-- WITH d_cultivos AS (
--   SELECT id, ROW_NUMBER() OVER (
--     PARTITION BY predio_id, nombre_planta, fecha_siembra
--     ORDER BY created_at ASC
--   ) as rn
--   FROM public.cultivos
--   WHERE deleted_at IS NULL
-- )
-- DELETE FROM public.cultivos WHERE id IN (
--   SELECT id FROM d_cultivos WHERE rn > 1
-- );

-- 4. Verificar que ya no hay duplicados
SELECT predio_id, nombre, COUNT(*)
FROM public.lotes
WHERE deleted_at IS NULL
GROUP BY predio_id, nombre
HAVING COUNT(*) > 1;
-- Debe retornar 0 filas.
