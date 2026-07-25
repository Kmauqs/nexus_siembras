-- =============================================================
-- NEXUS Siembras — Fix: eliminar shares "invertidos" espurios
-- =============================================================
-- Síntoma (Fase 3e-9-9):
--   Al abrir "Finca de prueba A" en la Cuenta A, camuquisu@outlook.com
--   aparece como "Propietario · control total" en vez de "Trabajador".
--
-- Causa raíz:
--   Cuando la Cuenta B sincronizaba, el `_pushColaboradores` subía TODAS
--   sus filas locales de `predio_colaboradores`, incluida la fila
--   informativa con rol='propietario' que representaba al owner real del
--   predio (fila que `_mergeShare` inserta en la BD del invitado para
--   pintar al dueño en la card de colaboradores). Esa fila se colaba a
--   `predio_shares` remoto como (owner_id=B, shared_with_id=A,
--   rol='propietario') — un share invertido. Al bajarlo la Cuenta A
--   creaba una segunda fila local (colaboradorUserId=B, rol='propietario')
--   que hacía aparecer a B como Propietario en el listado.
--
-- El fix del cliente (Fase 3e-9-9) impide subir shares con rol='propietario'
-- y limpia las filas locales invertidas. Este script se ocupa de las
-- filas ya existentes en Postgres.
--
-- Ejecutar completo en el SQL Editor. Idempotente.
-- =============================================================


-- 1. Preview de las filas problemáticas ANTES de borrar.
--    Un share es "invertido" cuando el owner_id del share NO coincide con
--    el owner_id real del predio. También cualquier share con
--    rol='propietario' es espurio (predio_shares almacena invitados,
--    nunca propietarios).
SELECT
  ps.id AS share_id,
  ps.predio_id,
  p.nombre AS predio_nombre,
  (SELECT email FROM auth.users WHERE id = ps.owner_id) AS share_owner,
  (SELECT email FROM auth.users WHERE id = p.owner_id) AS predio_owner_real,
  (SELECT email FROM auth.users WHERE id = ps.shared_with_id) AS shared_with,
  ps.rol,
  CASE
    WHEN ps.rol = 'propietario' THEN '❌ rol propietario en shares'
    WHEN ps.owner_id != p.owner_id THEN '❌ owner_id invertido'
    ELSE '✓ ok'
  END AS diagnostico
FROM public.predio_shares ps
JOIN public.predios p ON p.id = ps.predio_id
WHERE ps.rol = 'propietario' OR ps.owner_id != p.owner_id
ORDER BY p.nombre;


-- 2. Purga: borra las filas invertidas identificadas arriba.
DELETE FROM public.predio_shares ps
USING public.predios p
WHERE ps.predio_id = p.id
  AND (ps.rol = 'propietario' OR ps.owner_id != p.owner_id);


-- 3. Verificación posterior — la query 1 no debe devolver filas.
SELECT
  ps.id AS share_id,
  p.nombre AS predio_nombre,
  ps.rol,
  CASE
    WHEN ps.rol = 'propietario' THEN '❌ rol propietario'
    WHEN ps.owner_id != p.owner_id THEN '❌ owner_id invertido'
    ELSE '✓ ok'
  END AS diagnostico
FROM public.predio_shares ps
JOIN public.predios p ON p.id = ps.predio_id
WHERE ps.rol = 'propietario' OR ps.owner_id != p.owner_id;
-- Esperado: 0 filas.


-- =============================================================
-- FIN
-- =============================================================
