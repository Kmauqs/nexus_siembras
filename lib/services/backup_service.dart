// Servicio de backup y restore local para el predio activo.
//
// Formato: JSON con secciones por tabla. Solo se exportan datos
// operativos (cultivos, tareas, inventario, etc.). Los catálogos
// globales (plantas, patologías, geografía, unidades) NO se exportan
// porque se rehidratan por seed en cada instalación limpia.
//
// Estructura del archivo:
// {
//   "schema": 5,
//   "generatedAt": "ISO 8601",
//   "predio": {...},
//   "lotes": [...],
//   "cultivos": [...],
//   "eventos": [...],
//   "tareas": [...],
//   "inventario": [...],
//   "compras": [...],
//   "proveedores": [...],
//   "analisisSuelo": [...],
//   "condicionesPredio": {...},
//   "cultivoPatologias": [...]
// }

import 'dart:convert';
import 'package:drift/drift.dart';
import '../data/database/database.dart';

class BackupService {
  BackupService(this.db);
  final AppDatabase db;

  /// Versión actual del formato de backup. Coincide con schemaVersion.
  static const int currentSchema = 5;

  /// Exporta el predio activo como String JSON con indentación.
  Future<String> exportarPredio(int predioId) async {
    final predio = await (db.select(db.predios)
          ..where((p) => p.id.equals(predioId)))
        .getSingleOrNull();
    if (predio == null) {
      throw StateError('Predio $predioId no encontrado');
    }

    final lotes = await (db.select(db.lotes)
          ..where((l) => l.predioId.equals(predioId)))
        .get();
    final cultivos = await (db.select(db.cultivos)
          ..where((c) => c.predioId.equals(predioId)))
        .get();
    final cultivoIds = cultivos.map((c) => c.id).toList();

    final eventos = cultivoIds.isEmpty
        ? <EventosCultivoData>[]
        : await (db.select(db.eventosCultivo)
              ..where((e) => e.cultivoId.isIn(cultivoIds)))
            .get();
    final tareas = cultivoIds.isEmpty
        ? <TareasCompletada>[]
        : await (db.select(db.tareasCompletadas)
              ..where((t) => t.cultivoId.isIn(cultivoIds)))
            .get();
    final cultivoPatologias = cultivoIds.isEmpty
        ? <CultivoPatologia>[]
        : await (db.select(db.cultivoPatologias)
              ..where((p) => p.cultivoId.isIn(cultivoIds)))
            .get();

    final inventario = await (db.select(db.inventarios)
          ..where((i) => i.predioId.equals(predioId)))
        .get();
    final compras = await (db.select(db.compras)
          ..where((c) => c.predioId.equals(predioId)))
        .get();
    // Proveedores: todos, para que las FK se puedan resolver al importar.
    final proveedores = await (db.select(db.proveedores)
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final analisis = await (db.select(db.analisisSuelo)
          ..where((a) => a.predioId.equals(predioId)))
        .get();
    final condiciones = await (db.select(db.condicionesPredio)
          ..where((c) => c.predioId.equals(predioId))
          ..limit(1))
        .getSingleOrNull();

    final data = <String, dynamic>{
      'schema': currentSchema,
      'generatedAt': DateTime.now().toIso8601String(),
      'predio': _predioToJson(predio),
      'lotes': lotes.map(_loteToJson).toList(),
      'cultivos': cultivos.map(_cultivoToJson).toList(),
      'eventos': eventos.map(_eventoToJson).toList(),
      'tareas': tareas.map(_tareaToJson).toList(),
      'inventario': inventario.map(_inventarioToJson).toList(),
      'compras': compras.map(_compraToJson).toList(),
      'proveedores': proveedores.map(_provToJson).toList(),
      'analisisSuelo': analisis.map(_analisisToJson).toList(),
      'condicionesPredio':
          condiciones == null ? null : _condicionesToJson(condiciones),
      'cultivoPatologias':
          cultivoPatologias.map(_cultivoPatologiaToJson).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Importa un JSON previamente exportado.
  /// Si [reemplazar] es true, borra todo lo del predio destino antes.
  /// Si es false, agrega (los IDs se regeneran, no hay conflicto de claves).
  Future<ImportResult> importarPredio(
    String jsonStr, {
    required bool reemplazar,
  }) async {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('JSON inválido: $e');
    }
    final schemaVer = data['schema'] as int?;
    if (schemaVer == null || schemaVer > currentSchema) {
      throw FormatException(
          'Versión de backup no soportada: $schemaVer (esperada ≤ $currentSchema)');
    }
    final predioJson = data['predio'] as Map<String, dynamic>?;
    if (predioJson == null) throw const FormatException('Falta "predio"');

    return await db.transaction<ImportResult>(() async {
      // Crea el predio (siempre nuevo, ID autogenerado)
      final predioId = await db.into(db.predios).insert(PrediosCompanion.insert(
            nombre: predioJson['nombre'] as String,
            propietario: Value(predioJson['propietario'] as String?),
            paisId: Value(predioJson['paisId'] as int?),
            regionId: Value(predioJson['regionId'] as int?),
            municipioId: Value(predioJson['municipioId'] as int?),
            lat: Value((predioJson['lat'] as num?)?.toDouble()),
            lng: Value((predioJson['lng'] as num?)?.toDouble()),
            altM: Value((predioJson['altM'] as num?)?.toDouble()),
            notas: Value(predioJson['notas'] as String?),
          ));

      // Proveedores: solo importa los que no existen ya por nombre
      final provMap = <int, int>{};
      for (final p in (data['proveedores'] as List<dynamic>? ?? [])) {
        final row = p as Map<String, dynamic>;
        final nombre = row['nombre'] as String? ?? '';
        if (nombre.isEmpty) continue;
        final existente = await (db.select(db.proveedores)
              ..where((x) => x.nombre.equals(nombre))
              ..limit(1))
            .getSingleOrNull();
        final newId = existente?.id ??
            await db.into(db.proveedores).insert(
                ProveedoresCompanion.insert(
                    nombre: nombre,
                    nit: Value(row['nit'] as String?),
                    telefono: Value(row['telefono'] as String?),
                    email: Value(row['email'] as String?),
                    web: Value(row['web'] as String?),
                    direccion: Value(row['direccion'] as String?),
                    notas: Value(row['notas'] as String?)));
        provMap[row['id'] as int] = newId;
      }

      // Lotes
      final loteMap = <int, int>{};
      for (final l in (data['lotes'] as List<dynamic>? ?? [])) {
        final row = l as Map<String, dynamic>;
        final newId = await db.into(db.lotes).insert(LotesCompanion.insert(
              predioId: predioId,
              nombre: row['nombre'] as String,
              administrador: Value(row['administrador'] as String?),
              altitudMsnm: Value((row['altitudMsnm'] as num?)?.toDouble()),
              areaM2: Value((row['areaM2'] as num?)?.toDouble()),
              poligonoGeoJson: Value(row['poligonoGeoJson'] as String?),
              notas: Value(row['notas'] as String?),
            ));
        loteMap[row['id'] as int] = newId;
      }

      // Cultivos
      final cultivoMap = <int, int>{};
      for (final c in (data['cultivos'] as List<dynamic>? ?? [])) {
        final row = c as Map<String, dynamic>;
        final oldLoteId = row['loteId'] as int?;
        final newId =
            await db.into(db.cultivos).insert(CultivosCompanion.insert(
                  predioId: predioId,
                  plantaId: row['plantaId'] as int,
                  loteId: Value(oldLoteId == null ? null : loteMap[oldLoteId]),
                  nombreLote: Value(row['nombreLote'] as String?),
                  fechaSiembra:
                      DateTime.parse(row['fechaSiembra'] as String),
                  fechaCosechaEstimada: Value(
                      _parseNullableDate(row['fechaCosechaEstimada'])),
                  areaBaseM2:
                      Value((row['areaBaseM2'] as num?)?.toDouble()),
                  hhTotal: Value((row['hhTotal'] as num?)?.toDouble() ?? 0),
                  horaValor:
                      Value((row['horaValor'] as num?)?.toDouble()),
                  lat: Value((row['lat'] as num?)?.toDouble()),
                  lng: Value((row['lng'] as num?)?.toDouble()),
                  altM: Value((row['altM'] as num?)?.toDouble()),
                  finalizadoFecha:
                      Value(_parseNullableDate(row['finalizadoFecha'])),
                  notas: Value(row['notas'] as String?),
                ));
        cultivoMap[row['id'] as int] = newId;
      }

      // Eventos (referencian cultivos)
      var evCount = 0;
      for (final e in (data['eventos'] as List<dynamic>? ?? [])) {
        final row = e as Map<String, dynamic>;
        final newCultivoId = cultivoMap[row['cultivoId'] as int];
        if (newCultivoId == null) continue;
        await db.into(db.eventosCultivo).insert(EventosCultivoCompanion.insert(
              cultivoId: newCultivoId,
              tipo: row['tipo'] as String,
              fechaProgramada: Value(_parseNullableDate(row['fechaProgramada'])),
              fechaEjecutada: Value(_parseNullableDate(row['fechaEjecutada'])),
              descripcion: Value(row['descripcion'] as String?),
              notas: Value(row['notas'] as String?),
            ));
        evCount++;
      }

      // Tareas
      var tareaCount = 0;
      for (final t in (data['tareas'] as List<dynamic>? ?? [])) {
        final row = t as Map<String, dynamic>;
        final newCultivoId = cultivoMap[row['cultivoId'] as int];
        if (newCultivoId == null) continue;
        await db.into(db.tareasCompletadas).insert(
            TareasCompletadasCompanion.insert(
                cultivoId: newCultivoId,
                fecha: DateTime.parse(row['fecha'] as String),
                hh: Value((row['hh'] as num?)?.toDouble() ?? 0),
                actividadesJson:
                    row['actividadesJson'] as String? ?? '[]',
                insumosJson:
                    Value(row['insumosJson'] as String? ?? '[]'),
                notas: Value(row['notas'] as String?)));
        tareaCount++;
      }

      // Inventario
      for (final i in (data['inventario'] as List<dynamic>? ?? [])) {
        final row = i as Map<String, dynamic>;
        await db.into(db.inventarios).insert(InventariosCompanion.insert(
              predioId: predioId,
              fecha: DateTime.parse(row['fecha'] as String),
              descripcion: row['descripcion'] as String,
              codigo: Value(row['codigo'] as String?),
              fabricante: Value(row['fabricante'] as String?),
              cantidadBase: (row['cantidadBase'] as num).toDouble(),
              unidadBase: row['unidadBase'] as String,
              notas: Value(row['notas'] as String?),
            ));
      }

      // Compras
      for (final c in (data['compras'] as List<dynamic>? ?? [])) {
        final row = c as Map<String, dynamic>;
        final oldProvId = row['proveedorId'] as int?;
        await db.into(db.compras).insert(ComprasCompanion.insert(
              predioId: predioId,
              proveedorId:
                  Value(oldProvId == null ? null : provMap[oldProvId]),
              fecha: DateTime.parse(row['fecha'] as String),
              descripcion1: row['descripcion1'] as String,
              descripcion2: Value(row['descripcion2'] as String?),
              valorTotal: (row['valorTotal'] as num).toDouble(),
              cantidadBase: (row['cantidadBase'] as num).toDouble(),
              unidadBase: row['unidadBase'] as String,
              codigo: Value(row['codigo'] as String?),
              factura: Value(row['factura'] as String?),
              tipo: Value(row['tipo'] as String?),
              notas: Value(row['notas'] as String?),
            ));
      }

      // Análisis de suelo
      for (final a in (data['analisisSuelo'] as List<dynamic>? ?? [])) {
        final row = a as Map<String, dynamic>;
        await db.into(db.analisisSuelo).insert(AnalisisSueloCompanion.insert(
              predioId: predioId,
              fechaMuestreo: DateTime.parse(row['fechaMuestreo'] as String),
              lote: Value(row['lote'] as String?),
              laboratorio: Value(row['laboratorio'] as String?),
              profundidadCm:
                  Value((row['profundidadCm'] as num?)?.toDouble()),
              textura: Value(row['textura'] as String?),
              ph: Value((row['ph'] as num?)?.toDouble()),
              materiaOrganicaPct:
                  Value((row['materiaOrganicaPct'] as num?)?.toDouble()),
              nPpm: Value((row['nPpm'] as num?)?.toDouble()),
              pPpm: Value((row['pPpm'] as num?)?.toDouble()),
              kPpm: Value((row['kPpm'] as num?)?.toDouble()),
              caMeq: Value((row['caMeq'] as num?)?.toDouble()),
              mgMeq: Value((row['mgMeq'] as num?)?.toDouble()),
              naMeq: Value((row['naMeq'] as num?)?.toDouble()),
              cicMeq: Value((row['cicMeq'] as num?)?.toDouble()),
              conductividadMsCm:
                  Value((row['conductividadMsCm'] as num?)?.toDouble()),
              notas: Value(row['notas'] as String?),
            ));
      }

      // Condiciones edafoclim
      final cond = data['condicionesPredio'] as Map<String, dynamic>?;
      if (cond != null) {
        await db.into(db.condicionesPredio).insert(
            CondicionesPredioCompanion.insert(
              predioId: predioId,
              altitudMsnm: Value((cond['altitudMsnm'] as num?)?.toDouble()),
              precipitacionAnualMm:
                  Value((cond['precipitacionAnualMm'] as num?)?.toDouble()),
              tempMediaC: Value((cond['tempMediaC'] as num?)?.toDouble()),
              tempMinC: Value((cond['tempMinC'] as num?)?.toDouble()),
              tempMaxC: Value((cond['tempMaxC'] as num?)?.toDouble()),
              humedadRelativaPct:
                  Value((cond['humedadRelativaPct'] as num?)?.toDouble()),
              zonaClimatica: Value(cond['zonaClimatica'] as String?),
              pisoTermico: Value(cond['pisoTermico'] as String?),
              fuente: Value(cond['fuente'] as String?),
              notas: Value(cond['notas'] as String?),
            ));
      }

      return ImportResult(
        predioId: predioId,
        cultivos: cultivoMap.length,
        eventos: evCount,
        tareas: tareaCount,
        lotes: loteMap.length,
      );
    });
  }

  static DateTime? _parseNullableDate(dynamic v) {
    if (v == null || v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  Map<String, dynamic> _predioToJson(Predio p) => {
        'id': p.id,
        'nombre': p.nombre,
        'propietario': p.propietario,
        'paisId': p.paisId,
        'regionId': p.regionId,
        'municipioId': p.municipioId,
        'lat': p.lat,
        'lng': p.lng,
        'altM': p.altM,
        'notas': p.notas,
      };

  Map<String, dynamic> _loteToJson(Lote l) => {
        'id': l.id,
        'nombre': l.nombre,
        'administrador': l.administrador,
        'altitudMsnm': l.altitudMsnm,
        'areaM2': l.areaM2,
        'poligonoGeoJson': l.poligonoGeoJson,
        'notas': l.notas,
      };

  Map<String, dynamic> _cultivoToJson(Cultivo c) => {
        'id': c.id,
        'plantaId': c.plantaId,
        'loteId': c.loteId,
        'nombreLote': c.nombreLote,
        'fechaSiembra': c.fechaSiembra.toIso8601String(),
        'fechaCosechaEstimada': c.fechaCosechaEstimada?.toIso8601String(),
        'areaBaseM2': c.areaBaseM2,
        'hhTotal': c.hhTotal,
        'horaValor': c.horaValor,
        'lat': c.lat,
        'lng': c.lng,
        'altM': c.altM,
        'finalizadoFecha': c.finalizadoFecha?.toIso8601String(),
        'notas': c.notas,
      };

  Map<String, dynamic> _eventoToJson(EventosCultivoData e) => {
        'cultivoId': e.cultivoId,
        'tipo': e.tipo,
        'fechaProgramada': e.fechaProgramada?.toIso8601String(),
        'fechaEjecutada': e.fechaEjecutada?.toIso8601String(),
        'descripcion': e.descripcion,
        'notas': e.notas,
      };

  Map<String, dynamic> _tareaToJson(TareasCompletada t) => {
        'cultivoId': t.cultivoId,
        'fecha': t.fecha.toIso8601String(),
        'hh': t.hh,
        'actividadesJson': t.actividadesJson,
        'insumosJson': t.insumosJson,
        'notas': t.notas,
      };

  Map<String, dynamic> _inventarioToJson(Inventario i) => {
        'fecha': i.fecha.toIso8601String(),
        'descripcion': i.descripcion,
        'codigo': i.codigo,
        'fabricante': i.fabricante,
        'cantidadBase': i.cantidadBase,
        'unidadBase': i.unidadBase,
        'notas': i.notas,
      };

  Map<String, dynamic> _compraToJson(Compra c) => {
        'proveedorId': c.proveedorId,
        'fecha': c.fecha.toIso8601String(),
        'descripcion1': c.descripcion1,
        'descripcion2': c.descripcion2,
        'valorTotal': c.valorTotal,
        'cantidadBase': c.cantidadBase,
        'unidadBase': c.unidadBase,
        'codigo': c.codigo,
        'factura': c.factura,
        'tipo': c.tipo,
        'notas': c.notas,
      };

  Map<String, dynamic> _provToJson(Proveedore p) => {
        'id': p.id,
        'nombre': p.nombre,
        'nit': p.nit,
        'telefono': p.telefono,
        'email': p.email,
        'web': p.web,
        'direccion': p.direccion,
        'notas': p.notas,
      };

  Map<String, dynamic> _analisisToJson(AnalisisSueloData a) => {
        'fechaMuestreo': a.fechaMuestreo.toIso8601String(),
        'lote': a.lote,
        'laboratorio': a.laboratorio,
        'profundidadCm': a.profundidadCm,
        'textura': a.textura,
        'ph': a.ph,
        'materiaOrganicaPct': a.materiaOrganicaPct,
        'nPpm': a.nPpm,
        'pPpm': a.pPpm,
        'kPpm': a.kPpm,
        'caMeq': a.caMeq,
        'mgMeq': a.mgMeq,
        'naMeq': a.naMeq,
        'cicMeq': a.cicMeq,
        'conductividadMsCm': a.conductividadMsCm,
        'notas': a.notas,
      };

  Map<String, dynamic> _condicionesToJson(CondicionesPredioData c) => {
        'altitudMsnm': c.altitudMsnm,
        'precipitacionAnualMm': c.precipitacionAnualMm,
        'tempMediaC': c.tempMediaC,
        'tempMinC': c.tempMinC,
        'tempMaxC': c.tempMaxC,
        'humedadRelativaPct': c.humedadRelativaPct,
        'zonaClimatica': c.zonaClimatica,
        'pisoTermico': c.pisoTermico,
        'fuente': c.fuente,
        'notas': c.notas,
      };

  Map<String, dynamic> _cultivoPatologiaToJson(CultivoPatologia p) => {
        'cultivoId': p.cultivoId,
        'patologiaId': p.patologiaId,
        'fechaDeteccion': p.fechaDeteccion.toIso8601String(),
        'severidad': p.severidad,
        'notas': p.notas,
      };
}

class ImportResult {
  final int predioId;
  final int cultivos, eventos, tareas, lotes;
  const ImportResult({
    required this.predioId,
    required this.cultivos,
    required this.eventos,
    required this.tareas,
    required this.lotes,
  });
}
