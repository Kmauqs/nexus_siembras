// Herramienta de auditoría S2: imprime el fingerprint SHA-256 del
// certificado TLS que presenta api.eppo.int, para copiarlo en
// `_eppoPins` de lib/services/eppo_client.dart.
//
// Uso (desde la raíz del proyecto, con conexión a internet):
//     dart run tool/eppo_fingerprint.dart
//
// IMPORTANTE: ejecutar solo desde una red de confianza (no WiFi público),
// porque el fingerprint que se imprime es el que se va a anclar.

import 'dart:io';
import 'package:crypto/crypto.dart';

Future<void> main() async {
  const host = 'api.eppo.int';
  try {
    final socket = await SecureSocket.connect(
      host,
      443,
      timeout: const Duration(seconds: 20),
      onBadCertificate: (_) => true, // solo para inspección, no para tráfico
    );
    final cert = socket.peerCertificate;
    socket.destroy();
    if (cert == null) {
      stderr.writeln('No se recibió certificado de $host.');
      exitCode = 1;
      return;
    }
    stdout.writeln('Host:    $host');
    stdout.writeln('Sujeto:  ${cert.subject}');
    stdout.writeln('Emisor:  ${cert.issuer}');
    stdout.writeln('Válido:  ${cert.startValidity} → ${cert.endValidity}');
    stdout.writeln('SHA-256: ${sha256.convert(cert.der)}');
    stdout.writeln('');
    stdout.writeln('Copie el valor SHA-256 en _eppoPins '
        '(lib/services/eppo_client.dart).');
  } catch (e) {
    stderr.writeln('Error conectando a $host: $e');
    exitCode = 1;
  }
}
