-- =============================================================
-- Diagnóstico: por qué el colaborador no ve cultivos/inventario
-- =============================================================
-- IMPORTANTE: Supabase SQL Editor solo muestra el resultado del ÚLTIMO
-- SELECT. Ejecuta CADA BLOQUE por separado:
--
--   1. Selecciona el bloque completo (entre los "-- ▓▓▓ BLOQUE N ▓▓▓")
--   2. Click "Run" (o Ctrl+Enter en Windows)
--   3. Copia el resultado y pásalo aquí
--   4. Repite con el siguiente bloque
--
-- Los emails asumidos son:
--   Propietario:  mauchitoq@gmail.com
--   Colaborador:  camuquisu@outlook.com
-- Predio: 'Finca Villamariana'
-- =============================================================


-- ▓▓▓ BLOQUE 1 — usuarios ▓▓▓
SELECT id, email, created_at
FROM auth.users
WHERE email IN ('mauchitoq@gmail.com', 'camuquisu@outlook.com')
ORDER BY email;


-- ▓▓▓ BLOQUE 2 — shares del predio ▓▓▓
SELECT
  ps.id,
  p.nombre AS predio,
  (SELECT email FROM auth.users WHERE id = ps.owner_id) AS propietario,
  (SELECT email FROM auth.users WHERE id = ps.shared_with_id) AS colaborador,
  ps.rol,
  ps.invitado_at,
  ps.aceptado_at,
  CASE
    WHEN ps.aceptado_at IS NULL THEN '❌ NO ACEPTADO'
    ELSE '✓ Aceptado'
  END AS estado
FROM public.predio_shares ps
JOIN public.predios p ON p.id = ps.predio_id
WHERE p.nombre = 'Finca Villamariana';


-- ▓▓▓ BLOQUE 3 — cultivos en el predio ▓▓▓
SELECT
  c.id,
  c.nombre_planta,
  c.predio_id,
  (SELECT email FROM auth.users WHERE id = c.owner_id) AS owner,
  c.updated_at,
  c.deleted_at
FROM public.cultivos c
JOIN public.predios p ON p.id = c.predio_id
WHERE p.nombre = 'Finca Villamariana';
-- Si retorna 0 filas → los cultivos NUNCA se subieron desde Cuenta A.
-- Solución: entra a Cuenta A → Cuenta → "Sincronizar ahora".


-- ▓▓▓ BLOQUE 4 — inventarios en el predio ▓▓▓
SELECT
  i.id,
  i.descripcion,
  i.cantidad_base,
  i.predio_id,
  (SELECT email FROM auth.users WHERE id = i.owner_id) AS owner,
  i.deleted_at
FROM public.inventarios i
JOIN public.predios p ON p.id = i.predio_id
WHERE p.nombre = 'Finca Villamariana';


-- ▓▓▓ BLOQUE 5 — simulación RLS como colaborador ▓▓▓
-- Este bloque simula ser 'camuquisu@outlook.com' y ejecuta rol_en_predio()
-- + puede_ver_predio() sobre 'Finca Villamariana'. Debe retornar:
--   rol_calculado = 'trabajador' (o 'consultor')
--   puede_ver     = true
WITH cfg AS (
  SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT id::text FROM auth.users WHERE email = 'camuquisu@outlook.com'),
    true
  ) AS uid_simulado
)
SELECT
  cfg.uid_simulado AS uid_camuquisu,
  p.id AS predio_id,
  p.nombre,
  public.rol_en_predio(p.id) AS rol_calculado,
  public.puede_ver_predio(p.id) AS puede_ver
FROM public.predios p, cfg
WHERE p.nombre = 'Finca Villamariana';


-- ▓▓▓ BLOQUE 6 — cultivos visibles al colaborador (según RLS) ▓▓▓
WITH cfg AS (
  SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT id::text FROM auth.users WHERE email = 'camuquisu@outlook.com'),
    true
  ) AS uid_simulado
)
SELECT
  c.id,
  c.nombre_planta,
  c.predio_id,
  public.puede_ver_predio(c.predio_id) AS puedo_ver
FROM public.cultivos c
JOIN public.predios p ON p.id = c.predio_id, cfg
WHERE p.nombre = 'Finca Villamariana';

-- FIN
