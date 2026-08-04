import { Card } from '@/components/ui';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { obtenerSesionAdmin } from '@/lib/auth';
import { FormConfig, type Parametro, type AdminFila } from './formulario';

export const dynamic = 'force-dynamic';

export default async function ConfigPage() {
  const sesion = await obtenerSesionAdmin();
  const sb = supabaseAdmin();

  const [cfg, admins, esquema] = await Promise.all([
    sb.from('app_config').select('*').order('clave'),
    sb.from('admin_allowlist').select('*').order('email'),
    sb.from('schema_meta').select('version, applied_at').maybeSingle(),
  ]);

  return (
    <div className="space-y-6">
      <Card titulo="Parámetros de la aplicación" icono={<span>⚙️</span>}>
        <p className="mb-4 text-sm text-slate-600">
          Ajustes centralizados que la app lee al sincronizar. El{' '}
          <strong>correo del desarrollador</strong> es el destino de las
          copias de feedback de los usuarios.
        </p>
        <FormConfig
          parametros={(cfg.data ?? []) as Parametro[]}
          admins={(admins.data ?? []) as AdminFila[]}
          emailSesion={sesion?.email ?? ''}
        />
      </Card>

      <Card titulo="Estado del sistema" icono={<span>🩺</span>}>
        <dl className="grid gap-3 text-sm sm:grid-cols-3">
          <div className="rounded-lg border border-slate-200 p-3">
            <dt className="text-xs uppercase text-slate-500">
              Esquema remoto
            </dt>
            <dd className="text-lg font-bold text-nexus-800">
              v{esquema.data?.version ?? '—'}
            </dd>
            <p className="text-xs text-slate-500">
              Aplicado:{' '}
              {esquema.data?.applied_at
                ? new Date(esquema.data.applied_at).toLocaleString('es-CO')
                : '—'}
            </p>
          </div>
          <div className="rounded-lg border border-slate-200 p-3">
            <dt className="text-xs uppercase text-slate-500">
              Administradores activos
            </dt>
            <dd className="text-lg font-bold text-nexus-800">
              {(admins.data ?? []).filter((a) => a.activo).length}
            </dd>
          </div>
          <div className="rounded-lg border border-slate-200 p-3">
            <dt className="text-xs uppercase text-slate-500">Sesión actual</dt>
            <dd className="truncate text-sm font-medium text-nexus-800">
              {sesion?.email}
            </dd>
          </div>
        </dl>
        <p className="mt-3 rounded-lg bg-slate-50 px-3 py-2 text-xs text-slate-600">
          Las migraciones SQL se aplican desde el SQL Editor de Supabase, en
          el orden documentado en <code>supabase/migrations/README.md</code>.
          El backoffice requiere la migración <strong>0017</strong>.
        </p>
      </Card>
    </div>
  );
}
