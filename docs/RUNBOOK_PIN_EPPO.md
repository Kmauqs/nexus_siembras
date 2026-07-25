# Runbook — Renovación del certificate pinning de EPPO
**(revisión de código 2026-07-20, hallazgo #5)**

## Síntoma

La integración EPPO deja de funcionar **solo en Android** (Windows sigue
OK) con:

```
CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate
```

o el mensaje en pantalla `TLS rechazado por pinning → host=... sha256=...`.

Causa: `api.eppo.int` rotó su certificado y el fingerprint anclado en
`_eppoPins` (`lib/services/eppo_client.dart`) quedó obsoleto.

## Contexto de los pins actuales

| Pin | Qué es | Vigencia esperada |
|-----|--------|-------------------|
| `7f05c01b…` | Certificado HOJA de api.eppo.int | Meses (rota frecuente) |
| `6542d176…` | Intermedio "Sectigo Public Server Authentication CA OV R36" | ~2036 |

En Android la validación se corta en el **intermedio** (falta la raíz
Sectigo R46 en muchos dispositivos), así que mientras EPPO siga usando la
misma CA intermedia, la rotación de la hoja NO rompe nada. El caso que
requiere acción es que EPPO cambie de CA o de intermedio.

## Procedimiento (5 minutos)

1. Desde una **red de confianza** (no WiFi público), en la raíz del
   proyecto:

   ```powershell
   dart run tool/eppo_fingerprint.dart
   ```

2. Copiar el `SHA-256` impreso y añadirlo a `_eppoPins` en
   `lib/services/eppo_client.dart` (mantener el intermedio).
   Alternativa sin PC: el mensaje de error en pantalla del teléfono ya
   incluye el `sha256=` exacto a añadir.

3. Compilar, probar "Verificar estado del servicio" (onboarding o
   Configuración) en Android, y publicar release.

## Checklist de cada release (prevención)

- [ ] `dart run tool/eppo_fingerprint.dart` y comparar con `_eppoPins`.
- [ ] Si difiere la hoja: actualizarla (el intermedio suele bastar, pero
      mantener la hoja al día da defensa en profundidad).
- [ ] Probar la verificación EPPO en un dispositivo Android real.
