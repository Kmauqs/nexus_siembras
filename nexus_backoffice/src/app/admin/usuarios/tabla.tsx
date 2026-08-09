'use client';

import Link from 'next/link';
import { useMemo, useState, useTransition } from 'react';
import { Chip } from '@/components/ui';
import { banderaPais, fecha, haceCuanto, nombrePais } from '@/lib/formato';
import { moverAPapelera } from './acciones';

export type UsuarioFila = {
  user_id: string;
  email: string;
  created_at: string;
  last_sign_in_at: string | null;
  pais: string | null;
  region: string | null;
  ciudad: string | null;
  predios: number;
  lotes: number;
  cultivos: number;
  feedbacks: number;
  feedbacks_pendientes: number;
};

export function TablaUsuarios({ filas }: { filas: UsuarioFila[] }) {
  const [busqueda, setBusqueda] = useState('');
  const [orden, setOrden] = useState<'reciente' | 'activo' | 'cultivos'>(
    'reciente'
  );
  const [aEliminar, setAEliminar] = useState<UsuarioFila | null>(null);
  const [aviso, setAviso] = useState<{ ok: boolean; texto: string } | null>(
    null
  );

  const visibles = useMemo(() => {
    const q = busqueda.trim().toLowerCase();
    const lista = q
      ? filas.filter(
          (f) =>
            f.email.toLowerCase().includes(q) ||
            (f.ciudad ?? '').toLowerCase().includes(q) ||
            nombrePais(f.pais).toLowerCase().includes(q)
        )
      : filas;
    return [...lista].sort((a, b) => {
      if (orden === 'cultivos') return b.cultivos - a.cultivos;
      if (orden === 'activo') {
        return (
          new Date(b.last_sign_in_at ?? 0).getTime() -
          new Date(a.last_sign_in_at ?? 0).getTime()
        );
      }
      return (
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
      );
    });
  }, [filas, busqueda, orden]);

  return (
    <>
      {aviso && (
        <p
          className={`mb-3 rounded-lg px-3 py-2 text-sm ${
            aviso.ok ? 'bg-nexus-50 text-nexus-800' : 'bg-red-50 text-red-700'
          }`}
        >
          {aviso.texto}
        </p>
      )}

      <div className="mb-3 flex flex-wrap items-center gap-2">
        <input
          className="input max-w-xs"
          placeholder="Buscar por email, ciudad o país…"
          value={busqueda}
          onChange={(e) => setBusqueda(e.target.value)}
        />
        <select
          className="input max-w-[200px]"
          value={orden}
          onChange={(e) => setOrden(e.target.value as typeof orden)}
        >
          <option value="reciente">Más recientes primero</option>
          <option value="activo">Actividad más reciente</option>
          <option value="cultivos">Más cultivos</option>
        </select>
        <span className="text-xs text-slate-500">
          {visibles.length} de {filas.length}
        </span>
        <div className="grow" />
        <Link href="/admin/usuarios/papelera" className="btn-secundario text-sm">
          Papelera
        </Link>
      </div>

      <div className="overflow-x-auto">
        <table className="tabla">
          <thead>
            <tr>
              <th>Usuario</th>
              <th>Ubicación</th>
              <th className="text-right">Predios</th>
              <th className="text-right">Lotes</th>
              <th className="text-right">Cultivos</th>
              <th>Feedback</th>
              <th>Última sesión</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {visibles.map((u) => (
              <tr key={u.user_id}>
                <td>
                  <p className="font-medium text-slate-800">{u.email}</p>
                  <p className="text-xs text-slate-500">
                    Alta: {fecha(u.created_at)}
                  </p>
                </td>
                <td className="text-sm">
                  {u.pais ? (
                    <>
                      <span aria-hidden>{banderaPais(u.pais)}</span>{' '}
                      {nombrePais(u.pais)}
                      <p className="text-xs text-slate-500">
                        {[u.ciudad, u.region].filter(Boolean).join(', ') || '—'}
                      </p>
                    </>
                  ) : (
                    <span className="text-slate-400">Sin predio</span>
                  )}
                </td>
                <td className="text-right">{u.predios}</td>
                <td className="text-right">{u.lotes}</td>
                <td className="text-right font-semibold text-nexus-800">
                  {u.cultivos}
                </td>
                <td>
                  {u.feedbacks === 0 ? (
                    <span className="text-xs text-slate-400">—</span>
                  ) : (
                    <Link
                      href={`/admin/feedback?usuario=${encodeURIComponent(u.email)}`}
                      className="inline-flex items-center gap-1"
                    >
                      <Chip tono={u.feedbacks_pendientes ? 'ambar' : 'verde'}>
                        {u.feedbacks} ·{' '}
                        {u.feedbacks_pendientes
                          ? `${u.feedbacks_pendientes} sin atender`
                          : 'al día'}
                      </Chip>
                    </Link>
                  )}
                </td>
                <td className="whitespace-nowrap text-xs">
                  {haceCuanto(u.last_sign_in_at)}
                </td>
                <td>
                  <button
                    className="btn-sutil px-2 py-1 text-xs text-amber-800 hover:bg-amber-50"
                    onClick={() => {
                      setAviso(null);
                      setAEliminar(u);
                    }}
                  >
                    A papelera
                  </button>
                </td>
              </tr>
            ))}
            {visibles.length === 0 && (
              <tr>
                <td colSpan={8} className="py-6 text-center text-slate-400">
                  Sin usuarios que coincidan con la búsqueda.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {aEliminar && (
        <DialogoPapelera
          usuario={aEliminar}
          onCerrar={() => setAEliminar(null)}
          onResultado={(r) => {
            setAviso({ ok: r.ok, texto: r.mensaje });
            setAEliminar(null);
          }}
        />
      )}
    </>
  );
}

function DialogoPapelera({
  usuario,
  onCerrar,
  onResultado,
}: {
  usuario: UsuarioFila;
  onCerrar: () => void;
  onResultado: (r: { ok: boolean; mensaje: string }) => void;
}) {
  const [confirmacion, setConfirmacion] = useState('');
  const [pendiente, iniciar] = useTransition();
  const coincide =
    confirmacion.trim().toLowerCase() === usuario.email.toLowerCase();

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
      <div className="w-full max-w-lg rounded-xl bg-white p-6 shadow-xl">
        <h3 className="text-lg font-bold text-amber-800">
          Mover a la papelera
        </h3>
        <div className="mt-3 space-y-2 text-sm text-slate-700">
          <p>
            Se suspenderá <strong>{usuario.email}</strong> (
            {usuario.predios} predio(s), {usuario.lotes} lote(s),{' '}
            {usuario.cultivos} cultivo(s)). No podrá iniciar sesión.
          </p>
          <p className="rounded-lg bg-nexus-50 px-3 py-2 text-nexus-800">
            Sus datos se conservan. Desde la papelera puedes{' '}
            <strong>recuperar</strong> la cuenta o{' '}
            <strong>eliminarla definitivamente</strong> (entonces sí se borran
            los datos privados; variedades y reportes comunitarios se
            conservan anónimos).
          </p>
          <label className="block pt-2">
            Escribe el correo del usuario para confirmar:
            <input
              className="input mt-1"
              value={confirmacion}
              onChange={(e) => setConfirmacion(e.target.value)}
              placeholder={usuario.email}
              autoFocus
            />
          </label>
        </div>
        <div className="mt-5 flex justify-end gap-2">
          <button className="btn-sutil" onClick={onCerrar} disabled={pendiente}>
            Cancelar
          </button>
          <button
            className="btn-primario"
            disabled={!coincide || pendiente}
            onClick={() =>
              iniciar(async () => {
                const r = await moverAPapelera(usuario.user_id, confirmacion);
                onResultado(r);
              })
            }
          >
            {pendiente ? 'Moviendo…' : 'Mover a papelera'}
          </button>
        </div>
      </div>
    </div>
  );
}
