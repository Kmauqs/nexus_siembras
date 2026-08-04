-- =============================================================
-- NEXUS Siembras — Verificación end-to-end (Fase 3e-9)
-- =============================================================
-- Ejecutar como service_role en el SQL Editor de Supabase.
-- Cada bloque es independiente: seleccionar el bloque completo entre
-- los "-- ▓▓▓ BLOQUE N ▓▓▓" y correrlo por separado (Ctrl+Enter).
--
-- Variables: sustituir a mano antes de ejecutar (no versionar correos reales).
--   Email propietario:  'EMAIL_PROPIETARIO@ejemplo.com'  (cuenta A)
--   Email colaborador:  'EMAIL_COLABORADOR@ejemplo.com'  (cuenta B)
--   Predio de prueba:   'Finca de Prueba A' (o el que uses)
-- =============================================================


-- ▓▓▓ BLOQUE 1 — Usuarios y UUIDs ▓▓▓
-- Confirma que ambas cuentas existen en auth.users.
SELECT id, email, created_at
FROM auth.users
WHERE email IN ('EMAIL_PROPIETARIO@ejemplo.com', 'EMAIL_COLABORADOR@ejemplo.com')
ORDER BY email;


-- ▓▓▓ BLOQUE 2 — Predios visibles y ownership ▓▓▓
-- Para cada predio, muestra el owner + colaboradores + estado del share.
SELECT
  p.id,
  p.nombre,
  (SELECT email FROM auth.users WHERE id = p.owner_id) AS propietario,
  ps.rol,
  (SELECT email FROM auth.users WHERE id = ps.shared_with_id) AS colaborador,
  ps.aceptado_at,
  CASE
    WHEN ps.aceptado_at IS NULL THEN '❌ NO ACEPTADO'
    ELSE '✓ Aceptado'
  END AS estado_share
FROM public.predios p
LEFT JOIN public.predio_shares ps ON ps.predio_id = p.id
ORDER BY p.nombre, ps.rol;


-- ▓▓▓ BLOQUE 3 — Verificar helpers de RLS ▓▓▓
-- Simula el rol de cada usuario sobre un predio y verifica la función
-- rol_en_predio() — debe retornar el rol correcto.
WITH cfg_a AS (
  SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT id::text FROM auth.users WHERE email = 'EMAIL_PROPIETARIO@ejemplo.com'),
    true
  ) AS uid
)
SELECT
  cfg_a.uid AS simulando_A,
  p.id AS predio_id,
  p.nombre,
  public.rol_en_predio(p.id) AS rol_A,
  public.puede_ver_predio(p.id) AS puede_ver_A,
  public.puede_editar_predio(p.id) AS puede_editar_A,
  public.es_propietario_predio(p.id) AS es_prop_A
FROM public.predios p, cfg_a;

-- Reset y simula colaborador
WITH cfg_b AS (
  SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT id::text FROM auth.users WHERE email = 'EMAIL_COLABORADOR@ejemplo.com'),
    true
  ) AS uid
)
SELECT
  cfg_b.uid AS simulando_B,
  p.id AS predio_id,
  p.nombre,
  public.rol_en_predio(p.id) AS rol_B,
  public.puede_ver_predio(p.id) AS puede_ver_B,
  public.puede_editar_predio(p.id) AS puede_editar_B,
  public.es_propietario_predio(p.id) AS es_prop_B
FROM public.predios p, cfg_b;


-- ▓▓▓ BLOQUE 4 — Sync efectivo: cultivos e inventario ▓▓▓
-- Cuenta cuántos cultivos/inventarios hay por predio y por owner.
-- Sin duplicados (mismo owner+id no debe repetirse).
SELECT
  p.nombre AS predio,
  (SELECT email FROM auth.users WHERE id = c.owner_id) AS owner_del_registro,
  COUNT(*) AS cultivos
FROM public.cultivos c
JOIN public.predios p ON p.id = c.predio_id
WHERE c.deleted_at IS NULL
GROUP BY p.nombre, c.owner_id
ORDER BY p.nombre;

SELECT
  p.nombre AS predio,
  (SELECT email FROM auth.users WHERE id = i.owner_id) AS owner_del_registro,
  COUNT(*) AS inventarios,
  SUM(i.cantidad_base) AS total_cantidad
FROM public.inventarios i
JOIN public.predios p ON p.id = i.predio_id
WHERE i.deleted_at IS NULL
GROUP BY p.nombre, i.owner_id
ORDER BY p.nombre;


-- ▓▓▓ BLOQUE 5 — Trazabilidad HH por usuario (Fase 3g) ▓▓▓
-- Verifica que las tareas registradas tienen created_by_user_id populado
-- correctamente por el trigger `tareas_completadas_autor`.
SELECT
  (SELECT email FROM auth.users WHERE id = t.created_by_user_id) AS autor,
  COUNT(*) AS tareas,
  SUM(t.hh) AS hh_totales
FROM public.tareas_completadas t
JOIN public.cultivos c ON c.id = t.cultivo_id
WHERE c.deleted_at IS NULL
GROUP BY t.created_by_user_id
ORDER BY hh_totales DESC NULLS LAST;

-- Alertas: tareas sin autor (legacy) — debe ir bajando con el uso.
SELECT
  COUNT(*) FILTER (WHERE created_by_user_id IS NOT NULL) AS con_autor,
  COUNT(*) FILTER (WHERE created_by_user_id IS NULL)     AS sin_autor_legacy
FROM public.tareas_completadas;


-- ▓▓▓ BLOQUE 6 — Patologías reportadas (Fase 3e-5) ▓▓▓
-- Reportes comunitarios visibles en la tabla pública.
SELECT
  pr.id,
  pr.patologia_nombre,
  pr.planta_nombre,
  pr.severidad,
  pr.pais_iso2,
  pr.fecha_deteccion,
  ROUND(pr.lat::numeric, 4) AS lat,
  ROUND(pr.lng::numeric, 4) AS lng,
  CASE
    WHEN pr.foto_remote_url IS NOT NULL THEN '📸 con foto'
    WHEN pr.foto_local_path IS NOT NULL THEN '⌛ foto pendiente sync'
    ELSE '—'
  END AS estado_foto
FROM public.patologias_reportadas pr
WHERE pr.deleted_at IS NULL
ORDER BY pr.fecha_deteccion DESC;

-- Cuenta por país (para heatmap comunitario)
SELECT
  COALESCE(pais_iso2, 'sin_pais') AS pais,
  COUNT(*) AS reportes,
  COUNT(DISTINCT patologia_nombre) AS patologias_distintas
FROM public.patologias_reportadas
WHERE deleted_at IS NULL
GROUP BY pais_iso2
ORDER BY reportes DESC;


-- ▓▓▓ BLOQUE 7 — Detección de duplicados ▓▓▓
-- Alertas si un mismo owner tiene más de una fila con el mismo cliente_id
-- (indicaría fallo del mapping local↔remoto).
SELECT
  'cultivos' AS tabla, owner_id, cliente_id, COUNT(*) AS duplicados
FROM public.cultivos
WHERE cliente_id IS NOT NULL AND deleted_at IS NULL
GROUP BY owner_id, cliente_id
HAVING COUNT(*) > 1

UNION ALL

SELECT
  'inventarios', owner_id, cliente_id, COUNT(*)
FROM public.inventarios
WHERE cliente_id IS NOT NULL AND deleted_at IS NULL
GROUP BY owner_id, cliente_id
HAVING COUNT(*) > 1

UNION ALL

SELECT
  'tareas_completadas', created_by_user_id, cliente_id, COUNT(*)
FROM public.tareas_completadas
WHERE cliente_id IS NOT NULL
GROUP BY created_by_user_id, cliente_id
HAVING COUNT(*) > 1

ORDER BY 4 DESC;
-- Esperado: 0 filas. Cualquier resultado indica un bug de deduplicación.


-- ▓▓▓ BLOQUE 8 — Salud general del sistema ▓▓▓
-- Snapshot de todas las tablas sincronizables.
SELECT 'predios'              AS tabla, COUNT(*) FROM public.predios WHERE deleted_at IS NULL
UNION ALL SELECT 'lotes',              COUNT(*) FROM public.lotes WHERE deleted_at IS NULL
UNION ALL SELECT 'cultivos',           COUNT(*) FROM public.cultivos WHERE deleted_at IS NULL
UNION ALL SELECT 'proveedores',        COUNT(*) FROM public.proveedores WHERE deleted_at IS NULL
UNION ALL SELECT 'inventarios',        COUNT(*) FROM public.inventarios WHERE deleted_at IS NULL
UNION ALL SELECT 'compras',            COUNT(*) FROM public.compras WHERE deleted_at IS NULL
UNION ALL SELECT 'tareas_completadas', COUNT(*) FROM public.tareas_completadas
UNION ALL SELECT 'eventos_cultivo',    COUNT(*) FROM public.eventos_cultivo WHERE deleted_at IS NULL
UNION ALL SELECT 'analisis_suelo',     COUNT(*) FROM public.analisis_suelo WHERE deleted_at IS NULL
UNION ALL SELECT 'condiciones_predio', COUNT(*) FROM public.condiciones_predio WHERE deleted_at IS NULL
UNION ALL SELECT 'predio_shares',      COUNT(*) FROM public.predio_shares
UNION ALL SELECT 'patologias_reportadas', COUNT(*) FROM public.patologias_reportadas WHERE deleted_at IS NULL
ORDER BY tabla;


-- ▓▓▓ BLOQUE 9 — Restaurar sesión ▓▓▓
-- Después de los bloques 3, restaurar el contexto normal.
SELECT set_config('request.jwt.claim.sub', '', true) AS sesion_restaurada;

-- =============================================================
-- FIN
-- =============================================================
