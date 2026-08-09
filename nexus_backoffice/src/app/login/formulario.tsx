'use client';

import { useState, useTransition } from 'react';
import { solicitarMagicLink } from './acciones';

export function FormularioLogin({ emailSugerido }: { emailSugerido: string }) {
  const [email, setEmail] = useState(emailSugerido);
  const [enviado, setEnviado] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; texto: string } | null>(null);
  const [pendiente, iniciar] = useTransition();

  const pedirEnlace = () =>
    iniciar(async () => {
      const fd = new FormData();
      fd.set('email', email);
      const r = await solicitarMagicLink(null, fd);
      setMsg({ ok: r.ok, texto: r.mensaje });
      if (r.ok) setEnviado(true);
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
          disabled={pendiente || enviado}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="tucorreo@dominio.com"
          autoComplete="email"
          onKeyDown={(e) => {
            if (e.key === 'Enter' && email.includes('@')) pedirEnlace();
          }}
        />
      </div>

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

      {enviado ? (
        <div className="space-y-2">
          <p className="rounded-lg bg-slate-50 px-3 py-3 text-sm text-slate-700">
            Abre el correo y pulsa <strong>Sign in</strong> (o el enlace
            equivalente). Te traerá de vuelta a este sitio ya autenticado.
          </p>
          <button
            className="btn-sutil w-full"
            onClick={() => {
              setEnviado(false);
              setMsg(null);
            }}
            disabled={pendiente}
          >
            Usar otro correo o reenviar enlace
          </button>
        </div>
      ) : (
        <button
          className="btn-primario w-full"
          onClick={pedirEnlace}
          disabled={pendiente || !email.includes('@')}
        >
          {pendiente ? 'Enviando…' : 'Enviar enlace de acceso'}
        </button>
      )}

      <p className="border-t border-slate-100 pt-3 text-xs text-slate-500">
        El acceso está restringido a los correos autorizados. No se usa
        contraseña: cada ingreso usa el enlace mágico enviado por email
        (plantilla por defecto de Supabase).
      </p>
    </div>
  );
}
