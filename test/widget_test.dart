// Test placeholder (auditoría 2026-07-19): el test plantilla original
// referenciaba `MyApp`, clase inexistente en este proyecto, y rompía
// `flutter test`. Se reemplaza por pruebas unitarias mínimas de lógica
// pura hasta que existan tests de widgets reales.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_siembras/core/widgets/duracion_field.dart';
import 'package:nexus_siembras/data/database/database.dart' as drift;
import 'package:nexus_siembras/features/pathologies/agrupacion_patologias.dart';
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

  group('DuracionController', () {
    test('convierte a días según la unidad elegida', () {
      final c = DuracionController();
      c.texto.text = '3';
      expect(c.dias, 3);
      c.unidad = UnidadTiempo.semanas;
      expect(c.dias, 21);
      c.unidad = UnidadTiempo.meses;
      expect(c.dias, 90);
      c.unidad = UnidadTiempo.anios;
      expect(c.dias, 1095);
      c.dispose();
    });

    test('acepta decimales y coma decimal', () {
      final c = DuracionController(unidad: UnidadTiempo.meses);
      c.texto.text = '1,5';
      expect(c.dias, 45);
      c.dispose();
    });

    test('vacío o no numérico devuelve null', () {
      final c = DuracionController();
      expect(c.dias, isNull);
      expect(c.vacio, isTrue);
      c.texto.text = ',';
      expect(c.dias, isNull);
      c.dispose();
    });

    test('cero es válido (abono al sembrar)', () {
      final c = DuracionController(dias: 0);
      expect(c.dias, 0);
      expect(c.unidad, UnidadTiempo.dias);
      c.dispose();
    });

    test('precarga eligiendo la unidad más legible', () {
      final casos = <int, (String, UnidadTiempo)>{
        1095: ('3', UnidadTiempo.anios),
        90: ('3', UnidadTiempo.meses),
        14: ('2', UnidadTiempo.semanas),
        65: ('65', UnidadTiempo.dias),
      };
      for (final e in casos.entries) {
        final c = DuracionController(dias: e.key);
        expect(c.texto.text, e.value.$1, reason: 'días=${e.key}');
        expect(c.unidad, e.value.$2, reason: 'días=${e.key}');
        expect(c.dias, e.key, reason: 'round-trip días=${e.key}');
        c.dispose();
      }
    });
  });

  group('DuracionField', () {
    // Dos campos densos en una fila es la disposición más estrecha que usa la
    // app (variedades, agregar cultivo): valida que el sufijo con el selector
    // de unidad no desborde.
    Widget host(DuracionController c) => MaterialApp(
          home: Scaffold(
            body: Row(children: [
              Expanded(
                child: DuracionField(
                    controller: c, label: 'Esperanza de vida', dense: true),
              ),
              const Expanded(child: SizedBox()),
            ]),
          ),
        );

    testWidgets('muestra la abreviatura de la unidad precargada',
        (tester) async {
      final c = DuracionController(dias: 1095);
      await tester.pumpWidget(host(c));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('año'), findsOneWidget);
      c.dispose();
    });

    testWidgets('al elegir otra unidad convierte y muestra la equivalencia',
        (tester) async {
      final c = DuracionController();
      await tester.pumpWidget(host(c));
      await tester.enterText(find.byType(TextField), '2');

      await tester.tap(find.text('d'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Meses').last);
      await tester.pumpAndSettle();

      expect(c.dias, 60);
      expect(find.text('= 60 días'), findsOneWidget);
      c.dispose();
    });
  });

  group('Agrupación de patologías', () {
    drift.Patologia pat({String? tipo, String? tipoManual}) => drift.Patologia(
          id: 1,
          nombreComun: 'Hormiga arriera',
          nombreCientifico: 'Atta cephalotes',
          tipo: tipo,
          tipoManual: tipoManual,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('sin reclasificar usa el tipo del catálogo', () {
      final p = pat(tipo: 'plaga');
      expect(grupoEfectivo(p), 'plaga');
      expect(reclasificadaManualmente(p), isFalse);
    });

    test('la reclasificación manual manda sobre el tipo automático', () {
      final p = pat(tipo: 'plaga', tipoManual: 'abiotica');
      expect(grupoEfectivo(p), 'abiotica');
      expect(grupoAutomatico(p), 'plaga');
      expect(reclasificadaManualmente(p), isTrue);
    });

    test('tipoManual vacío se ignora', () {
      final p = pat(tipo: 'hongo', tipoManual: '  ');
      expect(grupoEfectivo(p), 'hongo');
      expect(reclasificadaManualmente(p), isFalse);
    });

    test('tipos nulos o desconocidos caen en «otra»', () {
      expect(grupoEfectivo(pat()), grupoOtras);
      expect(grupoEfectivo(pat(tipo: 'oomiceto')), grupoOtras);
    });

    test('normaliza mayúsculas y espacios', () {
      expect(grupoEfectivo(pat(tipo: ' Virus ')), 'virus');
    });

    test('cada grupo tiene código único y resoluble', () {
      final codigos = gruposPatologias.map((g) => g.codigo).toList();
      expect(codigos.toSet().length, codigos.length);
      for (final c in codigos) {
        expect(grupoPorCodigo(c).codigo, c);
      }
    });
  });
}
