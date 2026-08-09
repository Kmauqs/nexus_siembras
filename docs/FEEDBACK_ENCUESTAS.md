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

**Implementado** en `supabase/functions/notify-feedback/` (ver su README).

- Destino: `feedback_config.email_notificacion` (configurable en el panel;
  **nunca** hardcodeado en el repo).
- Si el destino es el placeholder `email@domain.com`, **no envía**
  (evita fugas). Sustituir según `nexus_backoffice/README.md` §2.4.
- Secretos: `RESEND_API_KEY`, `FEEDBACK_FROM` vía `supabase secrets set`.
- Pendiente operativo: deploy de la función + Database Webhook ON INSERT
  en `feedback_encuestas`.

### 3.4 Checklist

- [x] Bandeja con filtros y marcado de atendido (backoffice).
- [x] Formulario de email / interruptor (`app_config` → `feedback_config`).
- [x] Edge Function `notify-feedback` (código + README).
- [ ] Deploy de la función + secrets Resend.
- [ ] Database Webhook ON INSERT.
- [x] Escrituras del panel con JWT + `es_admin()` (migración 0020).
- [ ] Retención: archivar feedback tras N meses (opcional).

---

## 4. Operación durante las pruebas por terceros

1. Aplicar `0016_feedback_encuestas.sql` en el dashboard.
2. Verificar: `SELECT email_notificacion FROM feedback_config;`
3. Entregar `docs/GUIA_TESTER.md` (C2-9b) junto al build y pedir que usen
   **Menú → Enviar comentarios** cuando algo
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
