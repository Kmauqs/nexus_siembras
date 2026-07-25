// NEXUS Siembras — Repositorio de cultivos
// Estado calculado (verde/naranja/rojo), soft-delete, finalizado,
// registro de tareas completadas con acumulación de HH.

import 'dart:convert';
import 'package:drift/drift.dart';
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
    final fechaBase = esGerminador
        ? fechaSiembra.add(Duration(days: planta.germinadorDias!))
        : fechaSiembra;

    final maxCos = planta.tiempoCosechaMaxDias ?? 120;
    final cosechaEst = fechaBase.add(Duration(days: maxCos));

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
        ));

    // Genera eventos proyectados. `executed=true` marca el evento como ya
    // ejecutado (para siembra o semillero, cuando se registra el cultivo
    // al momento de sembrar).
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
      // Semillero: hoy (fechaSiembra) — ya ejecutado
      await ev('semillero', fechaSiembra,
          'Semillero (germinador · ${planta.germinadorDias} d)',
          executed: true);
      // Trasplante: en fechaBase — PENDIENTE, se registra cuando toque
      await ev('trasplante', fechaBase, 'Trasplante');
    } else {
      await ev('siembra', fechaSiembra, 'Siembra', executed: true);
    }

    await ev('abono', fechaBase.add(const Duration(days: 1)),
        'Abono 1${planta.tipoAbono1 != null ? " · ${planta.tipoAbono1}" : ""}');

    if (planta.diasAbono2 != null) {
      final desmalezadaDia = (planta.diasAbono2! - 1).clamp(1, 999);
      await ev('control_fito',
          fechaBase.add(Duration(days: desmalezadaDia)), 'Desmalezada');
      await ev('abono', fechaBase.add(Duration(days: planta.diasAbono2!)),
          'Abono 2${planta.tipoAbono2 != null ? " · ${planta.tipoAbono2}" : ""}');
    }
    if (planta.tiempoCosechaMinDias != null) {
      await ev('cosecha',
          fechaBase.add(Duration(days: planta.tiempoCosechaMinDias!)),
          'Cosecha 1');
    }
    if (planta.tiempoCosechaMaxDias != null &&
        planta.tiempoCosechaMaxDias != planta.tiempoCosechaMinDias) {
      await ev('cosecha',
          fechaBase.add(Duration(days: planta.tiempoCosechaMaxDias!)),
          'Cosecha 2');
    }

    return cultivoId;
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
        final descPrefix = _actividadDescMap[a];
        if (descPrefix == null) continue;
        // Cierra el evento MÁS ANTIGUO pendiente cuya descripción coincida.
        // Con descripción específica distinguimos Abono 1 de Abono 2, etc.
        final match = await (db.select(db.eventosCultivo)
              ..where((e) => e.cultivoId.equals(cultivoId))
              ..where((e) => e.descripcion.like('$descPrefix%'))
              ..where((e) => e.fechaEjecutada.isNull())
              ..where((e) => e.deletedAt.isNull())
              ..orderBy([(e) => OrderingTerm.asc(e.fechaProgramada)])
              ..limit(1))
            .getSingleOrNull();
        if (match != null) {
          // Bumpear updatedAt es CRÍTICO: sin esto el sync no ve el cambio
          // y el remoto (y por tanto los otros dispositivos) nunca se
          // enteran de que el evento se completó, dejando el Gantt en
          // "Vencido" para los colaboradores (bug detectado 2026-07-19).
          await (db.update(db.eventosCultivo)
                ..where((e) => e.id.equals(match.id)))
              .write(EventosCultivoCompanion(
            fechaEjecutada: Value(fecha),
            updatedAt: Value(DateTime.now()),
          ));
        }
      }
      return id;
    });
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
      // 1) Reabre todos los eventos del cultivo.
      await (db.update(db.eventosCultivo)
            ..where((e) => e.cultivoId.equals(cultivoId))
            ..where((e) => e.deletedAt.isNull()))
          .write(EventosCultivoCompanion(
        fechaEjecutada: const Value(null),
        updatedAt: Value(DateTime.now()),
      ));

      // 2) Reabre eventos de siembra/semillero — se marcan como ejecutados
      //    al momento de insert() del cultivo (representan el "acto" que el
      //    usuario acaba de realizar). Trasplante NO va aquí: siempre inicia
      //    pendiente y se cierra cuando el usuario registre la actividad.
      final cul = await (db.select(db.cultivos)
            ..where((c) => c.id.equals(cultivoId)))
          .getSingleOrNull();
      if (cul == null) return 0;
      final auto = ['Siembra', 'Semillero'];
      for (final descPrefix in auto) {
        await (db.update(db.eventosCultivo)
              ..where((e) => e.cultivoId.equals(cultivoId))
              ..where((e) => e.descripcion.like('$descPrefix%'))
              ..where((e) => e.fechaEjecutada.isNull())
              ..where((e) => e.deletedAt.isNull()))
            .write(EventosCultivoCompanion(
          fechaEjecutada: Value(cul.fechaSiembra),
          updatedAt: Value(DateTime.now()),
        ));
      }

      // 3) Reprocesa cada tarea completada en orden cronológico.
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
          final descPrefix = _actividadDescMap[a];
          if (descPrefix == null) continue;
          final match = await (db.select(db.eventosCultivo)
                ..where((e) => e.cultivoId.equals(cultivoId))
                ..where((e) => e.descripcion.like('$descPrefix%'))
                ..where((e) => e.fechaEjecutada.isNull())
                ..where((e) => e.deletedAt.isNull())
                ..orderBy([(e) => OrderingTerm.asc(e.fechaProgramada)])
                ..limit(1))
              .getSingleOrNull();
          if (match != null) {
            await (db.update(db.eventosCultivo)
                  ..where((e) => e.id.equals(match.id)))
                .write(EventosCultivoCompanion(
              fechaEjecutada: Value(t.fecha),
              updatedAt: Value(DateTime.now()),
            ));
            cerrados++;
          }
        }
      }
      return cerrados;
    });
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}
