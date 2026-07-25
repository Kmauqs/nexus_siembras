// NEXUS Siembras — Repositorio de cultivos
// Estado calculado (verde/naranja/rojo), soft-delete, finalizado,
// registro de tareas completadas con acumulación de HH.

import 'dart:convert';
import 'package:drift/drift.dart';
import '../../core/models/ciclo_abono.dart';
import '../../core/units/units_catalog.dart';
import '../database/database.dart';

enum EstadoCultivo { verde, naranja, rojo }

class EstadoInfo {
  final EstadoCultivo estado;
  final String nota;
  const EstadoInfo(this.estado, this.nota);
}

class CultivoRepository {
  CultivoRepository(this.db);
  final AppDatabase db;

  // ============================================================
  // Streams
  // ============================================================

  Stream<List<Cultivo>> watchActivosByPredio(int predioId) {
    return (db.select(db.cultivos)
          ..where((c) => c.predioId.equals(predioId))
          ..where((c) => c.deletedAt.isNull())
          ..where((c) => c.finalizadoFecha.isNull())
          ..orderBy([(c) => OrderingTerm.desc(c.fechaSiembra)]))
        .watch();
  }

  Stream<List<Cultivo>> watchFinalizadosByPredio(int predioId) {
    return (db.select(db.cultivos)
          ..where((c) => c.predioId.equals(predioId))
          ..where((c) => c.deletedAt.isNull())
          ..where((c) => c.finalizadoFecha.isNotNull())
          ..orderBy([(c) => OrderingTerm.desc(c.finalizadoFecha)]))
        .watch();
  }

  Stream<List<Cultivo>> watchAllByPredio(int predioId) {
    return (db.select(db.cultivos)
          ..where((c) => c.predioId.equals(predioId))
          ..where((c) => c.deletedAt.isNull()))
        .watch();
  }

  /// Fase 3e-6: cultivos activos de TODOS los predios accesibles al usuario
  /// (todo lo que esté en la BD local). Se usa en el mapa para la capa
  /// "Todos mis cultivos".
  Stream<List<Cultivo>> watchTodosActivos() {
    return (db.select(db.cultivos)
          ..where((c) => c.deletedAt.isNull())
          ..where((c) => c.finalizadoFecha.isNull())
          ..orderBy([(c) => OrderingTerm.desc(c.fechaSiembra)]))
        .watch();
  }

  Stream<List<EventosCultivoData>> watchEventosByCultivo(int cultivoId) {
    return (db.select(db.eventosCultivo)
          ..where((e) => e.cultivoId.equals(cultivoId))
          ..where((e) => e.deletedAt.isNull())
          ..orderBy([(e) => OrderingTerm.asc(e.fechaProgramada)]))
        .watch();
  }

  /// Todos los eventos de cultivos activos del predio (join con cultivos).
  Stream<List<EventosCultivoData>> watchEventosByPredio(int predioId) {
    final query = db.select(db.eventosCultivo).join([
      innerJoin(db.cultivos, db.cultivos.id.equalsExp(db.eventosCultivo.cultivoId)),
    ])
      ..where(db.cultivos.predioId.equals(predioId))
      ..where(db.cultivos.deletedAt.isNull())
      ..where(db.eventosCultivo.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(db.eventosCultivo.fechaProgramada)]);
    return query.watch().map((rows) =>
        rows.map((row) => row.readTable(db.eventosCultivo)).toList());
  }

  Stream<List<TareasCompletada>> watchTareasByCultivo(int cultivoId) {
    return (db.select(db.tareasCompletadas)
          ..where((t) => t.cultivoId.equals(cultivoId))
          ..orderBy([(t) => OrderingTerm.asc(t.fecha)]))
        .watch();
  }

  /// Todas las tareas de cultivos del predio (activos y finalizados).
  Stream<List<TareasCompletada>> watchTareasByPredio(int predioId) {
    final query = db.select(db.tareasCompletadas).join([
      innerJoin(db.cultivos, db.cultivos.id.equalsExp(db.tareasCompletadas.cultivoId)),
    ])
      ..where(db.cultivos.predioId.equals(predioId))
      ..where(db.cultivos.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(db.tareasCompletadas.fecha)]);
    return query.watch().map((rows) =>
        rows.map((row) => row.readTable(db.tareasCompletadas)).toList());
  }

  // ============================================================
  // Mutaciones
  // ============================================================

  /// Inserta un cultivo nuevo + crea eventos proyectados iniciales.
  Future<int> insert({
    required int predioId,
    required int plantaId,
    required String lote,
    required DateTime fechaSiembra,
    required double areaValor,
    required String areaUnidad,
    required double semillaValor,
    required String semillaUnidad,
    required double hhInicial,
    required double horaValor,
    double? lat,
    double? lng,
    double? altM,
    int? loteId,
    String tipoCultivo = 'ciclo_unico',
    int? cosecha1Dias,
    int? cosecha2Dias,
    int? periodicidadCosechaDias,
    int? esperanzaVidaDias,
  }) async {
    final (areaBase, _) = toBase(areaValor, areaUnidad);
    final (semBase, semCode) = toBase(semillaValor, semillaUnidad);

    final planta = await (db.select(db.plantas)
          ..where((p) => p.id.equals(plantaId)))
        .getSingle();

    // === Modelo de etapas ===
    // Para cultivos con germinador, `fechaSiembra` representa la fecha en
    // que el usuario siembra la semilla en el germinador. La fenología
    // agronómica (abono, cosecha) se cuenta desde la fecha del TRASPLANTE
    // (= fechaSiembra + germinadorDias), que es cuando la planta pasa al
    // sitio definitivo.
    //
    // Etapas resultantes:
    //   Con germinador:
    //     - Semillero  : fechaSiembra (marcado como YA EJECUTADO)
    //     - Trasplante : fechaSiembra + germinadorDias (PENDIENTE)
    //     - Abono, cosecha, etc. : cuentan desde fechaTrasplante
    //   Sin germinador:
    //     - Siembra    : fechaSiembra (marcado como YA EJECUTADO)
    //     - Abono, cosecha, etc. : cuentan desde fechaSiembra
    final esGerminador =
        planta.metodoSiembra == 'germinador' && planta.germinadorDias != null;
    final fechaBase = _fechaBaseFenologia(
        planta: planta, fechaSiembra: fechaSiembra, esGerminador: esGerminador);

    final esPerenne = tipoCultivo == 'perenne';
    final cos1 = cosecha1Dias ?? planta.tiempoCosechaMinDias;
    final cos2 = cosecha2Dias ?? planta.tiempoCosechaMaxDias;
    final DateTime? cosechaEst;
    if (esPerenne && esperanzaVidaDias != null) {
      cosechaEst = fechaBase.add(Duration(days: esperanzaVidaDias));
    } else if (cos2 != null) {
      cosechaEst = fechaBase.add(Duration(days: cos2));
    } else if (cos1 != null) {
      cosechaEst = fechaBase.add(Duration(days: cos1));
    } else {
      cosechaEst = fechaBase.add(const Duration(days: 120));
    }

    final cultivoId = await db.into(db.cultivos).insert(CultivosCompanion.insert(
          predioId: predioId,
          plantaId: plantaId,
          loteId: Value(loteId),
          nombreLote: Value(lote.trim().isEmpty ? null : lote.trim()),
          fechaSiembra: fechaSiembra,
          fechaCosechaEstimada: Value(cosechaEst),
          areaBaseM2: Value(areaBase),
          cantidadSemillaBase: Value(semBase),
          cantidadSemillaUnidadBase: Value(semCode),
          hhTotal: Value(hhInicial),
          horaValor: Value(horaValor),
          lat: Value(lat),
          lng: Value(lng),
          altM: Value(altM),
          tipoCultivo: Value(tipoCultivo),
          cosecha1Dias: Value(cosecha1Dias),
          cosecha2Dias: Value(cosecha2Dias),
          periodicidadCosechaDias: Value(periodicidadCosechaDias),
          esperanzaVidaDias: Value(esperanzaVidaDias),
        ));

    final culRow = await (db.select(db.cultivos)
          ..where((c) => c.id.equals(cultivoId)))
        .getSingle();
    await _generarEventosProyectados(
      cultivoId: cultivoId,
      planta: planta,
      cul: culRow,
    );

    return cultivoId;
  }

  /// Crea el cronograma inicial de eventos según la planta y la config
  /// del cultivo (tipo, periodos de cosecha, etc.).
  Future<void> _generarEventosProyectados({
    required int cultivoId,
    required Planta planta,
    required Cultivo cul,
  }) async {
    final esGerminador =
        planta.metodoSiembra == 'germinador' && planta.germinadorDias != null;
    final fechaBase = _fechaBaseFenologia(
        planta: planta, fechaSiembra: cul.fechaSiembra, esGerminador: esGerminador);
    final esPerenne = cul.tipoCultivo == 'perenne';
    final cos1 = cul.cosecha1Dias ?? planta.tiempoCosechaMinDias;
    final cos2 = cul.cosecha2Dias ?? planta.tiempoCosechaMaxDias;

    Future<void> ev(String tipo, DateTime fecha, String desc,
        {bool executed = false}) async {
      await db.into(db.eventosCultivo).insert(EventosCultivoCompanion.insert(
            cultivoId: cultivoId,
            tipo: tipo,
            fechaProgramada: Value(fecha),
            fechaEjecutada: executed ? Value(fecha) : const Value.absent(),
            descripcion: Value(desc),
          ));
    }

    if (esGerminador) {
      await ev('semillero', cul.fechaSiembra,
          'Semillero (germinador · ${planta.germinadorDias} d)',
          executed: true);
      await ev('trasplante', fechaBase, 'Trasplante');
    } else {
      await ev('siembra', cul.fechaSiembra, 'Siembra', executed: true);
    }

    final ciclosAbono = decodeCiclosAbonoJson(
      planta.ciclosAbonoJson,
      tipoAbono1: planta.tipoAbono1,
      tipoAbono2: planta.tipoAbono2,
      diasAbono2: planta.diasAbono2,
    );
    final sorted = [...ciclosAbono]..sort((a, b) => a.dias.compareTo(b.dias));
    for (var i = 0; i < sorted.length; i++) {
      final c = sorted[i];
      final n = i + 1;
      await ev(
        'abono',
        fechaBase.add(Duration(days: c.dias)),
        'Abono $n${c.tipo.isNotEmpty ? " · ${c.tipo}" : ""}',
      );
    }
    if (sorted.length >= 2 && sorted[1].dias > 1) {
      await ev(
        'control_fito',
        fechaBase.add(Duration(days: sorted[1].dias - 1)),
        'Desmalezada',
      );
    }

    if (esPerenne) {
      final period = cul.periodicidadCosechaDias ?? 90;
      final vida = cul.esperanzaVidaDias ?? 365 * 3;
      final primera = cos1 ?? period;
      await _generarCosechasPeriodicas(
        cultivoId: cultivoId,
        ev: ev,
        fechaInicio: fechaBase.add(Duration(days: primera)),
        finCiclo: fechaBase.add(Duration(days: vida)),
        periodicidadDias: period,
        desdeNumero: 1,
      );
      await ev('renovacion', fechaBase.add(Duration(days: vida)), 'Renovación');
    } else {
      if (cos1 != null) {
        await ev('cosecha', fechaBase.add(Duration(days: cos1)), 'Cosecha 1');
      }
      if (cos2 != null && cos2 != cos1) {
        await ev('cosecha', fechaBase.add(Duration(days: cos2)), 'Cosecha 2');
      }
    }
  }

  static DateTime _fechaBaseFenologia({
    required Planta planta,
    required DateTime fechaSiembra,
    required bool esGerminador,
  }) {
    if (esGerminador && planta.germinadorDias != null) {
      return fechaSiembra.add(Duration(days: planta.germinadorDias!));
    }
    return fechaSiembra;
  }

  /// Genera eventos «Cosecha periódica N» cada [periodicidadDias] hasta
  /// [finCiclo] (exclusive de fechas posteriores al fin).
  Future<void> _generarCosechasPeriodicas({
    required int cultivoId,
    required Future<void> Function(String tipo, DateTime fecha, String desc,
            {bool executed})
        ev,
    required DateTime fechaInicio,
    required DateTime finCiclo,
    required int periodicidadDias,
    required int desdeNumero,
  }) async {
    var n = desdeNumero;
    var fecha = fechaInicio;
    final fin = DateTime(finCiclo.year, finCiclo.month, finCiclo.day);
    while (!fecha.isAfter(fin)) {
      await ev('cosecha', fecha, 'Cosecha periódica $n');
      n++;
      fecha = fecha.add(Duration(days: periodicidadDias));
    }
  }

  /// Tras registrar una cosecha periódica, asegura eventos futuros hasta el
  /// fin del ciclo de vida del cultivo perenne.
  Future<void> extenderCosechasPeriodicas({
    required int cultivoId,
    required DateTime fechaReferencia,
    required int periodicidadDias,
  }) async {
    final cul = await (db.select(db.cultivos)
          ..where((c) => c.id.equals(cultivoId)))
        .getSingleOrNull();
    if (cul == null || cul.tipoCultivo != 'perenne') return;

    final planta = await (db.select(db.plantas)
          ..where((p) => p.id.equals(cul.plantaId)))
        .getSingleOrNull();
    if (planta == null) return;

    final esGerm = planta.metodoSiembra == 'germinador' &&
        planta.germinadorDias != null;
    final fechaBase = _fechaBaseFenologia(
        planta: planta, fechaSiembra: cul.fechaSiembra, esGerminador: esGerm);
    final vida = cul.esperanzaVidaDias ?? 365 * 3;
    final finCiclo = fechaBase.add(Duration(days: vida));

    if (periodicidadDias != cul.periodicidadCosechaDias) {
      await (db.update(db.cultivos)..where((c) => c.id.equals(cultivoId)))
          .write(CultivosCompanion(
        periodicidadCosechaDias: Value(periodicidadDias),
        updatedAt: Value(DateTime.now()),
      ));
    }

    final pendientes = await (db.select(db.eventosCultivo)
          ..where((e) => e.cultivoId.equals(cultivoId))
          ..where((e) => e.descripcion.like('Cosecha periódica%'))
          ..where((e) => e.fechaEjecutada.isNull())
          ..where((e) => e.deletedAt.isNull())
          ..orderBy([(e) => OrderingTerm.desc(e.fechaProgramada)]))
        .get();
    if (pendientes.isNotEmpty) return;

    final todos = await (db.select(db.eventosCultivo)
          ..where((e) => e.cultivoId.equals(cultivoId))
          ..where((e) => e.descripcion.like('Cosecha periódica%'))
          ..where((e) => e.deletedAt.isNull()))
        .get();
    var maxN = 0;
    for (final e in todos) {
      final d = e.descripcion ?? '';
      final m = RegExp(r'Cosecha periódica (\d+)').firstMatch(d);
      if (m != null) {
        final num = int.tryParse(m.group(1) ?? '') ?? 0;
        if (num > maxN) maxN = num;
      }
    }

    Future<void> ev(String tipo, DateTime fecha, String desc,
        {bool executed = false}) async {
      await db.into(db.eventosCultivo).insert(EventosCultivoCompanion.insert(
            cultivoId: cultivoId,
            tipo: tipo,
            fechaProgramada: Value(fecha),
            fechaEjecutada: executed ? Value(fecha) : const Value.absent(),
            descripcion: Value(desc),
          ));
    }

    await _generarCosechasPeriodicas(
      cultivoId: cultivoId,
      ev: ev,
      fechaInicio: fechaReferencia.add(Duration(days: periodicidadDias)),
      finCiclo: finCiclo,
      periodicidadDias: periodicidadDias,
      desdeNumero: maxN + 1,
    );
  }

  Future<void> softDelete(int id) {
    final now = DateTime.now();
    return (db.update(db.cultivos)..where((c) => c.id.equals(id))).write(
      CultivosCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  Future<void> markFinalizado(int id) => (db.update(db.cultivos)
        ..where((c) => c.id.equals(id)))
      .write(CultivosCompanion(finalizadoFecha: Value(DateTime.now())));

  Future<void> unmarkFinalizado(int id) => (db.update(db.cultivos)
        ..where((c) => c.id.equals(id)))
      .write(const CultivosCompanion(finalizadoFecha: Value(null)));

  // ============================================================
  // Estado calculado
  // ============================================================

  Future<EstadoInfo> computarEstado(int cultivoId) async {
    final hoy = DateTime.now();
    final soloHoy = DateTime(hoy.year, hoy.month, hoy.day);

    final patAv = await (db.select(db.cultivoPatologias)
          ..where((p) => p.cultivoId.equals(cultivoId))
          ..where((p) => p.curaFecha.isNull())
          ..where((p) => p.severidad.equals('avanzada'))
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.desc(p.fechaDeteccion)])
          ..limit(1))
        .getSingleOrNull();
    if (patAv != null) {
      final pat = await (db.select(db.patologias)
            ..where((p) => p.id.equals(patAv.patologiaId ?? -1)))
          .getSingleOrNull();
      return EstadoInfo(EstadoCultivo.rojo,
          'Patología avanzada: ${pat?.nombreComun ?? "?"} desde ${_iso(patAv.fechaDeteccion)}');
    }

    final vencido = await (db.select(db.eventosCultivo)
          ..where((e) => e.cultivoId.equals(cultivoId))
          ..where((e) => e.fechaEjecutada.isNull())
          ..where((e) => e.deletedAt.isNull())
          ..where((e) => e.fechaProgramada.isSmallerThanValue(soloHoy))
          ..orderBy([(e) => OrderingTerm.asc(e.fechaProgramada)])
          ..limit(1))
        .getSingleOrNull();
    if (vencido != null) {
      final dias = soloHoy.difference(vencido.fechaProgramada!).inDays;
      return EstadoInfo(EstadoCultivo.rojo,
          'Actividad "${vencido.descripcion ?? ""}" vencida hace $dias día(s)');
    }

    final patIn = await (db.select(db.cultivoPatologias)
          ..where((p) => p.cultivoId.equals(cultivoId))
          ..where((p) => p.curaFecha.isNull())
          ..where((p) => p.severidad.equals('inicial'))
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.desc(p.fechaDeteccion)])
          ..limit(1))
        .getSingleOrNull();
    if (patIn != null) {
      return const EstadoInfo(EstadoCultivo.naranja, 'Patología inicial en detección');
    }

    final proximo = await (db.select(db.eventosCultivo)
          ..where((e) => e.cultivoId.equals(cultivoId))
          ..where((e) => e.fechaEjecutada.isNull())
          ..where((e) => e.deletedAt.isNull())
          ..where((e) => e.fechaProgramada.isBiggerOrEqualValue(soloHoy))
          ..where((e) => e.fechaProgramada
              .isSmallerOrEqualValue(soloHoy.add(const Duration(days: 7))))
          ..orderBy([(e) => OrderingTerm.asc(e.fechaProgramada)])
          ..limit(1))
        .getSingleOrNull();
    if (proximo != null) {
      final dias = proximo.fechaProgramada!.difference(soloHoy).inDays;
      return EstadoInfo(EstadoCultivo.naranja,
          'Faltan $dias día(s) para "${proximo.descripcion ?? ""}"');
    }

    return const EstadoInfo(EstadoCultivo.verde, 'Sin alertas');
  }

  // ============================================================
  // Tareas completadas
  // ============================================================

  static const _actividadTipoMap = <String, String>{
    'Abono1': 'abono', 'Abono2': 'abono',
    'Desmalezada': 'control_fito', 'Fumigación': 'control_fito',
    'Cosecha1': 'cosecha', 'Cosecha2': 'cosecha',
    'Cosecha periódica': 'cosecha',
    'Renovación': 'renovacion',
    'Semillero': 'semillero', 'Trasplante': 'trasplante',
    'Siembra': 'siembra',
  };

  /// Mapea la actividad seleccionada por el usuario al prefijo de descripción
  /// del evento correspondiente. Permite distinguir Abono1 vs Abono2 aunque
  /// ambos compartan tipo='abono'.
  static const _actividadDescMap = <String, String>{
    'Siembra': 'Siembra',
    'Semillero': 'Semillero',
    'Trasplante': 'Trasplante',
    'Abono1': 'Abono 1',
    'Abono2': 'Abono 2',
    'Desmalezada': 'Desmalezada',
    'Cosecha1': 'Cosecha 1',
    'Cosecha2': 'Cosecha 2',
    'Cosecha periódica': 'Cosecha periódica',
    'Renovación': 'Renovación',
    // 'Fumigación' no tiene evento proyectado; se registra como tarea sin cerrar evento.
  };

  Future<int> registrarTarea({
    required int cultivoId,
    required DateTime fecha,
    required double hh,
    required List<String> actividades,
    List<Map<String, dynamic>> insumos = const [],
    String? notas,
    String? createdByUserId,
    int? periodicidadCosechaDias,
  }) async {
    return await db.transaction<int>(() async {
      final id = await db.into(db.tareasCompletadas).insert(
          TareasCompletadasCompanion.insert(
            cultivoId: cultivoId,
            fecha: fecha,
            hh: Value(hh),
            actividadesJson: jsonEncode(actividades),
            insumosJson: Value(jsonEncode(insumos)),
            notas: Value(notas),
            createdByUserId: Value(createdByUserId),
          ));
      // Read-modify-write para acumular HH (evita customStatement con DateTime)
      final cultivoActual = await (db.select(db.cultivos)
            ..where((c) => c.id.equals(cultivoId)))
          .getSingle();
      await (db.update(db.cultivos)..where((c) => c.id.equals(cultivoId)))
          .write(CultivosCompanion(
        hhTotal: Value(cultivoActual.hhTotal + hh),
        updatedAt: Value(DateTime.now()),
      ));
      for (final a in actividades) {
        await _cerrarEventoPorActividad(
          cultivoId: cultivoId,
          actividad: a,
          fecha: fecha,
        );
      }

      if (actividades.contains('Cosecha periódica') &&
          periodicidadCosechaDias != null &&
          periodicidadCosechaDias > 0) {
        await extenderCosechasPeriodicas(
          cultivoId: cultivoId,
          fechaReferencia: fecha,
          periodicidadDias: periodicidadCosechaDias,
        );
      }

      if (actividades.contains('Renovación')) {
        await markFinalizado(cultivoId);
      }

      return id;
    });
  }

  /// Cierra el evento pendiente más antiguo que coincida con [actividad] y
  /// desplaza los eventos posteriores según la fecha real de ejecución.
  Future<bool> _cerrarEventoPorActividad({
    required int cultivoId,
    required String actividad,
    required DateTime fecha,
  }) async {
    final descPrefix = _actividadDescMap[actividad];
    if (descPrefix == null) return false;
    final match = await (db.select(db.eventosCultivo)
          ..where((e) => e.cultivoId.equals(cultivoId))
          ..where((e) => e.descripcion.like('$descPrefix%'))
          ..where((e) => e.fechaEjecutada.isNull())
          ..where((e) => e.deletedAt.isNull())
          ..orderBy([(e) => OrderingTerm.asc(e.fechaProgramada)])
          ..limit(1))
        .getSingleOrNull();
    if (match == null) return false;
    final prog = match.fechaProgramada ?? fecha;
    await (db.update(db.eventosCultivo)..where((e) => e.id.equals(match.id)))
        .write(EventosCultivoCompanion(
      fechaEjecutada: Value(fecha),
      updatedAt: Value(DateTime.now()),
    ));
    await _desplazarEventosPendientes(
      cultivoId: cultivoId,
      anclaProgramada: prog,
      fechaEjecutada: fecha,
    );
    return true;
  }

  /// Desplaza las fechas programadas de eventos pendientes posteriores al
  /// ancla cuando una actividad se ejecuta antes o después de lo previsto.
  Future<void> _desplazarEventosPendientes({
    required int cultivoId,
    required DateTime anclaProgramada,
    required DateTime fechaEjecutada,
  }) async {
    final orig = DateTime(
        anclaProgramada.year, anclaProgramada.month, anclaProgramada.day);
    final exec =
        DateTime(fechaEjecutada.year, fechaEjecutada.month, fechaEjecutada.day);
    final delta = exec.difference(orig).inDays;
    if (delta == 0) return;

    final pendientes = await (db.select(db.eventosCultivo)
          ..where((e) => e.cultivoId.equals(cultivoId))
          ..where((e) => e.fechaEjecutada.isNull())
          ..where((e) => e.deletedAt.isNull())
          ..where((e) => e.fechaProgramada.isBiggerThanValue(orig)))
        .get();

    final now = DateTime.now();
    for (final e in pendientes) {
      final prog = e.fechaProgramada;
      if (prog == null) continue;
      await (db.update(db.eventosCultivo)..where((x) => x.id.equals(e.id)))
          .write(EventosCultivoCompanion(
        fechaProgramada: Value(prog.add(Duration(days: delta))),
        updatedAt: Value(now),
      ));
    }
    await _actualizarFechaCosechaEstimada(cultivoId);
  }

  /// Recalcula la fecha de cosecha estimada del cultivo según el último
  /// evento de cosecha o renovación (efectivo o programado).
  Future<void> _actualizarFechaCosechaEstimada(int cultivoId) async {
    final evs = await (db.select(db.eventosCultivo)
          ..where((e) => e.cultivoId.equals(cultivoId))
          ..where((e) => e.deletedAt.isNull())
          ..where((e) => e.tipo.isIn(['cosecha', 'renovacion'])))
        .get();
    if (evs.isEmpty) return;
    DateTime? maxFecha;
    for (final e in evs) {
      final f = e.fechaEjecutada ?? e.fechaProgramada;
      if (f == null) continue;
      if (maxFecha == null || f.isAfter(maxFecha)) maxFecha = f;
    }
    if (maxFecha == null) return;
    await (db.update(db.cultivos)..where((c) => c.id.equals(cultivoId))).write(
        CultivosCompanion(
      fechaCosechaEstimada: Value(maxFecha),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Actualiza fecha, HH, y notas de una tarea existente. No permite cambiar
  /// actividades ni insumos (usar delete + registrar para eso).
  Future<void> updateTareaSimple({
    required int id,
    required DateTime fecha,
    required double hh,
    String? notas,
  }) async {
    await db.transaction(() async {
      final old = await (db.select(db.tareasCompletadas)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (old == null) return;
      final diff = hh - old.hh;
      await (db.update(db.tareasCompletadas)..where((t) => t.id.equals(id)))
          .write(TareasCompletadasCompanion(
        fecha: Value(fecha),
        hh: Value(hh),
        notas: Value(notas),
      ));
      if (diff != 0) {
        final cul = await (db.select(db.cultivos)
              ..where((c) => c.id.equals(old.cultivoId)))
            .getSingle();
        await (db.update(db.cultivos)..where((c) => c.id.equals(old.cultivoId)))
            .write(CultivosCompanion(
          hhTotal: Value(cul.hhTotal + diff),
          updatedAt: Value(DateTime.now()),
        ));
      }
    });
  }

  /// Borra una tarea y revierte sus efectos: resta HH, restaura insumos al
  /// inventario y reabre los eventos que había cerrado.
  Future<void> deleteTarea(int id, int predioId) async {
    await db.transaction(() async {
      final tarea = await (db.select(db.tareasCompletadas)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (tarea == null) return;
      // 1) Resta HH del cultivo (con clamp a 0)
      final cul = await (db.select(db.cultivos)
            ..where((c) => c.id.equals(tarea.cultivoId)))
          .getSingle();
      final nuevoHh = (cul.hhTotal - tarea.hh).clamp(0.0, double.infinity);
      await (db.update(db.cultivos)..where((c) => c.id.equals(tarea.cultivoId)))
          .write(CultivosCompanion(
        hhTotal: Value(nuevoHh),
        updatedAt: Value(DateTime.now()),
      ));
      // 2) Restaura insumos al inventario
      List<dynamic> insumos = [];
      try {
        insumos = jsonDecode(tarea.insumosJson) as List<dynamic>;
      } catch (_) {}
      for (final ins in insumos) {
        if (ins is! Map) continue;
        final desc = ins['desc'] as String?;
        final cant = (ins['cantidad'] as num?)?.toDouble();
        if (desc == null || cant == null || cant <= 0) continue;
        // Suma en unidad base (cant ya está en base al haber sido consumido así)
        final inv = await (db.select(db.inventarios)
              ..where((i) => i.predioId.equals(predioId))
              ..where((i) => i.descripcion.lower().equals(desc.toLowerCase().trim()))
              ..limit(1))
            .getSingleOrNull();
        if (inv != null) {
          await (db.update(db.inventarios)..where((i) => i.id.equals(inv.id)))
              .write(InventariosCompanion(
            cantidadBase: Value(inv.cantidadBase + cant),
            updatedAt: Value(DateTime.now()),
          ));
        }
      }
      // 3) Reabre eventos cerrados por la fecha de la tarea
      final acts = <String>[];
      try {
        acts.addAll((jsonDecode(tarea.actividadesJson) as List<dynamic>).cast<String>());
      } catch (_) {}
      for (final a in acts) {
        final descPrefix = _actividadDescMap[a];
        if (descPrefix == null) continue;
        await (db.update(db.eventosCultivo)
              ..where((e) => e.cultivoId.equals(tarea.cultivoId))
              ..where((e) => e.descripcion.like('$descPrefix%'))
              ..where((e) => e.fechaEjecutada.equals(tarea.fecha)))
            .write(EventosCultivoCompanion(
          fechaEjecutada: const Value(null),
          updatedAt: Value(DateTime.now()),
        ));
      }
      // 4) Borra la tarea
      await (db.delete(db.tareasCompletadas)..where((t) => t.id.equals(id))).go();
    });
  }

  /// Recorre las tareas del cultivo y vuelve a cerrar los eventos que
  /// correspondan según la actual lógica de matching por descripción.
  /// Útil para reparar datos generados por versiones anteriores donde
  /// Abono1 y Abono2 compartían tipo='abono' y podían cerrar el evento
  /// equivocado.
  Future<int> resincronizarEventos(int cultivoId) async {
    return await db.transaction<int>(() async {
      final cul = await (db.select(db.cultivos)
            ..where((c) => c.id.equals(cultivoId)))
          .getSingleOrNull();
      if (cul == null) return 0;
      final planta = await (db.select(db.plantas)
            ..where((p) => p.id.equals(cul.plantaId)))
          .getSingleOrNull();
      if (planta == null) return 0;

      // Regenera fechas programadas originales y reaplica tareas con ajuste.
      await (db.delete(db.eventosCultivo)
            ..where((e) => e.cultivoId.equals(cultivoId)))
          .go();
      await _generarEventosProyectados(
        cultivoId: cultivoId,
        planta: planta,
        cul: cul,
      );

      final tareas = await (db.select(db.tareasCompletadas)
            ..where((t) => t.cultivoId.equals(cultivoId))
            ..orderBy([(t) => OrderingTerm.asc(t.fecha)]))
          .get();
      var cerrados = 0;
      for (final t in tareas) {
        final acts = <String>[];
        try {
          acts.addAll(
              (jsonDecode(t.actividadesJson) as List<dynamic>).cast<String>());
        } catch (_) {}
        for (final a in acts) {
          if (await _cerrarEventoPorActividad(
            cultivoId: cultivoId,
            actividad: a,
            fecha: t.fecha,
          )) {
            cerrados++;
          }
        }
        if (acts.contains('Cosecha periódica') &&
            cul.periodicidadCosechaDias != null &&
            cul.periodicidadCosechaDias! > 0) {
          await extenderCosechasPeriodicas(
            cultivoId: cultivoId,
            fechaReferencia: t.fecha,
            periodicidadDias: cul.periodicidadCosechaDias!,
          );
        }
        if (acts.contains('Renovación')) {
          await markFinalizado(cultivoId);
        }
      }
      return cerrados;
    });
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}
