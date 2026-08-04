# Micro-encuestas de feedback — arquitectura y guía de implementación
**Revisión C2-9 · 2026-08-03**

Canal de retroalimentación para las pruebas por terceros: el tester
responde una micro-encuesta dentro de la app (3 toques), funciona **sin
conexión**, y los datos suben a Supabase cuando hay red. La consulta y la
notificación por correo se harán desde la **herramienta de gestión web**
(siguiente etapa) — esta guía documenta lo que queda por construir.

---

## 1. Estado actual (implementado)

```
┌──────────────┐   guardar()   ┌─────────────────────┐
│  Pantalla    │ ────────────► │ Cola local (Drift)  │  ← funciona sin red
│ /feedback    │               │ feedback_encuestas  │     y sin sesión
└──────────────┘               └──────────┬──────────┘
                                          │ enviarPendientes()
                     al guardar · al abrir la pantalla · tras cada auto-sync
                                          ▼
                            ┌──────────────────────────┐
                            │ Supabase                 │
                            │ public.feedback_encuestas│
                            └──────────────────────────┘
```

| Pieza | Ubicación |
|---|---|
| Tabla local (Drift v21) | `FeedbackEncuestas` en `lib/data/database/database.dart` |
| Servicio (cola + envío) | `lib/services/feedback_service.dart` |
| Pantalla + hoja modal | `lib/features/feedback/feedback_screen.dart` |
| Acceso | Menú lateral → «Enviar comentarios» (`/feedback`) |
| Envío oportunista | `AutoSyncService` al recuperar conectividad |
| Tablas remotas | `supabase/migrations/0016_feedback_encuestas.sql` |

**Garantías de diseño**

- El comentario **nunca se pierde**: primero se persiste local, luego se
  intenta subir. Si no hay sesión o red, queda pendiente y se reintenta.
- Reintentos hasta 8 veces automáticos; después la fila se conserva y
  puede forzarse desde el botón ☁ de la pantalla.
- Datos recogidos: calificación 1-5, aspectos (chips), comentario libre,
  versión de app, plataforma y fecha. El `user_id` lo asigna el servidor
  (`DEFAULT auth.uid()`), y al eliminar la cuenta pasa a `NULL`
  (el feedback queda anónimo, coherente con la migración 0014).
- RLS: el usuario **solo puede insertar**. No puede leer, editar ni
  borrar feedback — la gestión es exclusiva del backoffice.

**Uso desde código** (para encuestas contextuales):

```dart
// Al terminar el asistente, tras generar un reporte, etc.
await mostrarMicroEncuesta(context, tipo: 'wizard',
    titulo: '¿Qué tal el asistente?');
```

Tipos previstos: `general`, `wizard`, `reporte`, `bug`. Los chips por tipo
se definen en `_aspectos` (feedback_screen.dart).

---

## 2. Esquema remoto

### `public.feedback_encuestas`

| Columna | Tipo | Notas |
|---|---|---|
| `id` | bigserial PK | |
| `user_id` | uuid → auth.users | `ON DELETE SET NULL` (anonimiza) |
| `email_usuario` | text | copia informativa al enviar |
| `tipo` | text | `general` \| `wizard` \| `reporte` \| `bug` |
| `calificacion` | int 1-5 | nullable |
| `respuestas` | jsonb | `{"aspectos": ["...", "..."]}` |
| `comentario` | text | |
| `app_version`, `plataforma` | text | contexto técnico |
| **`atendido`** | boolean | **para la gestión web** |
| **`notas_gestion`** | text | **para la gestión web** |
| `created_at` | timestamptz | |

Índice `idx_feedback_pendientes (atendido, created_at DESC)` — pensado
para la bandeja «sin atender» del backoffice.

### `public.feedback_config` (singleton)

| Columna | Valor inicial | Para qué |
|---|---|---|
| `email_notificacion` | `email@domain.com` (placeholder) | destino de los avisos |
| `notificar_activo` | `true` | interruptor global |

Sin policies RLS: solo accesible con `service_role`. **No se commitea el
correo real** en el repositorio. Tras aplicar la migración 0016 hay que
sustituir el placeholder (SQL abajo o panel **Configuración** del
backoffice). Detalle: `nexus_backoffice/README.md` §2.4.

---

## 3. Pendiente para la herramienta de gestión web (siguiente etapa)

### 3.1 Bandeja de feedback

Consulta base (con `service_role`, nunca desde el navegador del público):

```sql
SELECT id, created_at, tipo, calificacion, comentario,
       respuestas->'aspectos' AS aspectos,
       app_version, plataforma, email_usuario, atendido, notas_gestion
FROM public.feedback_encuestas
ORDER BY atendido ASC, created_at DESC;
```

Acciones mínimas: marcar `atendido`, escribir `notas_gestion`, filtrar por
`tipo` / `plataforma` / `app_version`, y una métrica de calificación
promedio por versión (útil para ver si una release mejoró la experiencia).

### 3.2 Edición del email de notificación

Tras aplicar `0016`, sustituir el placeholder (SQL Editor o panel web):

```sql
UPDATE public.feedback_config
SET email_notificacion = 'TU_EMAIL_ADMIN@ejemplo.com',
    notificar_activo = true,
    updated_at = now()
WHERE id = 1;
```

Desde el backoffice: **Configuración** → parámetro `email_desarrollador`
(se replica automáticamente a `feedback_config.email_notificacion`).

La app móvil **no** conoce ningún correo de notificación.

### 3.3 Notificación por email

Diseño recomendado (todo del lado servidor, sin credenciales en la app):

1. **Edge Function** `notify-feedback` (Deno) en el proyecto Supabase:

```ts
// supabase/functions/notify-feedback/index.ts (a crear)
import { createClient } from 'jsr:@supabase/supabase-js@2';

Deno.serve(async (req) => {
  const { record } = await req.json();           // fila insertada
  const sb = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,  // secret, no en la app
  );
  const { data: cfg } = await sb
    .from('feedback_config').select('*').single();
  if (!cfg?.notificar_activo) return new Response('skip');

  await fetch('https://api.resend.com/emails', {   // o SMTP equivalente
    method: 'POST',
    headers: {
      Authorization: `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'NEXUS Siembras <feedback@tu-dominio>',
      to: cfg.email_notificacion,
      subject: `[NEXUS] ${record.tipo} — ${record.calificacion ?? 's/c'}★`,
      text: `${record.comentario ?? '(sin comentario)'}\n\n`
          + `Aspectos: ${JSON.stringify(record.respuestas)}\n`
          + `Versión: ${record.app_version} (${record.plataforma})\n`
          + `Usuario: ${record.email_usuario ?? 'anónimo'}`,
    }),
  });
  return new Response('ok');
});
```

2. **Database Webhook** en el dashboard: tabla `feedback_encuestas`,
   evento `INSERT` → HTTP Request a la Edge Function.

3. Secretos (`SERVICE_ROLE_KEY`, `RESEND_API_KEY`) solo como *secrets* de
   la función. **Nunca** en el `.env` de la app.

*Alternativa sin Edge Function:* revisar la bandeja periódicamente desde
la web, o un `pg_cron` con resumen diario. El webhook es preferible por
inmediatez durante las pruebas.

### 3.4 Checklist de implementación futura

- [ ] Bandeja con filtros y marcado de atendido.
- [ ] Formulario de `feedback_config` (email + interruptor).
- [ ] Edge Function `notify-feedback` + secrets.
- [ ] Database Webhook ON INSERT.
- [ ] Decidir acceso del backoffice: `service_role` en backend propio
      (recomendado) o cuenta con claim `gestor` + policy (plantilla
      comentada en la migración 0016).
- [ ] Retención: definir si el feedback se conserva indefinidamente o se
      archiva tras N meses.

---

## 4. Operación durante las pruebas por terceros

1. Aplicar `0016_feedback_encuestas.sql` en el dashboard.
2. Verificar: `SELECT email_notificacion FROM feedback_config;`
3. Pedir a los testers que usen **Menú → Enviar comentarios** cuando algo
   les llame la atención (bueno o malo).
4. Mientras no exista la web, revisar desde el SQL Editor:

```sql
SELECT created_at, tipo, calificacion, comentario, app_version, plataforma
FROM public.feedback_encuestas
WHERE NOT atendido
ORDER BY created_at DESC;
```

5. Cuando un tester reporte un fallo técnico, complementar con el log
   exportable desde **Reportes → Logs de diagnóstico → Compartir**.
