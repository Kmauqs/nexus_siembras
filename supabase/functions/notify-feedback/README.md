# notify-feedback

Envía un aviso por email cuando se inserta una fila en
`public.feedback_encuestas`. El destinatario se lee de
`feedback_config.email_notificacion` (nunca hardcodeado en el código).

## Prerrequisitos

1. Migraciones **0016** y **0020** aplicadas.
2. Email real configurado (no el placeholder `email@domain.com`) — ver
   `nexus_backoffice/README.md` §2.4.
3. Cuenta [Resend](https://resend.com) (u otro proveedor; este código usa
   Resend) y dominio/remitente verificado.

## Despliegue

```bash
# Desde la raíz del repo (o con la CLI apuntando al proyecto)
supabase functions deploy notify-feedback --no-verify-jwt

supabase secrets set \
  RESEND_API_KEY=re_xxxxxxxx \
  FEEDBACK_FROM="NEXUS Siembras <noreply@tu-dominio.com>"
```

`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` los inyecta la plataforma.

## Webhook

Dashboard → **Database** → **Webhooks** → Create:

| Campo | Valor |
|---|---|
| Table | `feedback_encuestas` |
| Events | `INSERT` |
| Type | HTTP Request |
| Method | POST |
| URL | `https://<ref>.supabase.co/functions/v1/notify-feedback` |
| Headers | `Authorization: Bearer <ANON_o_SERVICE_ROLE_KEY>` |

## Comportamiento

- `notificar_activo = false` → no envía (`skipped: disabled`).
- Destino vacío o `email@domain.com` → no envía (`skipped: placeholder_email`).
- Éxito → `{ ok: true }` y correo al admin configurado.
