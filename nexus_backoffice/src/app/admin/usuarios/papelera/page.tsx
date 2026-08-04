import Link from 'next/link';
import { Card } from '@/components/ui';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { ListaPapelera, type FilaPapelera } from './lista';

export const dynamic = 'force-dynamic';

export default async function PapeleraPage() {
  const sb = supabaseAdmin();
  const { data, error } = await sb
    .from('usuarios_papelera')
    .select('user_id, email, snapshot, motivo, eliminado_at, eliminado_por')
    .order('eliminado_at', { ascending: false });

  const filas = (data ?? []) as FilaPapelera[];

  return (
    <div className="space-y-6">
      <Card
        titulo={`Papelera de usuarios (${filas.length})`}
        icono={<span>🗑️</span>}
        accion={
          <Link href="/admin/usuarios" className="btn-sutil text-xs">
            ← Volver a usuarios
          </Link>
        }
      >
        <p className="mb-3 text-sm text-slate-600">
          Cuentas suspendidas. <strong>Recuperar</strong> restablece el acceso.
          <strong> Eliminar definitivamente</strong> borra los datos privados
          (CASCADE) y conserva variedades/reportes comunitarios anónimos.
        </p>
        {error ? (
          <p className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-800">
            No se pudo leer la papelera ({error.message}). ¿Aplicaste la
            migración <code>0019_usuarios_papelera.sql</code>?
          </p>
        ) : (
          <ListaPapelera filas={filas} />
        )}
      </Card>
    </div>
  );
}
