-- =====================================================================
-- Migración 0016 — Micro-encuestas de feedback (Revisión C2-9)
-- Fecha: 2026-08-03. Idempotente. schema_meta → 13.
--
-- Arquitectura:
--   App (offline-first): las encuestas se guardan en la cola local
--   Drift `feedback_encuestas` (v21) y se suben aquí cuando hay
--   conexión + sesión.
--
--   Gestión (siguiente etapa — herramienta web):
--     · Lee esta tabla con service_role (RLS no aplica) o con una
--       cuenta de rol gestor (ver policy comentada abajo).
--     · Marca `atendido` y anota `notas_gestion`.
--     · Edita `feedback_config.email_notificacion` (destino de los
--       avisos por correo).
--
--   Notificación por email (siguiente etapa — documentada en
--   docs/FEEDBACK_ENCUESTAS.md): Database Webhook ON INSERT →
--   Edge Function `notify-feedback` → lee feedback_config → envía el
--   correo (Resend/SMTP). El cliente móvil NO envía correos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tabla principal de feedback
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.feedback_encuestas (
  id            bigserial PRIMARY KEY,
  -- Quién: se conserva el vínculo mientras exista la cuenta; al
  -- eliminarla, el feedback queda anónimo (SET NULL — coherente con 0014).
  user_id       uuid DEFAULT auth.uid()
                REFERENCES auth.users(id) ON DELETE SET NULL,
  email_usuario text,             -- copia informativa al momento de enviar
  -- Qué:
  tipo          text NOT NULL DEFAULT 'general', -- general|wizard|reporte|bug…
  calificacion  int CHECK (calificacion BETWEEN 1 AND 5),
  respuestas    jsonb NOT NULL DEFAULT '{}'::jsonb,
  comentario    text,
  -- Contexto técnico:
  app_version   text,
  plataforma    text,             -- android|windows|linux|macos|web
  -- Gestión (para la herramienta web):
  atendido      boolean NOT NULL DEFAULT false,
  notas_gestion text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_feedback_pendientes
  ON public.feedback_encuestas (atendido, created_at DESC);

ALTER TABLE public.feedback_encuestas ENABLE ROW LEVEL SECURITY;

-- Los usuarios solo pueden INSERTAR su propio feedback. No pueden leer,
-- editar ni borrar (la gestión es exclusiva del backoffice).
DROP POLICY IF EXISTS feedback_insert ON public.feedback_encuestas;
CREATE POLICY feedback_insert ON public.feedback_encuestas
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL AND user_id = auth.uid());

-- (Siguiente etapa) Si la herramienta web usará una cuenta gestora en vez
-- de service_role, activar una policy como esta con su UUID o claim:
-- CREATE POLICY feedback_gestion ON public.feedback_encuestas
--   FOR ALL USING (auth.jwt() ->> 'role' = 'gestor');

-- ---------------------------------------------------------------------
-- 2. Configuración de notificaciones (editable desde la gestión web)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.feedback_config (
  id                  int PRIMARY KEY DEFAULT 1 CHECK (id = 1), -- singleton
  email_notificacion  text NOT NULL,
  notificar_activo    boolean NOT NULL DEFAULT true,
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- Placeholder deliberado (no commitear el correo real). Sustituir tras
-- aplicar — ver nexus_backoffice/README.md §2.4 y docs/FEEDBACK_ENCUESTAS.md.
INSERT INTO public.feedback_config (id, email_notificacion)
VALUES (1, 'email@domain.com')
ON CONFLICT (id) DO NOTHING;  -- no pisar si ya fue editado

ALTER TABLE public.feedback_config ENABLE ROW LEVEL SECURITY;
-- Sin policies: solo service_role (dashboard / gestión web) la lee/edita.

COMMENT ON TABLE public.feedback_encuestas IS
  'Micro-encuestas enviadas desde la app (cola offline local → aquí). '
  'Gestión: herramienta web (siguiente etapa) via service_role.';
COMMENT ON TABLE public.feedback_config IS
  'Configuración de notificaciones de feedback. email_notificacion es el '
  'destino de los avisos por correo (Edge Function notify-feedback, '
  'siguiente etapa). Editable desde la herramienta de gestión web.';

INSERT INTO public.schema_meta (id, version)
VALUES (1, 13)
ON CONFLICT (id) DO UPDATE
SET version = GREATEST(public.schema_meta.version, 13),
    applied_at = NOW();

-- Verificación:
-- SELECT version FROM public.schema_meta;                    -- → 13
-- SELECT email_notificacion FROM public.feedback_config;     -- → email
