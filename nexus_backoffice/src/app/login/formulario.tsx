'use client';

import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { solicitarCodigo, verificarCodigo } from './acciones';

export function FormularioLogin({ emailSugerido }: { emailSugerido: string }) {
  const router = useRouter();
  const [paso, setPaso] = useState<'email' | 'codigo'>('email');
  const [email, setEmail] = useState(emailSugerido);
  const [codigo, setCodigo] = useState('');
  const [msg, setMsg] = useState<{ ok: boolean; texto: string } | null>(null);
  const [pendiente, iniciar] = useTransition();

  const pedirCodigo = () =>
    iniciar(async () => {
      const fd = new FormData();
      fd.set('email', email);
      const r = await solicitarCodigo(null, fd);
      setMsg({ ok: r.ok, texto: r.mensaje });
      if (r.ok) setPaso('codigo');
    });

  const validar = () =>
    iniciar(async () => {
      const fd = new FormData();
      fd.set('email', email);
      fd.set('codigo', codigo);
      const r = await verificarCodigo(null, fd);
      setMsg({ ok: r.ok, texto: r.mensaje });
      if (r.ok) {
        router.replace('/admin');
        router.refresh();
      }
    });

  return (
    <div className="space-y-4">
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">
          Correo del administrador
        </label>
        <input
          type="email"
          className="input"
          value={email}
          disabled={paso === 'codigo' || pendiente}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="tucorreo@dominio.com"
          autoComplete="email"
        />
      </div>

      {paso === 'codigo' && (
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">
            Código de 6 dígitos
          </label>
          <input
            inputMode="numeric"
            maxLength={6}
            className="input text-center text-2xl font-bold tracking-[0.5em]"
            value={codigo}
            disabled={pendiente}
            onChange={(e) => setCodigo(e.target.value.replace(/\D/g, ''))}
            placeholder="······"
            autoFocus
            onKeyDown={(e) => {
              if (e.key === 'Enter' && codigo.length === 6) validar();
            }}
          />
          <p className="mt-1 text-xs text-slate-500">
            Revisa tu bandeja de entrada (y la carpeta de correo no deseado).
            El código vence en 60 minutos.
          </p>
        </div>
      )}

      {msg && (
        <p
          className={`rounded-lg px-3 py-2 text-sm ${
            msg.ok
              ? 'bg-nexus-50 text-nexus-800'
              : 'bg-red-50 text-red-700'
          }`}
        >
          {msg.texto}
        </p>
      )}

      {paso === 'email' ? (
        <button
          className="btn-primario w-full"
          onClick={pedirCodigo}
          disabled={pendiente || !email.includes('@')}
        >
          {pendiente ? 'Enviando…' : 'Enviar código de acceso'}
        </button>
      ) : (
        <div className="space-y-2">
          <button
            className="btn-primario w-full"
            onClick={validar}
            disabled={pendiente || codigo.length !== 6}
          >
            {pendiente ? 'Verificando…' : 'Ingresar'}
          </button>
          <button
            className="btn-sutil w-full"
            onClick={() => {
              setPaso('email');
              setCodigo('');
              setMsg(null);
            }}
            disabled={pendiente}
          >
            Usar otro correo o reenviar código
          </button>
        </div>
      )}

      <p className="border-t border-slate-100 pt-3 text-xs text-slate-500">
        El acceso está restringido a los correos autorizados. No se usa
        contraseña: cada ingreso requiere un código nuevo enviado por email.
      </p>
    </div>
  );
}
