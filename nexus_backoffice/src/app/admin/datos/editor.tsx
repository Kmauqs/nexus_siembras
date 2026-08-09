'use client';

import { useMemo, useState, useTransition } from 'react';
import { Card, Chip, Vacio } from '@/components/ui';
import {
  atenderReporte, eliminarFila, guardarFila, moderarReporte, type Tabla,
} from './acciones';

export type Columna = {
  campo: string;
  etiqueta: string;
  tipo?: 'texto' | 'numero' | 'bool' | 'select' | 'texto-largo' | 'estado';
  opciones?: string[];
  soloLectura?: boolean;
  ancho?: string;
};

function diasSinActividad(fila: Record<string, unknown>): number | null {
  const v = (fila.ultima_actividad_at ?? fila.created_at) as string | null;
  if (!v) return null;
  return Math.floor((Date.now() - new Date(v).getTime()) / 86_400_000);
}

type Fila = Record<string, unknown> & { id: number };

type DefTabla = {
  id: Tabla;
  titulo: string;
  icono: string;
  columnas: Columna[];
  filas: Fila[];
  permiteCrear: boolean;
};

export function EditorTablas({
  tablas,
  diasDesatendida = 60,
}: {
  tablas: DefTabla[];
  /** Umbral desde app_config.patologia_dias_desatendida. */
  diasDesatendida?: number;
}) {
  const [activa, setActiva] = useState<Tabla>(tablas[0].id);
  const def = tablas.find((t) => t.id === activa)!;

  return (
    <div>
      <div className="mb-4 flex flex-wrap gap-2">
        {tablas.map((t) => (
          <button
            key={t.id}
            onClick={() => setActiva(t.id)}
            className={`btn text-sm ${
              t.id === activa
                ? 'bg-nexus-600 text-white'
                : 'border border-slate-300 bg-white text-slate-700 hover:bg-slate-50'
            }`}
          >
            <span aria-hidden>{t.icono}</span>
            {t.titulo}
            <span className="ml-1 rounded-full bg-black/10 px-1.5 text-xs">
              {t.filas.length}
            </span>
          </button>
        ))}
      </div>
      <TablaEditable
        key={def.id}
        def={def}
        diasDesatendida={diasDesatendida}
      />
    </div>
  );
}

function TablaEditable({
  def,
  diasDesatendida,
}: {
  def: DefTabla;
  diasDesatendida: number;
}) {
  const [busqueda, setBusqueda] = useState('');
  const [editando, setEditando] = useState<Fila | 'nuevo' | null>(null);
  const [aviso, setAviso] = useState<{ ok: boolean; texto: string } | null>(
    null
  );
  const [pendiente, iniciar] = useTransition();

  const visibles = useMemo(() => {
    const q = busqueda.trim().toLowerCase();
    if (!q) return def.filas;
    return def.filas.filter((f) =>
      def.columnas.some((c) =>
        String(f[c.campo] ?? '').toLowerCase().includes(q)
      )
    );
  }, [def, busqueda]);

  const esReportes = def.id === 'patologias_reportadas';

  const borrar = (fila: Fila) => {
    if (!confirm('¿Seguro que deseas eliminar este registro?')) return;
    iniciar(async () => {
      const r = await eliminarFila(def.id, fila.id);
      setAviso({ ok: r.ok, texto: r.mensaje });
    });
  };

  const atender = (fila: Fila) =>
    iniciar(async () => {
      const r = await atenderReporte(fila.id);
      setAviso({ ok: r.ok, texto: r.mensaje });
    });

  const moderar = (fila: Fila) => {
    const oculto = fila.deleted_at != null;
    if (
      !oculto &&
      !confirm(
        'Ocultar del mapa público. El reporte se conserva en la base y ' +
          'puede restaurarse. ¿Continuar?'
      )
    ) {
      return;
    }
    iniciar(async () => {
      const r = await moderarReporte(fila.id, !oculto);
      setAviso({ ok: r.ok, texto: r.mensaje });
    });
  };

  return (
    <Card titulo={def.titulo} icono={<span>{def.icono}</span>}>
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
          placeholder="Filtrar…"
          value={busqueda}
          onChange={(e) => setBusqueda(e.target.value)}
        />
        <span className="text-xs text-slate-500">
          {visibles.length} de {def.filas.length}
        </span>
        <div className="grow" />
        {def.permiteCrear && (
          <button
            className="btn-primario text-sm"
            onClick={() => setEditando('nuevo')}
          >
            + Nuevo registro
          </button>
        )}
      </div>

      {visibles.length === 0 ? (
        <Vacio texto="Sin registros." />
      ) : (
        <div className="max-h-[65vh] overflow-auto rounded-lg border border-slate-200">
          <table className="tabla">
            <thead>
              <tr>
                {def.columnas.map((c) => (
                  <th key={c.campo} className={c.ancho}>
                    {c.etiqueta}
                  </th>
                ))}
                <th></th>
              </tr>
            </thead>
            <tbody>
              {visibles.map((f) => {
                const oculto = f.deleted_at != null;
                return (
                  <tr key={f.id} className={oculto ? 'opacity-50' : ''}>
                    {def.columnas.map((c) => (
                      <td key={c.campo} className="max-w-xs">
                        <Celda
                          valor={f[c.campo]}
                          columna={c}
                          fila={f}
                          diasDesatendida={diasDesatendida}
                        />
                      </td>
                    ))}
                    <td className="whitespace-nowrap">
                      <button
                        className="btn-sutil px-2 py-1 text-xs"
                        onClick={() => setEditando(f)}
                      >
                        Editar
                      </button>
                      {esReportes ? (
                        <>
                          <button
                            className="btn-sutil px-2 py-1 text-xs text-nexus-700 hover:bg-nexus-50"
                            disabled={pendiente}
                            title="Reinicia el contador: vuelve a contar como foco activo"
                            onClick={() => atender(f)}
                          >
                            Atender
                          </button>
                          <button
                            className="btn-sutil px-2 py-1 text-xs text-amber-700 hover:bg-amber-50"
                            disabled={pendiente}
                            onClick={() => moderar(f)}
                          >
                            {oculto ? 'Restaurar' : 'Ocultar'}
                          </button>
                        </>
                      ) : (
                        <button
                          className="btn-sutil px-2 py-1 text-xs text-red-600 hover:bg-red-50"
                          disabled={pendiente}
                          onClick={() => borrar(f)}
                        >
                          Borrar
                        </button>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {editando && (
        <DialogoEdicion
          def={def}
          fila={editando === 'nuevo' ? null : editando}
          onCerrar={() => setEditando(null)}
          onResultado={(r) => {
            setAviso({ ok: r.ok, texto: r.mensaje });
            if (r.ok) setEditando(null);
          }}
        />
      )}
    </Card>
  );
}

function Celda({
  valor,
  columna,
  fila,
  diasDesatendida = 60,
}: {
  valor: unknown;
  columna: Columna;
  fila?: Record<string, unknown>;
  diasDesatendida?: number;
}) {
  // Estado del reporte: activa (verde) / desatendida (gris) / oculta.
  if (columna.tipo === 'estado' && fila) {
    if (fila.deleted_at != null) return <Chip>oculta</Chip>;
    const dias = diasSinActividad(fila);
    if (dias === null) return <Chip>sin datos</Chip>;
    const desatendida = dias >= diasDesatendida;
    return (
      <span title={`${dias} día(s) sin actividad`}>
        {desatendida ? (
          <Chip tono="gris">● desatendida</Chip>
        ) : (
          <Chip tono="verde">● activa</Chip>
        )}
      </span>
    );
  }

  if (valor === null || valor === undefined || valor === '') {
    return <span className="text-slate-300">—</span>;
  }
  if (columna.tipo === 'bool') {
    return valor ? <Chip tono="verde">sí</Chip> : <Chip>no</Chip>;
  }
  const texto = String(valor);
  if (texto.length > 90) {
    return (
      <span title={texto} className="block truncate">
        {texto.slice(0, 90)}…
      </span>
    );
  }
  return <span>{texto}</span>;
}

function DialogoEdicion({
  def,
  fila,
  onCerrar,
  onResultado,
}: {
  def: DefTabla;
  fila: Fila | null;
  onCerrar: () => void;
  onResultado: (r: { ok: boolean; mensaje: string }) => void;
}) {
  const editables = def.columnas.filter((c) => !c.soloLectura);
  const [valores, setValores] = useState<Record<string, unknown>>(() =>
    Object.fromEntries(
      editables.map((c) => [c.campo, fila ? fila[c.campo] ?? '' : ''])
    )
  );
  const [pendiente, iniciar] = useTransition();

  const set = (campo: string, v: unknown) =>
    setValores((prev) => ({ ...prev, [campo]: v }));

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
      <div className="max-h-[90vh] w-full max-w-2xl overflow-auto rounded-xl bg-white p-6 shadow-xl">
        <h3 className="text-lg font-bold text-nexus-800">
          {fila ? 'Editar registro' : 'Nuevo registro'} · {def.titulo}
        </h3>

        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          {editables.map((c) => (
            <label
              key={c.campo}
              className={`block text-sm ${
                c.tipo === 'texto-largo' ? 'sm:col-span-2' : ''
              }`}
            >
              <span className="mb-1 block font-medium text-slate-700">
                {c.etiqueta}
              </span>
              {c.tipo === 'select' ? (
                <select
                  className="input"
                  value={String(valores[c.campo] ?? '')}
                  onChange={(e) => set(c.campo, e.target.value)}
                >
                  <option value="">—</option>
                  {(c.opciones ?? []).map((o) => (
                    <option key={o} value={o}>{o}</option>
                  ))}
                </select>
              ) : c.tipo === 'bool' ? (
                <select
                  className="input"
                  value={valores[c.campo] ? 'true' : 'false'}
                  onChange={(e) => set(c.campo, e.target.value === 'true')}
                >
                  <option value="true">Sí</option>
                  <option value="false">No</option>
                </select>
              ) : c.tipo === 'texto-largo' ? (
                <textarea
                  className="input"
                  rows={3}
                  value={String(valores[c.campo] ?? '')}
                  onChange={(e) => set(c.campo, e.target.value)}
                />
              ) : (
                <input
                  className="input"
                  type={c.tipo === 'numero' ? 'number' : 'text'}
                  value={String(valores[c.campo] ?? '')}
                  onChange={(e) => set(c.campo, e.target.value)}
                />
              )}
            </label>
          ))}
        </div>

        <div className="mt-5 flex justify-end gap-2">
          <button className="btn-sutil" onClick={onCerrar} disabled={pendiente}>
            Cancelar
          </button>
          <button
            className="btn-primario"
            disabled={pendiente}
            onClick={() =>
              iniciar(async () => {
                const r = await guardarFila(
                  def.id,
                  fila?.id ?? null,
                  valores
                );
                onResultado(r);
              })
            }
          >
            {pendiente ? 'Guardando…' : 'Guardar'}
          </button>
        </div>
      </div>
    </div>
  );
}
