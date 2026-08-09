// Edge Function: aviso por email al insertar feedback_encuestas.
//
// Despliegue (manual, una vez):
//   supabase functions deploy notify-feedback --no-verify-jwt
//   supabase secrets set RESEND_API_KEY=re_xxx FEEDBACK_FROM="NEXUS Siembras <onboarding@resend.dev>"
//
// Webhook en Dashboard → Database → Webhooks:
//   tabla feedback_encuestas, evento INSERT →
//   URL https://<proyecto>.supabase.co/functions/v1/notify-feedback
//   header Authorization: Bearer <SUPABASE_ANON_KEY o service role>
//
// El destino del correo se lee de feedback_config (configurable en el
// panel). Nunca hardcodear el email del admin aquí.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const PLACEHOLDER = 'email@domain.com';

type FeedbackRow = {
  id?: number;
  tipo?: string;
  calificacion?: number | null;
  comentario?: string | null;
  respuestas?: unknown;
  app_version?: string | null;
  plataforma?: string | null;
  email_usuario?: string | null;
};

type WebhookBody = {
  type?: string;
  table?: string;
  record?: FeedbackRow;
  // Formato alternativo de algunos webhooks
  body?: { record?: FeedbackRow };
};

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  let payload: WebhookBody;
  try {
    payload = await req.json();
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }

  const record = payload.record ?? payload.body?.record;
  if (!record) {
    return new Response('Missing record', { status: 400 });
  }

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) {
    console.error('Faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY');
    return new Response('Server misconfigured', { status: 500 });
  }

  const sb = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: cfg, error: errCfg } = await sb
    .from('feedback_config')
    .select('email_notificacion, notificar_activo')
    .eq('id', 1)
    .maybeSingle();

  if (errCfg) {
    console.error('feedback_config:', errCfg.message);
    return new Response('Config error', { status: 500 });
  }
  if (!cfg?.notificar_activo) {
    return new Response(JSON.stringify({ ok: true, skipped: 'disabled' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const destino = (cfg.email_notificacion ?? '').trim().toLowerCase();
  if (!destino || destino === PLACEHOLDER || !destino.includes('@')) {
    // Placeholder del repo o sin configurar: no enviar (evita fugas / spam).
    console.warn(
      'notify-feedback: email_notificacion no configurado (placeholder). ' +
        'Sustituir según nexus_backoffice/README.md §2.4',
    );
    return new Response(
      JSON.stringify({ ok: true, skipped: 'placeholder_email' }),
      { headers: { 'Content-Type': 'application/json' } },
    );
  }

  const resendKey = Deno.env.get('RESEND_API_KEY');
  if (!resendKey) {
    console.error('Falta RESEND_API_KEY en secrets de la función');
    return new Response('Missing RESEND_API_KEY', { status: 500 });
  }

  const from =
    Deno.env.get('FEEDBACK_FROM') ??
    'NEXUS Siembras <onboarding@resend.dev>';

  const estrellas = record.calificacion != null
    ? `${record.calificacion}★`
    : 's/c';
  const subject = `[NEXUS] ${record.tipo ?? 'feedback'} — ${estrellas}`;
  const text =
    `${record.comentario ?? '(sin comentario)'}\n\n` +
    `Aspectos: ${JSON.stringify(record.respuestas ?? {})}\n` +
    `Versión: ${record.app_version ?? '—'} (${record.plataforma ?? '—'})\n` +
    `Usuario: ${record.email_usuario ?? 'anónimo'}\n` +
    `Id: ${record.id ?? '—'}`;

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from,
      to: [destino],
      subject,
      text,
    }),
  });

  if (!res.ok) {
    const detail = await res.text();
    console.error('Resend error:', res.status, detail);
    return new Response(`Email provider error: ${res.status}`, { status: 502 });
  }

  return new Response(JSON.stringify({ ok: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
