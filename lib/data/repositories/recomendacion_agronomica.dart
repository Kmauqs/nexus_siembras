// Motor de recomendaciones agronómicas
// Evalúa análisis de suelo + condiciones edafoclimáticas + requerimientos
// de la planta y produce alertas y sugerencias de dosificación.

import 'dart:convert';
import '../database/database.dart';

enum NivelAlerta { info, atencion, critico }

class AlertaAgronomica {
  final NivelAlerta nivel;
  final String titulo;
  final String detalle;
  const AlertaAgronomica(this.nivel, this.titulo, this.detalle);
}

class DosisRecomendada {
  final double? nKgHa;
  final double? pKgHa;
  final double? kKgHa;
  final String? notaN;
  final String? notaP;
  final String? notaK;
  const DosisRecomendada({
    this.nKgHa,
    this.pKgHa,
    this.kKgHa,
    this.notaN,
    this.notaP,
    this.notaK,
  });
}

class RecomendacionAgronomica {
  final List<AlertaAgronomica> alertas;
  final DosisRecomendada dosis;
  final AnalisisSueloData? analisis;
  final CondicionesPredioData? condiciones;
  final Planta planta;
  final String? resumen;
  const RecomendacionAgronomica({
    required this.alertas,
    required this.dosis,
    required this.planta,
    this.analisis,
    this.condiciones,
    this.resumen,
  });

  bool get tieneAlertasCriticas =>
      alertas.any((a) => a.nivel == NivelAlerta.critico);

  int get nAlertasAtencion =>
      alertas.where((a) => a.nivel == NivelAlerta.atencion).length;
}

class MotorRecomendaciones {
  /// Genera la recomendación combinando planta + análisis + condiciones.
  /// `analisis` y `condiciones` pueden ser null (se emiten alertas informativas).
  static RecomendacionAgronomica evaluar({
    required Planta planta,
    AnalisisSueloData? analisis,
    CondicionesPredioData? condiciones,
    double? areaHa,
  }) {
    final alertas = <AlertaAgronomica>[];

    // ============ CONDICIONES CLIMÁTICAS ============
    if (condiciones == null) {
      alertas.add(const AlertaAgronomica(
        NivelAlerta.info,
        'Sin datos edafoclimáticos del predio',
        'Registre altitud, temperatura y precipitación en Configuración → Condiciones del predio para obtener recomendaciones ajustadas.',
      ));
    } else {
      // Altitud
      final alt = condiciones.altitudMsnm;
      if (alt != null && planta.altitudMinM != null && planta.altitudMaxM != null) {
        if (alt < planta.altitudMinM!) {
          alertas.add(AlertaAgronomica(
            NivelAlerta.atencion,
            'Altitud por debajo del rango óptimo',
            'El predio está a ${alt.toStringAsFixed(0)} msnm; '
                '${planta.nombreComun} requiere ${planta.altitudMinM!.toStringAsFixed(0)}–'
                '${planta.altitudMaxM!.toStringAsFixed(0)} msnm.',
          ));
        } else if (alt > planta.altitudMaxM!) {
          alertas.add(AlertaAgronomica(
            NivelAlerta.atencion,
            'Altitud por encima del rango óptimo',
            'El predio está a ${alt.toStringAsFixed(0)} msnm; '
                '${planta.nombreComun} requiere ${planta.altitudMinM!.toStringAsFixed(0)}–'
                '${planta.altitudMaxM!.toStringAsFixed(0)} msnm.',
          ));
        }
      }
      // Temperatura media
      final temp = condiciones.tempMediaC;
      if (temp != null && planta.tempMinC != null && planta.tempMaxC != null) {
        if (temp < planta.tempMinC! || temp > planta.tempMaxC!) {
          alertas.add(AlertaAgronomica(
            NivelAlerta.atencion,
            'Temperatura fuera del rango óptimo',
            'Media del predio: ${temp.toStringAsFixed(1)} °C; '
                'rango óptimo: ${planta.tempMinC!.toStringAsFixed(0)}–'
                '${planta.tempMaxC!.toStringAsFixed(0)} °C.',
          ));
        }
      }
      // Precipitación
      final precip = condiciones.precipitacionAnualMm;
      if (precip != null && planta.precipMinMm != null && planta.precipMaxMm != null) {
        if (precip < planta.precipMinMm!) {
          alertas.add(AlertaAgronomica(
            NivelAlerta.atencion,
            'Precipitación deficitaria',
            '${precip.toStringAsFixed(0)} mm/año; '
                '${planta.nombreComun} requiere al menos ${planta.precipMinMm!.toStringAsFixed(0)} mm/año. '
                'Prevea riego suplementario.',
          ));
        } else if (precip > planta.precipMaxMm!) {
          alertas.add(AlertaAgronomica(
            NivelAlerta.atencion,
            'Precipitación excesiva',
            '${precip.toStringAsFixed(0)} mm/año; el óptimo va hasta '
                '${planta.precipMaxMm!.toStringAsFixed(0)} mm/año. '
                'Considere drenaje o coberturas.',
          ));
        }
      }
    }

    // ============ ANÁLISIS DE SUELO ============
    if (analisis == null) {
      alertas.add(const AlertaAgronomica(
        NivelAlerta.info,
        'Sin análisis de suelo registrado',
        'Registre un análisis físico-químico para obtener recomendaciones de abono precisas basadas en déficit real.',
      ));
    } else {
      // pH
      if (analisis.ph != null &&
          planta.phMin != null &&
          planta.phMax != null) {
        if (analisis.ph! < planta.phMin!) {
          alertas.add(AlertaAgronomica(
            NivelAlerta.critico,
            'pH ácido para el cultivo',
            'pH del suelo: ${analisis.ph!.toStringAsFixed(1)}; '
                'requerido: ${planta.phMin!.toStringAsFixed(1)}–'
                '${planta.phMax!.toStringAsFixed(1)}. '
                'Aplique cal dolomítica (0.5–1.5 t/ha) para subir pH.',
          ));
        } else if (analisis.ph! > planta.phMax!) {
          alertas.add(AlertaAgronomica(
            NivelAlerta.critico,
            'pH alcalino para el cultivo',
            'pH del suelo: ${analisis.ph!.toStringAsFixed(1)}; '
                'requerido: ${planta.phMin!.toStringAsFixed(1)}–'
                '${planta.phMax!.toStringAsFixed(1)}. '
                'Considere azufre elemental o materia orgánica ácida.',
          ));
        }
      }
      // Materia orgánica
      if (analisis.materiaOrganicaPct != null &&
          planta.materiaOrganicaMinPct != null &&
          analisis.materiaOrganicaPct! < planta.materiaOrganicaMinPct!) {
        alertas.add(AlertaAgronomica(
          NivelAlerta.atencion,
          'Materia orgánica baja',
          'MO actual: ${analisis.materiaOrganicaPct!.toStringAsFixed(1)}%; '
              'mínimo recomendado: ${planta.materiaOrganicaMinPct!.toStringAsFixed(1)}%. '
              'Incorpore compost, gallinaza (2–4 t/ha) o abonos verdes.',
        ));
      }
      // Textura
      final texturas = <String>[];
      if (planta.texturasRecomendadasJson != null) {
        try {
          texturas.addAll((jsonDecode(planta.texturasRecomendadasJson!)
                  as List<dynamic>)
              .cast<String>());
        } catch (_) {}
      }
      if (analisis.textura != null &&
          texturas.isNotEmpty &&
          !texturas.contains(analisis.textura)) {
        alertas.add(AlertaAgronomica(
          NivelAlerta.info,
          'Textura no óptima',
          'Textura del suelo: "${analisis.textura}". '
              'Recomendadas: ${texturas.join(", ")}. '
              'Ajuste manejo hídrico y aporte MO para mejorar estructura.',
        ));
      }
      // Conductividad (salinidad)
      if (analisis.conductividadMsCm != null &&
          analisis.conductividadMsCm! > 2.0) {
        alertas.add(AlertaAgronomica(
          NivelAlerta.atencion,
          'Suelo con salinidad elevada',
          'Conductividad: ${analisis.conductividadMsCm!.toStringAsFixed(2)} mS/cm '
              '(>2 mS/cm indica salinidad). Lave el perfil con riego abundante y evite fertilizantes salinos.',
        ));
      }
    }

    // ============ DOSIS DE ABONO (déficit N-P-K) ============
    // Fórmula simplificada: dosis = requerimiento - (N_ppm × 3.2 / 1000 × factor)
    // Simplificamos: si hay análisis con NPK en ppm, estimamos disponibilidad
    // aproximada asumiendo 20 cm profundidad y 1.3 g/cm³ densidad → 2.6M kg suelo/ha.
    // 1 ppm ≈ 2.6 kg/ha del nutriente.
    final ha = areaHa ?? 1.0;
    double? dosisN, dosisP, dosisK;
    String? notaN, notaP, notaK;

    double disp(double ppm) => ppm * 2.6; // kg/ha aprox

    if (planta.requerimientoNKgHa != null) {
      final req = planta.requerimientoNKgHa!;
      final dispN = analisis?.nPpm == null ? 0.0 : disp(analisis!.nPpm!);
      final deficit = (req - dispN).clamp(0, req).toDouble();
      dosisN = deficit;
      notaN = analisis?.nPpm == null
          ? 'Sin análisis: aplique dosis completa (${req.toStringAsFixed(0)} kg/ha).'
          : 'Suelo aporta ~${dispN.toStringAsFixed(0)} kg/ha; requerimiento: ${req.toStringAsFixed(0)} kg/ha.';
    }
    if (planta.requerimientoPKgHa != null) {
      final req = planta.requerimientoPKgHa!;
      final dispP = analisis?.pPpm == null ? 0.0 : disp(analisis!.pPpm!);
      final deficit = (req - dispP).clamp(0, req).toDouble();
      dosisP = deficit;
      notaP = analisis?.pPpm == null
          ? 'Sin análisis: aplique dosis completa (${req.toStringAsFixed(0)} kg/ha).'
          : 'Suelo aporta ~${dispP.toStringAsFixed(0)} kg/ha; requerimiento: ${req.toStringAsFixed(0)} kg/ha.';
    }
    if (planta.requerimientoKKgHa != null) {
      final req = planta.requerimientoKKgHa!;
      final dispK = analisis?.kPpm == null ? 0.0 : disp(analisis!.kPpm!);
      final deficit = (req - dispK).clamp(0, req).toDouble();
      dosisK = deficit;
      notaK = analisis?.kPpm == null
          ? 'Sin análisis: aplique dosis completa (${req.toStringAsFixed(0)} kg/ha).'
          : 'Suelo aporta ~${dispK.toStringAsFixed(0)} kg/ha; requerimiento: ${req.toStringAsFixed(0)} kg/ha.';
    }

    final dosis = DosisRecomendada(
      nKgHa: dosisN,
      pKgHa: dosisP,
      kKgHa: dosisK,
      notaN: notaN,
      notaP: notaP,
      notaK: notaK,
    );

    // Resumen textual corto
    final resumen = _generarResumen(planta, alertas, dosis, ha);

    return RecomendacionAgronomica(
      alertas: alertas,
      dosis: dosis,
      planta: planta,
      analisis: analisis,
      condiciones: condiciones,
      resumen: resumen,
    );
  }

  static String _generarResumen(
      Planta planta,
      List<AlertaAgronomica> alertas,
      DosisRecomendada dosis,
      double areaHa) {
    final buf = StringBuffer();
    final criticas = alertas.where((a) => a.nivel == NivelAlerta.critico).length;
    final atenciones = alertas.where((a) => a.nivel == NivelAlerta.atencion).length;
    if (criticas > 0) {
      buf.write('$criticas alerta(s) crítica(s). ');
    }
    if (atenciones > 0) {
      buf.write('$atenciones alerta(s) de atención. ');
    }
    final n = dosis.nKgHa, p = dosis.pKgHa, k = dosis.kKgHa;
    if (n != null || p != null || k != null) {
      buf.write('Dosis sugerida: ');
      final parts = <String>[];
      if (n != null) parts.add('N ${n.toStringAsFixed(0)} kg/ha');
      if (p != null) parts.add('P ${p.toStringAsFixed(0)} kg/ha');
      if (k != null) parts.add('K ${k.toStringAsFixed(0)} kg/ha');
      buf.write(parts.join(' · '));
      buf.write('.');
    }
    return buf.toString().trim();
  }
}
