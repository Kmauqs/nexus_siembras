# NEXUS Siembras — Backoffice y sitio público

Sitio web público con las estadísticas del proyecto + panel de
administración de la app. Next.js 14 (App Router) desplegado en Netlify,
conectado al mismo proyecto Supabase que la app móvil/escritorio.

---

## 1. Puesta en marcha

### Requisitos
- Node.js 20+
- Proyecto Supabase de NEXUS Siembras con las migraciones aplicadas
  **hasta la 0020** (panel); **0021** solo si usás sync de comprobantes de compras.

### Pasos

```bash
cd nexus_backoffice
npm install
cp .env.example .env.local     # OBLIGATORIO: Next no lee .env.example
# Editar .env.local con URL, anon/publishable key, service_role y ADMIN_EMAIL_BOOTSTRAP
npm run dev                    # http://localhost:3000  (reiniciar tras crear/editar .env.local)
```

`npm warn deprecated` y el aviso de `unrs-resolver` (script postinstall
bloqueado) son ruido habitual: el install ya quedó bien. No uses
`npm audit fix --force`. Si querés aprobar el postinstall nativo:

```bash
npm install-scripts approve unrs-resolver
```

### Variables de entorno

| Variable | Dónde se usa | Notas |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | cliente + servidor | URL del proyecto |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | cliente + servidor | publishable key |
| `SUPABASE_SERVICE_ROLE_KEY` | **solo servidor** | salta RLS — nunca exponer |
| `ADMIN_EMAIL_BOOTSTRAP` | servidor | acceso de respaldo; ver §2.4 |

**Regla de oro:** la `SUPABASE_SERVICE_ROLE_KEY` jamás lleva el prefijo
`NEXT_PUBLIC_`. Se consume solo desde `src/lib/supabase/admin.ts`, que
importa `server-only`: si alguien la importara en un componente cliente,
**el build falla** en vez de filtrar la clave.

**Correos reales:** no se versionan en Git. Las migraciones y
`.env.example` usan el placeholder `email@domain.com`. Debes sustituirlo
a mano en cada entorno (detalle en §2.4).

---

## 2. Configuración de Supabase (una sola vez)

### 2.1 Migración
Aplicar en el SQL Editor, en orden: `0016` … `0020` (feedback,
`app_config`, allowlist, patrimonio, papelera y RLS de escritura admin).
La `0021` (soportes de compras en Storage) es de la app móvil, no del panel.

### 2.2 Magic link (plan gratuito de Supabase)
El login usa el **magic link por defecto** de Supabase (plantilla
*Magic Link* sin personalizar). No hace falta editar el HTML del correo
ni usar el código de 6 dígitos.

En **Authentication → URL Configuration** agregá:

| Campo | Valor (dev) | Valor (prod) |
|---|---|---|
| *Site URL* | `http://localhost:3000` | URL de Netlify |
| *Redirect URLs* | `http://localhost:3000/auth/callback` | `https://TU-SITIO.netlify.app/auth/callback` |

Podés dejar ambas redirect URLs a la vez. El enlace del correo lleva a
`/auth/callback`, que crea la sesión y comprueba la allowlist.

### 2.3 Administradores
La tabla `admin_allowlist` define quién entra al panel. El correo debe
existir como usuario en Auth de la app (el login **no** crea cuentas).
Tras el primer acceso, el resto de admins se gestiona desde
**Configuración** del panel.

### 2.4 Email del administrador (configuración manual obligatoria)

El repositorio **no** contiene el correo real del administrador. Tras
aplicar las migraciones (o al desplegar), introduce tu email en estos
sitios:

| # | Dónde | Qué poner | Cómo |
|---|---|---|---|
| 1 | **Supabase → SQL Editor** | Email real del admin | Ejecutar el bloque SQL de abajo (sustituye `TU_EMAIL_ADMIN@ejemplo.com`) |
| 2 | **`.env.local`** (dev) / **Netlify → Environment variables** (prod) | Misma dirección en `ADMIN_EMAIL_BOOTSTRAP` | Copia desde `.env.example` y reemplaza el placeholder |
| 3 | **Panel → Configuración** (después del primer login) | `email_desarrollador`, `contacto_soporte` | Edición en UI; al guardar `email_desarrollador` se replica a `feedback_config` |

Bloque SQL (una sola vez por proyecto; idempotente si ya está bien):

```sql
-- Sustituir TU_EMAIL_ADMIN@ejemplo.com en las tres sentencias.
UPDATE public.app_config
SET valor = 'TU_EMAIL_ADMIN@ejemplo.com', updated_at = now()
WHERE clave IN ('email_desarrollador', 'contacto_soporte');

UPDATE public.feedback_config
SET email_notificacion = 'TU_EMAIL_ADMIN@ejemplo.com', updated_at = now()
WHERE id = 1;

INSERT INTO public.admin_allowlist (email, nombre, activo)
VALUES ('TU_EMAIL_ADMIN@ejemplo.com', 'Administrador', true)
ON CONFLICT (email) DO UPDATE
SET activo = true, nombre = COALESCE(EXCLUDED.nombre, admin_allowlist.nombre);
```

Comprobación rápida:

```sql
SELECT clave, valor FROM public.app_config
WHERE clave IN ('email_desarrollador', 'contacto_soporte');
SELECT email_notificacion FROM public.feedback_config WHERE id = 1;
SELECT email, activo FROM public.admin_allowlist;
```

Si la base ya tenía valores reales (aplicada antes de usar placeholders),
no hace falta re-ejecutar las migraciones: solo verifica que esos tres
lugares apunten al correo correcto y que Netlify tenga
`ADMIN_EMAIL_BOOTSTRAP`.

---

## 3. Despliegue en Netlify

1. Subir el repo a GitHub y en Netlify: *Add new site → Import project*.
2. **Base directory:** `nexus_backoffice` (si el repo incluye la app
   Flutter). Build y publish los toma de `netlify.toml`.
3. *Site settings → Environment variables:* cargar las 4 variables.
4. Deploy. El plugin `@netlify/plugin-nextjs` convierte las rutas y
   Server Actions en funciones — necesario para que la lógica
   administrativa corra del lado servidor.

```bash
# Alternativa por CLI
npm i -g netlify-cli
netlify deploy --build --prod
```

---

## 4. Mapa de la aplicación

| Ruta | Acceso | Contenido |
|---|---|---|
| `/` | público | Card de la app + GitHub, KPIs, usuarios por país (pie), tabla de estadísticas, mapa de calor de patologías |
| `/login` | público | Solicitud de magic link al correo autorizado |
| `/auth/callback` | público | Intercambio del código del enlace por sesión |
| `/admin` | admin | Series de uso 30 días, usuarios por país, feedback con errores, últimos comentarios |
| `/admin/usuarios` | admin | Listado con país/ciudad, predios, lotes, cultivos, feedback; soft-delete a papelera |
| `/admin/usuarios/papelera` | admin | Recuperar cuentas suspendidas o eliminarlas definitivamente |
| `/admin/datos` | admin | Edición de `variedades_comunitarias`, `patologias_reportadas`, `patologia_tratamientos` |
| `/admin/feedback` | admin | Bandeja con filtros, notas, marcado masivo, respuesta por email, export CSV |
| `/admin/config` | admin | Parámetros de la app (incluye email del desarrollador) y gestión de administradores |

### Seguridad en capas

1. **Middleware** — bloquea `/admin/*` sin sesión.
2. **Layout del panel** — `requerirAdmin()` / `es_admin()` (JWT).
3. **Cada Server Action** — vuelve a verificar antes de escribir.
4. **RLS + `es_admin()`** — escrituras de datos, feedback, config,
   allowlist y papelera van con el JWT del admin (migración **0020**).
   `service_role` solo para Auth Admin API (ban/listUsers) y agregados
   públicos de la landing. El borrado definitivo usa la RPC
   `admin_eliminar_usuario` (re-chequea `es_admin` en Postgres).

El soft-delete de usuario exige escribir el correo exacto y no permite
auto-borrarse. El borrado definitivo (desde la papelera) tiene la misma
fricción.

### Avisos por email de feedback

Código en `../supabase/functions/notify-feedback/`. Tras configurar el
email real (§2.4), desplegar la función y crear el webhook INSERT
(instrucciones en el README de esa carpeta).

---

## 5. Decisiones de diseño

- **Identidad visual:** paleta tomada de la app Flutter (verde `#1B7A3E`
  primario, `#0F5132` para encabezados), misma marca 🌱 y tipografía de
  sistema. Definida en `tailwind.config.ts` y `globals.css`.
- **Datos agregados en el servidor:** la landing pública no consulta
  tablas directamente; usa funciones `stats_*` que devuelven solo
  agregados anonimizados.
- **Papelera de usuarios (migración 0019):** «A papelera» suspende la
  cuenta (ban Auth + fila en `usuarios_papelera`) sin borrar datos.
  Desde `/admin/usuarios/papelera` se puede recuperar o eliminar
  definitivamente (CASCADE privado + patrimonio comunitario anónimo).
  Requiere **0015** y **0019** aplicadas.
- **Patrimonio comunitario (migración 0018):** las **variedades** y los
  **reportes de patologías** NO se borran nunca — ni al eliminar la
  cuenta del autor ni desde el panel. Se anonimizan (`created_by` /
  `owner_id` → NULL) y siguen sirviendo a la comunidad. A nivel de base
  de datos no existe policy de DELETE sobre `patologias_reportadas`: el
  borrado es imposible incluso por error. Para contenido inadecuado el
  panel ofrece **Ocultar** (soft-delete reversible).
- **Estado de los focos:** un reporte pasa a `desatendida` (gris, y deja
  de teñir el mapa de calor) tras `patologia_dias_desatendida` días (60
  por defecto) sin actividad. Se **reactiva** solo si llega un reporte
  nuevo dentro de `patologia_radio_km` (5 km) — un trigger propaga la
  actividad a los vecinos — o si el administrador pulsa **Atender**.
  Ambos parámetros se editan desde *Configuración*.

---

## 6. Pendiente / siguiente etapa

- [ ] Deploy operativo de `notify-feedback` + webhook INSERT (código listo).
- [ ] Paginación real en usuarios y datos si superan ~1000 filas
      (hoy hay límite de 500-1000 por consulta).
- [ ] Métricas de retención y embudo de onboarding.
- [ ] Vista de detalle por usuario (sus predios y cultivos).
