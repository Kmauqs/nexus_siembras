import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_siembras/core/widgets/acceso_denegado.dart';
import 'package:nexus_siembras/core/widgets/status_dot.dart';
import 'package:nexus_siembras/data/repositories/cultivo_repository.dart';

void main() {
  group('StatusDot', () {
    testWidgets('pinta el color de estado y responde al tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatusDot(
            estado: EstadoCultivo.rojo,
            tooltip: 'Alerta',
            onTap: () => taps++,
          ),
        ),
      ));

      expect(find.byType(StatusDot), findsOneWidget);
      await tester.tap(find.byType(StatusDot));
      expect(taps, 1);

      final dot = tester.widget<StatusDot>(find.byType(StatusDot));
      expect(dot.estado, EstadoCultivo.rojo);
      expect(dot.color, isNot(equals(StatusDot(
        estado: EstadoCultivo.verde,
      ).color)));
    });

    testWidgets('sin onTap no envuelve InkWell interactivo', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: StatusDot(estado: EstadoCultivo.verde),
        ),
      ));
      expect(find.byType(InkWell), findsNothing);
    });
  });

  group('AccesoDenegado', () {
    testWidgets('muestra título Solo lectura y el mensaje', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: AccesoDenegado(
            mensaje: 'No puedes editar este predio.',
          ),
        ),
      ));

      expect(find.text('Solo lectura'), findsOneWidget);
      expect(find.text('No puedes editar este predio.'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });
  });
}
