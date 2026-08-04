'use client';

import { useState, useTransition } from 'react';
import { Chip } from '@/components/ui';
import { guardarAdmin, guardarParametro } from './acciones';

export type Parametro = {
  clave: string;
  valor: string | null;
  descripcion: string | null;
  tipo: string;
  updated_at: string | null;
};

export type AdminFila = {
  email: string;
  nombre: string | null;
  activo: boolean;
};

export function FormConfig({
  parametros,
  admins,
  emailSesion,
}: {
  parametros: Parametro[];
  admins: AdminFila[];
  emailSesion: string;
}) {
  const [aviso, setAviso] = useState<{ ok: boolean; texto: string } | null>(
    null
  );

  return (
    <div className="space-y-6">
      {aviso && (
        <p
          className={`rounded-lg px-3 py-2 text-sm ${
            aviso.ok ? 'bg-nexus-50 text-nexus-800' : 'bg-red-50 text-red-700'
          }`}
        >
          {aviso.texto}
        </p>
      )}

      <div className="space-y-3">
        {parametros.map((p) => (
          <FilaParametro key={p.clave} p={p} onAviso={setAviso} />
        ))}
        {parametros.length === 0 && (
          <p className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-800">
            No se encontraron parámetros. ¿Aplicaste la migración 0017 en
            Supabase?
          </p>
        )}
      </div>

      <section className="border-t border-slate-200 pt-5">
        <h3 className="card-title">👤 Acceso al panel</h3>
        <p className="mb-3 text-sm text-slate-600">
          Correos que pueden solicitar código de acceso. El ingreso es sin
          contraseña: código de 6 dígitos enviado por email.
        </p>
        <TablaAdmins
          admins={admins}
          emailSesion={emailSesion}
          onAviso={setAviso}
        />
      </section>
    </div>
  );
}

function FilaParametro({
  p,
  onAviso,
}: {
  p: Parametro;
  onAviso: (a: { ok: boolean; texto: string }) => void;
}) {
  const [valor, setValor] = useState(p.valor ?? '');
  const [pendiente, iniciar] = useTransition();
  const cambiado = valor !== (p.valor ?? '');

  return (
    <div className="grid gap-2 rounded-lg border border-slate-200 p-3 sm:grid-cols-[1fr_auto]">
      <div>
        <label className="block text-sm font-medium text-slate-800">
          {p.descripcion ?? p.clave}
        </label>
        <p className="mb-2 font-mono text-[11px] text-slate-400">{p.clave}</p>
        {p.tipo === 'bool' ? (
          <select
            className="input max-w-xs"
            value={valor}
            onChange={(e) => setValor(e.target.value)}
          >
            <option value="true">Activado</option>
            <option value="false">Desactivado</option>
          </select>
        ) : (
          <input
            className="input"
            type={
              p.tipo === 'email' ? 'email' : p.tipo === 'numero' ? 'number' : 'text'
            }
            value={valor}
            onChange={(e) => setValor(e.target.value)}
          />
        )}
      </div>
      <div className="flex items-end">
        <button
          className="btn-primario text-sm"
          disabled={!cambiado || pendiente}
          onClick={() =>
            iniciar(async () => {
              const r = await guardarParametro(p.clave, valor, p.tipo);
              onAviso({ ok: r.ok, texto: r.mensaje });
            })
          }
        >
          {pendiente ? 'Guardando…' : 'Guardar'}
        </button>
      </div>
    </div>
  );
}

function TablaAdmins({
  admins,
  emailSesion,
  onAviso,
}: {
  admins: AdminFila[];
  emailSesion: string;
  onAviso: (a: { ok: boolean; texto: string }) => void;
}) {
  const [nuevo, setNuevo] = useState('');
  const [nombre, setNombre] = useState('');
  const [pendiente, iniciar] = useTransition();

  return (
    <>
      <div className="overflow-hidden rounded-lg border border-slate-200">
        <table className="tabla">
          <thead>
            <tr>
              <th>Correo</th>
              <th>Nombre</th>
              <th>Estado</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {admins.map((a) => (
              <tr key={a.email}>
                <td className="font-medium">
                  {a.email}
                  {a.email === emailSesion && (
                    <span className="ml-2 text-xs text-slate-400">(tú)</span>
                  )}
                </td>
                <td>{a.nombre ?? '—'}</td>
                <td>
                  {a.activo ? (
                    <Chip tono="verde">activo</Chip>
                  ) : (
                    <Chip>inactivo</Chip>
                  )}
                </td>
                <td>
                  <button
                    className="btn-sutil px-2 py-1 text-xs"
                    disabled={pendiente || a.email === emailSesion}
                    onClick={() =>
                      iniciar(async () => {
                        const r = await guardarAdmin(
                          a.email,
                          !a.activo,
                          a.nombre ?? undefined
                        );
                        onAviso({ ok: r.ok, texto: r.mensaje });
                      })
                    }
                  >
                    {a.activo ? 'Desactivar' : 'Activar'}
                  </button>
                </td>
              </tr>
            ))}
            {admins.length === 0 && (
              <tr>
                <td colSpan={4} className="py-4 text-center text-slate-400">
                  Sin administradores registrados en la tabla.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="mt-3 flex flex-wrap items-end gap-2">
        <label className="text-sm">
          <span className="mb-1 block font-medium text-slate-700">
            Nuevo administrador
          </span>
          <input
            className="input w-64"
            type="email"
            placeholder="correo@dominio.com"
            value={nuevo}
            onChange={(e) => setNuevo(e.target.value)}
          />
        </label>
        <label className="text-sm">
          <span className="mb-1 block font-medium text-slate-700">Nombre</span>
          <input
            className="input w-48"
            placeholder="Opcional"
            value={nombre}
            onChange={(e) => setNombre(e.target.value)}
          />
        </label>
        <button
          className="btn-primario text-sm"
          disabled={pendiente || !nuevo.includes('@')}
          onClick={() =>
            iniciar(async () => {
              const r = await guardarAdmin(nuevo, true, nombre);
              onAviso({ ok: r.ok, texto: r.mensaje });
              if (r.ok) {
                setNuevo('');
                setNombre('');
              }
            })
          }
        >
          Agregar
        </button>
      </div>
      <p className="mt-2 text-xs text-slate-500">
        El nuevo administrador debe tener una cuenta creada en la app (el
        login del panel no crea usuarios nuevos).
      </p>
    </>
  );
}
