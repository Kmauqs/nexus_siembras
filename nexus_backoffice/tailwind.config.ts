import type { Config } from 'tailwindcss';

// Paleta tomada de la app Flutter (core/theme/themes.dart y los PDF):
//   verde principal  #1B7A3E   · verde oscuro  #0F5132
//   alerta           #B91C1C   · atención      #D97706
const config: Config = {
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        nexus: {
          50: '#E8F5EC',
          100: '#C6E7D2',
          200: '#9FD7B4',
          300: '#74C795',
          400: '#4FB87E',
          500: '#2E9E63',
          600: '#1B7A3E', // primario de la app
          700: '#156935',
          800: '#0F5132', // encabezados / PDF
          900: '#0A3D24',
        },
        alerta: '#B91C1C',
        atencion: '#D97706',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'Segoe UI', 'sans-serif'],
      },
      boxShadow: {
        card: '0 1px 3px rgba(15,81,50,0.08), 0 1px 2px rgba(15,81,50,0.06)',
      },
    },
  },
  plugins: [],
};

export default config;
