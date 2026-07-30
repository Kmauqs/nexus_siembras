import 'package:flutter/material.dart';
import '../../data/database/database.dart' as drift;

/// Grupo del listado de patologías. El `codigo` es el valor que se guarda en
/// `patologias.tipo` (clasificación automática) y en `patologias.tipoManual`
/// (reclasificación del usuario).
class GrupoPatologia {
  const GrupoPatologia({
    required this.codigo,
    required this.titulo,
    required this.etiqueta,
    required this.icono,
  });

  final String codigo;

  /// Encabezado del grupo en el listado (con emoji).
  final String titulo;

  /// Nombre en singular para referirse al grupo dentro de una frase.
  final String etiqueta;

  final IconData icono;
}

/// Grupos en el orden en que se muestran. Los tipos que no coincidan con
/// ningún código caen en `otra`.
const gruposPatologias = <GrupoPatologia>[
  GrupoPatologia(
      codigo: 'abiotica',
      titulo: '🌡️  Abióticas',
      etiqueta: 'Abiótica',
      icono: Icons.thermostat),
  GrupoPatologia(
      codigo: 'hongo',
      titulo: '🍄 Hongos',
      etiqueta: 'Hongo',
      icono: Icons.blur_on),
  GrupoPatologia(
      codigo: 'bacteria',
      titulo: '🦠 Bacterias',
      etiqueta: 'Bacteria',
      icono: Icons.circle_outlined),
  GrupoPatologia(
      codigo: 'virus',
      titulo: '🧬 Virus',
      etiqueta: 'Virus',
      icono: Icons.polyline),
  GrupoPatologia(
      codigo: 'plaga',
      titulo: '🐛 Plagas',
      etiqueta: 'Plaga',
      icono: Icons.bug_report),
  GrupoPatologia(
      codigo: 'nutricional',
      titulo: '🌱 Deficiencias nutricionales',
      etiqueta: 'Deficiencia nutricional',
      icono: Icons.grass),
  GrupoPatologia(
      codigo: 'otra',
      titulo: '❓ Otras / sin clasificar',
      etiqueta: 'Sin clasificar',
      icono: Icons.help_outline),
];

const grupoOtras = 'otra';

/// Normaliza un tipo al código de un grupo existente; los desconocidos y los
/// vacíos van a `otra`.
String codigoGrupo(String? tipo) {
  final t = (tipo ?? '').trim().toLowerCase();
  for (final g in gruposPatologias) {
    if (g.codigo == t) return g.codigo;
  }
  return grupoOtras;
}

GrupoPatologia grupoPorCodigo(String codigo) => gruposPatologias.firstWhere(
      (g) => g.codigo == codigo,
      orElse: () => gruposPatologias.last,
    );

/// Grupo en el que se lista la patología: manda la reclasificación manual
/// del usuario y, si no hay, la clasificación automática del catálogo.
String grupoEfectivo(drift.Patologia p) =>
    codigoGrupo(reclasificadaManualmente(p) ? p.tipoManual : p.tipo);

/// Grupo que le correspondería por la clasificación automática, ignorando
/// cualquier reclasificación manual.
String grupoAutomatico(drift.Patologia p) => codigoGrupo(p.tipo);

bool reclasificadaManualmente(drift.Patologia p) =>
    (p.tipoManual ?? '').trim().isNotEmpty;
