import Link from 'next/link';
import { Card } from '@/components/ui';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { TablaUsuarios, type UsuarioFila } from './tabla';

export const dynamic = 'force-dynamic';

export default async function UsuariosPage() {
  const sb = supabaseAdmin();

  const [usersRes, predios, lotes, cultivos, feedbacks, papelera] =
    await Promise.all([
      sb.auth.admin.listUsers({ page: 1, perPage: 1000 }),
      sb
        .from('predios')
        .select(
          'owner_id, pais_iso2, region_nombre, municipio_nombre, created_at'
        )
        .is('deleted_at', null),
      sb.from('lotes').select('owner_id').is('deleted_at', null),
      sb.from('cultivos').select('owner_id').is('deleted_at', null),
      sb.from('feedback_encuestas').select('user_id, atendido'),
      sb.from('usuarios_papelera').select('user_id'),
    ]);

  const enPapelera = new Set(
    (papelera.data ?? []).map((r) => r.user_id as string)
  );

  const cuenta = <T extends { owner_id?: string | null }>(
    rows: T[] | null,
    id: string
  ) => (rows ?? []).filter((r) => r.owner_id === id).length;

  const filas: UsuarioFila[] = (usersRes.data?.users ?? [])
    .filter((u) => !enPapelera.has(u.id))
    .map((u) => {
      const suyos = (predios.data ?? []).filter((p) => p.owner_id === u.id);
      const primero = suyos.sort(
        (a, b) =>
          new Date(a.created_at ?? 0).getTime() -
          new Date(b.created_at ?? 0).getTime()
      )[0];
      const fbs = (feedbacks.data ?? []).filter((f) => f.user_id === u.id);
      return {
        user_id: u.id,
        email: u.email ?? '(sin email)',
        created_at: u.created_at,
        last_sign_in_at: u.last_sign_in_at ?? null,
        pais: (primero?.pais_iso2 as string) ?? null,
        region: (primero?.region_nombre as string) ?? null,
        ciudad: (primero?.municipio_nombre as string) ?? null,
        predios: suyos.length,
        lotes: cuenta(lotes.data, u.id),
        cultivos: cuenta(cultivos.data, u.id),
        feedbacks: fbs.length,
        feedbacks_pendientes: fbs.filter((f) => !f.atendido).length,
      };
    });

  const nPapelera = enPapelera.size;

  return (
    <div className="space-y-6">
      <Card
        titulo={`Usuarios activos (${filas.length})`}
        icono={<span>👥</span>}
        accion={
          <Link href="/admin/usuarios/papelera" className="btn-secundario text-xs">
            Papelera{nPapelera > 0 ? ` (${nPapelera})` : ''}
          </Link>
        }
      >
        <p className="mb-3 text-sm text-slate-600">
          Ubicación tomada del primer predio de cada usuario. Eliminar mueve
          la cuenta a la <strong>papelera</strong> (suspensión reversible). El
          borrado definitivo solo se hace desde allí.
        </p>
        <TablaUsuarios filas={filas} />
      </Card>
    </div>
  );
}
