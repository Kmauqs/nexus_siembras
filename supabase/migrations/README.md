# Migraciones canónicas — NEXUS Siembras (auditoría S6)

El esquema remoto estaba fragmentado en 7+ archivos aplicados a mano, y el
cliente compensaba con ramas "por si el servidor no tiene X aplicado".
Desde la auditoría 2026-07-19 este directorio es la **fuente canónica**:

## Orden de aplicación (proyecto Supabase nuevo)

Ejecutar en el SQL Editor, en este orden exacto:

| # | Archivo (en `supabase/`) | Contenido |
|---|--------------------------|-----------|
| 1 | `schema.sql` | Tablas base + RLS por owner |
| 2 | `schema_3e.sql` | Shares, patologías reportadas, bucket storage |
| 3 | `schema_3e_v2.sql` | RLS v2 por tabla |
| 4 | `schema_3e_v3.sql` | Ajustes shares |
| 5 | `schema_3e_v4.sql` | Trigger autoaceptar_share |
| 6 | `schema_3g.sql` | Autor en tareas |
| 7 | `fix_predio_shares_updated_at.sql` | Columna updated_at en shares |
| 8 | `migrations/0007_schema_meta_y_triggers_updated_at.sql` | **schema_meta + triggers updated_at (auditoría)** |
| 9 | `migrations/0008_banco_variedades.sql` | **Banco comunitario de variedades** (tabla + RPC `contribuir_variedad`) |
| 10 | `migrations/0009_rls_reportes_privacidad.sql` | **Privacidad reportes**: tabla base solo del dueño; lectura comunitaria por la vista anonimizada |
| 11 | `migrations/0010_cultivos_tipo_ciclo.sql` | Tipo de ciclo y periodos en `cultivos` (ciclo único / perenne) |
| 12 | `migrations/0011_compras_created_by.sql` | Autor (`created_by_user_id`) en compras para co-propietarios |
| 13 | `migrations/0012_proveedores_compartidos.sql` | **Proveedores compartidos**: lectura para colaboradores propietario/trabajador del predio |

Los archivos `fix_*.sql` restantes y `cleanup_duplicados.sql` son remedios
puntuales históricos: solo ejecutar si se reproduce el problema que
describen en su cabecera.

## Regla a partir de ahora

1. Todo cambio de esquema = nuevo archivo `migrations/NNNN_descripcion.sql`,
   idempotente, que **incremente `schema_meta.version`**.
2. Subir `SyncService.schemaRemotoRequerido` en el cliente cuando el
   cliente dependa de esa migración.
3. El cliente bloquea el sync si `schema_meta.version` es menor que lo
   requerido (mensaje claro en la UI de sync). Si la tabla no existe aún,
   solo advierte en logs (transición).

Recomendado: gestionar esto con la CLI (`supabase migration new ...`,
`supabase db push`) cuando el flujo de trabajo lo permita.

## Verificación rápida del estado del servidor

```sql
SELECT version, applied_at FROM public.schema_meta;
SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public';
SELECT tgname, tgrelid::regclass FROM pg_trigger WHERE tgname = 'trg_cap_updated_at';
```
