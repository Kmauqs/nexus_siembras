'use client';

import {
  Bar, BarChart, CartesianGrid, Cell, Legend, Line, LineChart, Pie,
  PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts';
import { COLORES_GRAFICO } from '@/lib/formato';

type Dato = { nombre: string; valor: number };

/** Gráfico circular (usuarios por país, feedback por tipo, etc.). */
export function GraficoCircular({
  datos,
  altura = 280,
}: {
  datos: Dato[];
  altura?: number;
}) {
  if (!datos.length) {
    return (
      <p className="py-10 text-center text-sm text-slate-400">
        Sin datos para graficar.
      </p>
    );
  }
  const total = datos.reduce((s, d) => s + d.valor, 0);
  return (
    <ResponsiveContainer width="100%" height={altura}>
      <PieChart>
        <Pie
          data={datos}
          dataKey="valor"
          nameKey="nombre"
          innerRadius="45%"
          outerRadius="78%"
          paddingAngle={2}
          label={({ name, value }) =>
            `${name} ${((Number(value) / total) * 100).toFixed(0)}%`
          }
          labelLine={false}
        >
          {datos.map((_, i) => (
            <Cell
              key={i}
              fill={COLORES_GRAFICO[i % COLORES_GRAFICO.length]}
            />
          ))}
        </Pie>
        <Tooltip
          formatter={(v: number | string) => [`${v}`, 'Cantidad']}
          contentStyle={{ fontSize: 12, borderRadius: 8 }}
        />
      </PieChart>
    </ResponsiveContainer>
  );
}

/** Serie temporal multi-línea (uso diario). */
export function GraficoLineas({
  datos,
  series,
  altura = 300,
}: {
  datos: Record<string, string | number>[];
  series: { clave: string; etiqueta: string }[];
  altura?: number;
}) {
  return (
    <ResponsiveContainer width="100%" height={altura}>
      <LineChart data={datos} margin={{ top: 8, right: 12, bottom: 4, left: -18 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
        <XAxis dataKey="dia" tick={{ fontSize: 11 }} stroke="#94a3b8" />
        <YAxis tick={{ fontSize: 11 }} stroke="#94a3b8" allowDecimals={false} />
        <Tooltip contentStyle={{ fontSize: 12, borderRadius: 8 }} />
        <Legend wrapperStyle={{ fontSize: 12 }} />
        {series.map((s, i) => (
          <Line
            key={s.clave}
            type="monotone"
            dataKey={s.clave}
            name={s.etiqueta}
            stroke={COLORES_GRAFICO[i % COLORES_GRAFICO.length]}
            strokeWidth={2}
            dot={false}
          />
        ))}
      </LineChart>
    </ResponsiveContainer>
  );
}

/** Barras horizontales (ranking: países, versiones, aspectos). */
export function GraficoBarras({
  datos,
  altura = 280,
}: {
  datos: Dato[];
  altura?: number;
}) {
  if (!datos.length) {
    return (
      <p className="py-10 text-center text-sm text-slate-400">Sin datos.</p>
    );
  }
  return (
    <ResponsiveContainer width="100%" height={altura}>
      <BarChart
        data={datos}
        layout="vertical"
        margin={{ top: 4, right: 16, bottom: 4, left: 8 }}
      >
        <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" horizontal={false} />
        <XAxis type="number" tick={{ fontSize: 11 }} allowDecimals={false} />
        <YAxis
          type="category"
          dataKey="nombre"
          tick={{ fontSize: 11 }}
          width={130}
        />
        <Tooltip contentStyle={{ fontSize: 12, borderRadius: 8 }} />
        <Bar dataKey="valor" radius={[0, 6, 6, 0]}>
          {datos.map((_, i) => (
            <Cell key={i} fill={COLORES_GRAFICO[i % COLORES_GRAFICO.length]} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}
