import Link from 'next/link';
import { redirect } from 'next/navigation';
import { obtenerSesionAdmin } from '@/lib/auth';
import { emailSugerido } from './acciones';
import { FormularioLogin } from './formulario';

export default async function LoginPage({
  searchParams,
}: {
  searchParams: { motivo?: string };
}) {
  // Ya autenticado y autorizado → directo al panel.
  if (await obtenerSesionAdmin()) redirect('/admin');

  const sugerido = await emailSugerido();

  return (
    <main className="flex min-h-screen items-center justify-center bg-gradient-to-br from-nexus-800 to-nexus-600 px-5 py-10">
      <div className="w-full max-w-md">
        <div className="mb-6 text-center text-white">
          <p className="text-5xl" aria-hidden>🌱</p>
          <h1 className="mt-2 text-2xl font-bold">NEXUS Siembras</h1>
          <p className="text-sm text-nexus-100">Panel de administración</p>
        </div>

        <div className="rounded-xl bg-white p-6 shadow-lg">
          {searchParams.motivo === 'no-autorizado' && (
            <p className="mb-4 rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-800">
              Necesitas iniciar sesión con una cuenta autorizada.
            </p>
          )}
          <FormularioLogin emailSugerido={sugerido} />
        </div>

        <p className="mt-6 text-center text-sm text-nexus-100">
          <Link href="/" className="underline hover:text-white">
            ← Volver al sitio público
          </Link>
        </p>
      </div>
    </main>
  );
}
