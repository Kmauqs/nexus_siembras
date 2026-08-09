import Link from 'next/link';
import { redirect } from 'next/navigation';
import { Marca } from '@/components/ui';
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
  const motivo = searchParams.motivo;

  return (
    <main className="flex min-h-screen items-center justify-center bg-gradient-to-br from-nexus-800 to-nexus-600 px-5 py-10">
      <div className="w-full max-w-md">
        <div className="mb-6 flex flex-col items-center text-center text-white">
          <Marca clara tamaño={72} compacta />
          <p className="mt-2 text-sm text-nexus-100">Panel de administración</p>
        </div>

        <div className="rounded-xl bg-white p-6 shadow-lg">
          {motivo === 'no-autorizado' && (
            <p className="mb-4 rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-800">
              Necesitas iniciar sesión con una cuenta autorizada.
            </p>
          )}
          {motivo === 'enlace-invalido' && (
            <p className="mb-4 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">
              El enlace no es válido o ya venció. Solicita uno nuevo.
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
