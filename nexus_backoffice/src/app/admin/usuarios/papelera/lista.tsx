'use client';

import { useState, useTransition } from 'react';
import { Chip } from '@/components/ui';
import { fecha } from '@/lib/formato';
import {
  eliminarUsuarioDefinitivo,
  recuperarUsuario,
} from '../acciones';

export type FilaPapelera = {
  user_id: string;
  email: string;
  snapshot: {
    predios?: number;
    lotes?: number;
    cultivos?: number;
    feedbacks?: number;
  } | null;
  motivo: string | null;
  eliminado_at: string;
  eliminado_por: string | null;
};

export function ListaPapelera({ filas }: { filas: FilaPapelera[] }) {
  const [aviso, setAviso] = useState<{ ok: boolean; texto: string } | null>(
    null
  );
  const [aBorrar, setABorrar] = useState<FilaPapelera | null>(null);

  if (filas.length === 0) {
    return (
      <p className="py-8 text-center text-sm text-slate-400">
        La papelera está vacía.
      </p>
    );
  }

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

      <div className="overflow-x-auto">
        <table className="tabla">
          <thead>
            <tr>
              <th>Usuario</th>
              <th>Snapshot</th>
              <th>En papelera desde</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {filas.map((f) => (
              <Fila
                key={f.user_id}
                fila={f}
                onAviso={setAviso}
                onPedirBorrar={() => {
                  setAviso(null);
                  setABorrar(f);
                }}
              />
            ))}
          </tbody>
        </table>
      </div>

      {aBorrar && (
        <DialogoBorrarDefinitivo
          fila={aBorrar}
          onCerrar={() => setABorrar(null)}
          onResultado={(r) => {
            setAviso({ ok: r.ok, texto: r.mensaje });
            setABorrar(null);
          }}
        />
      )}
    </>
  );
}

function Fila({
  fila,
  onAviso,
  onPedirBorrar,
}: {
  fila: FilaPapelera;
  onAviso: (a: { ok: boolean; texto: string }) => void;
  onPedirBorrar: () => void;
}) {
  const [pendiente, iniciar] = useTransition();
  const s = fila.snapshot ?? {};

  return (
    <tr>
      <td>
        <p className="font-medium text-slate-800">{fila.email}</p>
        {fila.motivo && (
          <p className="text-xs text-slate-500">{fila.motivo}</p>
        )}
      </td>
      <td className="text-xs text-slate-600">
        <Chip tono="ambar">
          {s.predios ?? 0} predios · {s.lotes ?? 0} lotes ·{' '}
          {s.cultivos ?? 0} cultivos
        </Chip>
      </td>
      <td className="whitespace-nowrap text-xs">
        {fecha(fila.eliminado_at, true)}
      </td>
      <td>
        <div className="flex flex-wrap justify-end gap-1">
          <button
            className="btn-primario px-2 py-1 text-xs"
            disabled={pendiente}
            onClick={() =>
              iniciar(async () => {
                const r = await recuperarUsuario(fila.user_id);
                onAviso({ ok: r.ok, texto: r.mensaje });
              })
            }
          >
            {pendiente ? '…' : 'Recuperar'}
          </button>
          <button
            className="btn-sutil px-2 py-1 text-xs text-red-600 hover:bg-red-50"
            disabled={pendiente}
            onClick={onPedirBorrar}
          >
            Eliminar definitivo
          </button>
        </div>
      </td>
    </tr>
  );
}

function DialogoBorrarDefinitivo({
  fila,
  onCerrar,
  onResultado,
}: {
  fila: FilaPapelera;
  onCerrar: () => void;
  onResultado: (r: { ok: boolean; mensaje: string }) => void;
}) {
  const [confirmacion, setConfirmacion] = useState('');
  const [pendiente, iniciar] = useTransition();
  const coincide =
    confirmacion.trim().toLowerCase() === fila.email.toLowerCase();

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
      <div className="w-full max-w-lg rounded-xl bg-white p-6 shadow-xl">
        <h3 className="text-lg font-bold text-red-700">
          Eliminar definitivamente
        </h3>
        <div className="mt-3 space-y-2 text-sm text-slate-700">
          <p>
            Se borrará <strong>{fila.email}</strong> y sus datos privados. Esta
            acción no se puede deshacer.
          </p>
          <p className="rounded-lg bg-nexus-50 px-3 py-2 text-nexus-800">
            Se conservan anónimos: variedades comunitarias y reportes de
            patologías.
          </p>
          <label className="block pt-2">
            Escribe el correo para confirmar:
            <input
              className="input mt-1"
              value={confirmacion}
              onChange={(e) => setConfirmacion(e.target.value)}
              placeholder={fila.email}
              autoFocus
            />
          </label>
        </div>
        <div className="mt-5 flex justify-end gap-2">
          <button className="btn-sutil" onClick={onCerrar} disabled={pendiente}>
            Cancelar
          </button>
          <button
            className="btn-peligro"
            disabled={!coincide || pendiente}
            onClick={() =>
              iniciar(async () => {
                const r = await eliminarUsuarioDefinitivo(
                  fila.user_id,
                  confirmacion
                );
                onResultado(r);
              })
            }
          >
            {pendiente ? 'Eliminando…' : 'Eliminar definitivamente'}
          </button>
        </div>
      </div>
    </div>
  );
}
