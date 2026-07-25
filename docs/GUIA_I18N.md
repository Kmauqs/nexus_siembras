# Guía de internacionalización (i18n) — NEXUS Siembras
**Fase B4 · 2026-07-20**

## Cómo funciona

No se usa `gen_l10n` (su chequeo de permisos falla en Windows y bloqueaba
el build). En su lugar, `lib/core/i18n/app_localizations.dart` lee los
mismos archivos ARB **en runtime** desde `lib/l10n/*.arb`, declarados como
assets en `pubspec.yaml`.

- Idiomas: **es** (base), **en**, **pt** — 115 claves con paridad total.
- Cambio de idioma: `localeProvider` (Configuración y onboarding). Al
  cambiarlo, `MaterialApp` reconstruye y los textos se actualizan solos.
- Si una clave falta en el idioma activo → cae a español. Si tampoco
  existe → devuelve la clave literal (visible en QA, nunca rompe la UI).

## Uso en un widget

```dart
import '../../core/i18n/app_localizations.dart';

Text(context.t('menuCrops'))                        // 'Ver cultivos'
Text(context.t('wizardStepOf', {'n': '3', 'total': '10'}))
```

Con placeholders, en el ARB se escriben entre llaves: `"Paso {n} de {total}"`.

## Agregar una clave nueva

1. Añadirla **en los tres** `lib/l10n/{es,en,pt}.arb` (mismo nombre).
2. Si lleva placeholders, declararlos con la entrada de metadatos:

```json
"wizardStepOf": "Paso {n} de {total}",
"@wizardStepOf": {"placeholders": {"n": {"type": "String"}, "total": {"type": "String"}}}
```

3. Usarla con `context.t('claveNueva')`.

Convención de nombres: prefijo por área — `menu*`, `dash*`, `crop*`,
`cfg*`, `wizard*`, `reports*`, `msg*`, `empty*`; y sin prefijo para las
acciones comunes (`save`, `cancel`, `delete`, `share`…).

## Verificar paridad entre idiomas

```powershell
python -c "import json;s=[set(k for k in json.load(open(f'lib/l10n/{c}.arb',encoding='utf-8')) if not k.startswith('@')) for c in ['es','en','pt']];print('OK' if s[0]==s[1]==s[2] else s[0]^s[1]|s[0]^s[2])"
```

## Estado de la migración

| Área | Estado |
|------|--------|
| Infraestructura (cargador, delegate, fallback, `context.t`) | ✅ Completa |
| ARB es/en/pt (115 claves, paridad verificada) | ✅ Completa |
| Menú lateral + tooltips + badge de sync (`AppShell`, visible en toda la app) | ✅ Migrado |
| Resto de pantallas (~700 strings) | ⏳ Pendiente, incremental |

**Cómo continuar:** migrar pantalla por pantalla, empezando por las de
mayor uso (Dashboard, Cultivos, Inventario). Para cada una: extraer los
literales a los 3 ARB con el prefijo del área y reemplazar por
`context.t(...)`. No hace falta migrar todo de una vez — las pantallas sin
migrar siguen mostrando su texto en español, sin errores.

Los textos de **datos** (nombres de plantas, patologías, tratamientos,
unidades) NO se traducen aquí: viven en la base de datos y en los assets
de catálogo, y su localización sería un trabajo aparte.
