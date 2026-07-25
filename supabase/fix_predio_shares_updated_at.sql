-- =============================================================
-- NEXUS Siembras — Fix: cambios de rol en predio_shares no se propagan
-- =============================================================
-- Síntoma reportado (Fase 3e-9-4):
--   La Cuenta A cambia el rol de un colaborador (trabajador → consultor)
--   y sincroniza. El cambio NO llega al remoto (verificado por CSV de
--   Supabase) y por tanto la Cuenta B tampoco lo ve tras sincronizar.
--
-- Causa raíz (dos partes):
--   1) La tabla `predio_shares` no tenía columna `updated_at`, por lo que
--      el pull incremental filtrando por `invitado_at` (inmutable) nunca
--      detectaba cambios de rol.
--   2) El cliente Flutter, al hacer PULL antes de PUSH, sobrescribía el
--      rol local con el rol viejo del remoto y bumpeaba `lastPushedAt`,
--      dejando el cambio de rol como "ya subido" cuando en realidad se
--      había perdido. (Este lado se arregla en el propio cliente:
--      `_saveMapping` con `bumpLastPushed:false` y `_mergeShare` con LWW.)
--
-- Este script arregla la parte Postgres: agrega la columna, un trigger
-- que la mantiene actualizada, y hace backfill de las filas existentes.
-- Ejecutar completo en el SQL Editor.
-- =============================================================


-- 1. Añadir columna updated_at (idempotente)
ALTER TABLE public.predio_shares
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();


-- 2. Backfill: inicializar updated_at = invitado_at para filas existentes
UPDATE public.predio_shares
SET updated_at = COALESCE(invitado_at, NOW())
WHERE updated_at IS NULL
   OR updated_at < COALESCE(invitado_at, updated_at);


-- 3. Trigger que actualiza updated_at en cada UPDATE (idempotente)
CREATE OR REPLACE FUNCTION public.predio_shares_touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS predio_shares_updated_at_touch ON public.predio_shares;
CREATE TRIGGER predio_shares_updated_at_touch
  BEFORE UPDATE ON public.predio_shares
  FOR EACH ROW EXECUTE FUNCTION public.predio_shares_touch_updated_at();


-- 4. Índice para acelerar el pull incremental
CREATE INDEX IF NOT EXISTS predio_shares_updated_at_idx
  ON public.predio_shares (updated_at DESC);


-- 5. Policy UPDATE (crítico) — sin esta policy, cualquier UPDATE desde
--    el cliente (incluyendo la rama DO UPDATE de un upsert) es bloqueado
--    silenciosamente por RLS. Es la causa raíz de que los cambios de rol
--    no lleguen al remoto (verificado 2026-07-19: el rol seguía en
--    'trabajador' aunque el cliente reportaba haber sincronizado).
--    Solo el owner del predio puede modificar sus shares.
DROP POLICY IF EXISTS predio_shares_owner_update ON public.predio_shares;
CREATE POLICY predio_shares_owner_update ON public.predio_shares
  FOR UPDATE
  USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());


-- =============================================================
-- VERIFICACIÓN
-- =============================================================

-- 5a. La columna existe y todas las filas tienen valor
SELECT
  COUNT(*)                                       AS total,
  COUNT(*) FILTER (WHERE updated_at IS NOT NULL) AS con_updated_at,
  MIN(updated_at)                                AS min_updated_at,
  MAX(updated_at)                                AS max_updated_at
FROM public.predio_shares;


-- 5b. El trigger está registrado
SELECT tgname, tgenabled, tgtype
FROM pg_trigger
WHERE tgname = 'predio_shares_updated_at_touch';
-- Esperado: 1 fila.


-- 5b-bis. Policies de predio_shares — deben aparecer las 4: read, ins,
--         update, del. Si falta 'update' el cambio de rol NO se propaga.
SELECT policyname, cmd
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'predio_shares'
ORDER BY policyname;
-- Esperado: predio_shares_owner_del (DELETE), predio_shares_owner_ins (INSERT),
-- predio_shares_owner_update (UPDATE), predio_shares_read (SELECT).


-- 5c. Prueba en vivo: touch a un share y verificar que updated_at avanza
--     (comentar/descomentar según necesidad — usa el share id=9 del CSV
--     compartido; ajustar si el id difiere).
-- UPDATE public.predio_shares
-- SET rol = rol  -- no-op semántico; solo para disparar el trigger
-- WHERE id = 9;
--
-- SELECT id, rol, invitado_at, updated_at FROM public.predio_shares WHERE id = 9;
-- Esperado: updated_at > invitado_at.

-- =============================================================
-- FIN
-- =============================================================
