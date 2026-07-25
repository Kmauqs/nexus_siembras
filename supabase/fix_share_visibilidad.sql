-- =============================================================
-- NEXUS Siembras — Fix rápido: share compartido no visible al colaborador
-- =============================================================
-- Síntoma reportado (Fase 3e-9-3):
--   Cuenta A crea "Finca de Prueba A", invita a Cuenta B como trabajador,
--   sincroniza (OK). Cuenta B sincroniza — snackbar dice
--   "Bajados: 1 registro" — pero la pantalla Predios muestra vacío.
--
-- Causa raíz:
--   El share llega a Postgres con `aceptado_at = NULL` (el cliente Flutter
--   NO estaba subiendo ese campo) + el proyecto Postgres del usuario NO
--   tenía aplicado `schema_3e_v4.sql`. Resultado: `rol_en_predio()` sigue
--   filtrando por `aceptado_at IS NOT NULL` → NULL para B → la RLS de la
--   tabla `predios` no le devuelve el predio → Cuenta B baja solo la fila
--   del share (huérfana) y `_mergeShare` la descarta porque no encuentra
--   el predio local.
--
-- Este script es idempotente. Ejecutarlo completo en el SQL Editor.
-- =============================================================


-- 1. Trigger de auto-aceptación (idempotente)
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
CREATE TRIGGER predio_shares_autoaceptar
  BEFORE INSERT ON public.predio_shares
  FOR EACH ROW EXECUTE FUNCTION public.autoaceptar_share();


-- 2. Backfill: aceptar todos los shares existentes que no lo estén
UPDATE public.predio_shares
SET aceptado_at = COALESCE(aceptado_at, invitado_at, NOW())
WHERE aceptado_at IS NULL;


-- 3. Simplificar rol_en_predio: si hay share, ya se considera aceptado
CREATE OR REPLACE FUNCTION public.rol_en_predio(p_predio_id BIGINT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN EXISTS (
      SELECT 1 FROM public.predios
      WHERE id = p_predio_id AND owner_id = auth.uid()
    ) THEN 'propietario'
    ELSE (
      SELECT rol FROM public.predio_shares
      WHERE predio_id = p_predio_id
        AND shared_with_id = auth.uid()
      LIMIT 1
    )
  END;
$$;


-- 4. Reafirmar policy predios_select (por si acaso quedó una versión antigua)
DROP POLICY IF EXISTS predios_select ON public.predios;
CREATE POLICY predios_select ON public.predios FOR SELECT
  USING (owner_id = auth.uid() OR public.puede_ver_predio(id));


-- =============================================================
-- VERIFICACIÓN — leer los resultados antes de dar por hecho el fix
-- =============================================================

-- 5a. Estado de shares: no debe quedar ninguno pendiente
SELECT
  COUNT(*) FILTER (WHERE aceptado_at IS NOT NULL) AS aceptados,
  COUNT(*) FILTER (WHERE aceptado_at IS NULL)     AS pendientes
FROM public.predio_shares;


-- 5b. Mostrar cada predio con su(s) share(s)
SELECT
  p.id,
  p.nombre,
  (SELECT email FROM auth.users WHERE id = p.owner_id) AS propietario,
  ps.rol,
  (SELECT email FROM auth.users WHERE id = ps.shared_with_id) AS colaborador,
  ps.aceptado_at
FROM public.predios p
LEFT JOIN public.predio_shares ps ON ps.predio_id = p.id
ORDER BY p.nombre, ps.rol;


-- 5c. Simular a camuquisu@outlook.com y verificar que ve "Finca de Prueba A"
WITH cfg AS (
  SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT id::text FROM auth.users WHERE email = 'camuquisu@outlook.com'),
    true
  ) AS uid
)
SELECT
  p.id,
  p.nombre,
  public.rol_en_predio(p.id) AS rol_calculado,
  public.puede_ver_predio(p.id) AS puede_ver
FROM public.predios p, cfg
ORDER BY p.nombre;
-- Esperado: la fila de "Finca de Prueba A" con rol_calculado='trabajador'
-- y puede_ver=true.


-- 6. Restaurar sesión al terminar
SELECT set_config('request.jwt.claim.sub', '', true) AS sesion_restaurada;

-- =============================================================
-- FIN
-- =============================================================
