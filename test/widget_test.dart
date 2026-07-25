// Test placeholder (auditoría 2026-07-19): el test plantilla original
// referenciaba `MyApp`, clase inexistente en este proyecto, y rompía
// `flutter test`. Se reemplaza por pruebas unitarias mínimas de lógica
// pura hasta que existan tests de widgets reales.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_siembras/services/eppo_client.dart';

void main() {
  group('inferirTipoTaxonomico', () {
    test('detecta virus', () {
      expect(inferirTipoTaxonomico('Tomato mosaic virus'), 'virus');
    });
    test('detecta bacterias por género', () {
      expect(inferirTipoTaxonomico('Xanthomonas campestris'), 'bacteria');
    });
    test('null cuando no hay nombre', () {
      expect(inferirTipoTaxonomico(null), isNull);
    });
  });
}
