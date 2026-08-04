'use client';

import { useMemo, useState, useTransition } from 'react';
import { Chip, Vacio } from '@/components/ui';
import { fecha } from '@/lib/formato';
import { actualizarFeedback, marcarLoteAtendido } from './acciones';

export type FeedbackItem = {
  id: number;
  created_at: string;
  tipo: string;
  calificacion: number | null;
  respuestas: { aspectos?: string[] } | null;
  comentario: string | null;
  email_usuario: string | null;
  app_version: string | null;
  plataforma: string | null;
  atendido: boolean;
  notas_gestion: string | null;
};

type Estado = 'todos' | 'pendientes' | 'atendidos';

export function ListaFeedback({
  items,
  filtroUsuarioInicial,
}: {
  items: FeedbackItem[];
  filtroUsuarioInicial: string;
}) {
  const [estado, setEstado] = useState<Estado>('pendientes');
  const [tipo, setTipo] = useState('todos');
  const [usuario, setUsuario] = useState(filtroUsuarioInicial);
  const [seleccion, setSeleccion] = useState<Set<number>>(new Set());
  const [aviso, setAviso] = useState<{ ok: boolean; texto: string } | null>(null);
  const [pendiente, iniciar] = useTransition();

  const tipos = useMemo(
    () => ['todos', ...Array.from(new Set(items.map((i) => i.tipo)))],
    [items]
  );

  const visibles = useMemo(() => {
    const q = usuario.trim().toLowerCase();
    return items.filter((f) => {
      if (estado === 'pendientes' && f.atendido) return false;
      if (estado === 'atendidos' && !f.atendido) return false;
      if (tipo !== 'todos' && f.tipo !== tipo) return false;
      if (q && !(f.email_usuario ?? '').toLowerCase().includes(q)) return false;
      return true;
    });
  }, [items, estado, tipo, usuario]);

  const alternar = (id: number) =>
    setSeleccion((prev) => {
      const s = new Set(prev);
      if (s.has(id)) s.delete(id);
      else s.add(id);
      return s;
    });

  const exportarCsv = () => {
    const cab = [
      'fecha', 'tipo', 'calificacion', 'comentario', 'aspectos',
      'usuario', 'version', 'plataforma', 'atendido', 'notas',
    ];
    const filas = visibles.map((f) => [
      f.created_at,
      f.tipo,
      f.calificacion ?? '',
      (f.comentario ?? '').replace(/"/g, "'"),
      (f.respuestas?.aspectos ?? []).join(' | '),
      f.email_usuario ?? '',
      f.app_version ?? '',
      f.plataforma ?? '',
      f.atendido ? 'sí' : 'no',
      (f.notas_gestion ?? '').replace(/"/g, "'"),
    ]);
    const csv = [cab, ...filas]
      .map((r) => r.map((c) => `"${String(c)}"`).join(','))
      .join('\n');
    const url = URL.createObjectURL(
      new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' })
    );
    const a = document.createElement('a');
    a.href = url;
    a.download = `feedback_nexus_${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

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

      <div className="mb-4 flex flex-wrap items-center gap-2">
        <select
          className="input max-w-[170px]"
          value={estado}
          onChange={(e) => setEstado(e.target.value as Estado)}
        >
          <option value="pendientes">Sin atender</option>
          <option value="atendidos">Atendidos</option>
          <option value="todos">Todos</option>
        </select>
        <select
          className="input max-w-[170px]"
          value={tipo}
          onChange={(e) => setTipo(e.target.value)}
        >
          {tipos.map((t) => (
            <option key={t} value={t}>
              {t === 'todos' ? 'Todos los tipos' : t}
            </option>
          ))}
        </select>
        <input
          className="input max-w-[240px]"
          placeholder="Filtrar por usuario…"
          value={usuario}
          onChange={(e) => setUsuario(e.target.value)}
        />
        <span className="text-xs text-slate-500">{visibles.length} resultado(s)</span>
        <div className="grow" />
        {seleccion.size > 0 && (
          <button
            className="btn-primario text-sm"
            disabled={pendiente}
            onClick={() =>
              iniciar(async () => {
                const r = await marcarLoteAtendido([...seleccion]);
                setAviso({ ok: r.ok, texto: r.mensaje });
                if (r.ok) setSeleccion(new Set());
              })
            }
          >
            Marcar {seleccion.size} como atendido(s)
          </button>
        )}
        <button className="btn-secundario text-sm" onClick={exportarCsv}>
          Exportar CSV
        </button>
      </div>

      {visibles.length === 0 ? (
        <Vacio texto="No hay feedback que coincida con los filtros." />
      ) : (
        <ul className="space-y-3">
          {visibles.map((f) => (
            <TarjetaFeedback
              key={f.id}
              item={f}
              seleccionado={seleccion.has(f.id)}
              onSeleccionar={() => alternar(f.id)}
              onAviso={setAviso}
            />
          ))}
        </ul>
      )}
    </>
  );
}

function TarjetaFeedback({
  item,
  seleccionado,
  onSeleccionar,
  onAviso,
}: {
  item: FeedbackItem;
  seleccionado: boolean;
  onSeleccionar: () => void;
  onAviso: (a: { ok: boolean; texto: string }) => void;
}) {
  const [notas, setNotas] = useState(item.notas_gestion ?? '');
  const [editandoNotas, setEditandoNotas] = useState(false);
  const [pendiente, iniciar] = useTransition();

  const esProblema =
    item.tipo === 'bug' ||
    (item.calificacion !== null && item.calificacion <= 2);

  const mailto = () => {
    const asunto = encodeURIComponent(
      `NEXUS Siembras — respuesta a tu comentario del ${fecha(item.created_at)}`
    );
    const cuerpo = encodeURIComponent(
      `Hola,\n\nGracias por tu comentario:\n\n` +
        `"${item.comentario ?? '(sin texto)'}"\n\n` +
        `---\nEnviado desde NEXUS Siembras v${item.app_version ?? ''} ` +
        `(${item.plataforma ?? ''})\n\n`
    );
    return `mailto:${item.email_usuario ?? ''}?subject=${asunto}&body=${cuerpo}`;
  };

  return (
    <li
      className={`rounded-xl border p-4 ${
        item.atendido
          ? 'border-slate-200 bg-white'
          : esProblema
            ? 'border-red-200 bg-red-50/40'
            : 'border-amber-200 bg-amber-50/30'
      }`}
    >
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="flex items-start gap-3">
          {!item.atendido && (
            <input
              type="checkbox"
              className="mt-1 h-4 w-4 accent-[#1B7A3E]"
              checked={seleccionado}
              onChange={onSeleccionar}
              aria-label="Seleccionar"
            />
          )}
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <Chip tono={esProblema ? 'rojo' : 'azul'}>{item.tipo}</Chip>
              {item.calificacion !== null && (
                <span className="text-sm text-amber-600">
                  {'★'.repeat(item.calificacion)}
                  <span className="text-slate-300">
                    {'★'.repeat(5 - item.calificacion)}
                  </span>
                </span>
              )}
              {item.atendido ? (
                <Chip tono="verde">atendido</Chip>
              ) : (
                <Chip tono="ambar">pendiente</Chip>
              )}
            </div>
            <p className="mt-2 text-sm text-slate-800">
              {item.comentario ?? (
                <em className="text-slate-400">Sin comentario escrito</em>
              )}
            </p>
            {(item.respuestas?.aspectos ?? []).length > 0 && (
              <div className="mt-2 flex flex-wrap gap-1">
                {item.respuestas!.aspectos!.map((a) => (
                  <span key={a} className="chip bg-slate-100 text-slate-600">
                    {a}
                  </span>
                ))}
              </div>
            )}
            <p className="mt-2 text-xs text-slate-500">
              {fecha(item.created_at, true)} ·{' '}
              {item.email_usuario ?? 'anónimo'} · v{item.app_version ?? '—'} ·{' '}
              {item.plataforma ?? '—'}
            </p>
          </div>
        </div>

        <div className="flex flex-wrap gap-1">
          {item.email_usuario && (
            <a className="btn-sutil px-2 py-1 text-xs" href={mailto()}>
              Responder
            </a>
          )}
          <button
            className="btn-sutil px-2 py-1 text-xs"
            onClick={() => setEditandoNotas((v) => !v)}
          >
            {item.notas_gestion ? 'Ver notas' : 'Añadir nota'}
          </button>
          <button
            className={`px-2 py-1 text-xs ${
              item.atendido ? 'btn-sutil' : 'btn-primario'
            }`}
            disabled={pendiente}
            onClick={() =>
              iniciar(async () => {
                const r = await actualizarFeedback(item.id, {
                  atendido: !item.atendido,
                });
                onAviso({ ok: r.ok, texto: r.mensaje });
              })
            }
          >
            {item.atendido ? 'Reabrir' : 'Marcar atendido'}
          </button>
        </div>
      </div>

      {editandoNotas && (
        <div className="mt-3 border-t border-slate-200 pt-3">
          <textarea
            className="input"
            rows={2}
            placeholder="Nota interna: qué se hizo, decisión tomada, número de versión donde se corrige…"
            value={notas}
            onChange={(e) => setNotas(e.target.value)}
          />
          <div className="mt-2 flex justify-end gap-2">
            <button
              className="btn-sutil text-xs"
              onClick={() => {
                setNotas(item.notas_gestion ?? '');
                setEditandoNotas(false);
              }}
            >
              Cancelar
            </button>
            <button
              className="btn-primario text-xs"
              disabled={pendiente}
              onClick={() =>
                iniciar(async () => {
                  const r = await actualizarFeedback(item.id, {
                    notas_gestion: notas,
                  });
                  onAviso({ ok: r.ok, texto: r.mensaje });
                  if (r.ok) setEditandoNotas(false);
                })
              }
            >
              Guardar nota
            </button>
          </div>
        </div>
      )}

      {!editandoNotas && item.notas_gestion && (
        <p className="mt-3 rounded-lg bg-slate-100 px-3 py-2 text-xs text-slate-600">
          <strong>Nota:</strong> {item.notas_gestion}
        </p>
      )}
    </li>
  );
}
