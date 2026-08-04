// NEXUS Siembras — Estado de datos (Fase 2g: cableado a Drift)
// Los providers exponen Streams reactivos sobre las tablas Drift.
// Las pantallas siguen usando las mismas clases UI-model (InvItem, Compra, Planta)
// para no romper la interfaz; hay adapters que las construyen desde los rows Drift.

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import '../core/models/ciclo_abono.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/reports/report_service.dart' show ReportPredio;
import '../data/database/database.dart' as drift;
import '../data/repositories/cultivo_repository.dart';
import '../data/repositories/inventory_repository.dart';
import '../data/repositories/patologia_repository.dart';
import '../data/repositories/trash_repository.dart';
import '../data/repositories/compra_repository.dart';
import '../data/repositories/planta_repository.dart';
import '../data/repositories/proveedor_repository.dart';
import '../data/repositories/predio_repository.dart';
import '../data/repositories/analisis_suelo_repository.dart';
import '../data/repositories/condiciones_predio_repository.dart';
import '../data/repositories/recomendacion_agronomica.dart';
import '../data/repositories/colaborador_repository.dart';
import '../data/repositories/lote_repository.dart';
import '../services/auto_sync_service.dart';
import '../services/account_service.dart';
import '../services/feedback_service.dart';
import '../services/backup_service.dart';
import '../services/event_notification_sync.dart';
import '../services/maintenance_service.dart';
import '../services/notification_service.dart';
import '../services/patologia_catalog_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import 'app_state.dart';
import 'auth_state.dart';

// ============ Modelos UI (idénticos a los de la fase in-memory) ============

class InvItem {
  InvItem({
    required this.id, required this.desc, required this.cod,
    required this.cantidad, required this.unidad,
    this.fabricante, required this.fecha,
  });
  int id;
  String desc;
  String cod;
  double cantidad;
  String unidad;
  String? fabricante;
  String fecha;

  factory InvItem.fromDrift(drift.Inventario i) => InvItem(
        id: i.id, desc: i.descripcion, cod: i.codigo ?? '',
        cantidad: i.cantidadBase, unidad: i.unidadBase,
        fabricante: i.fabricante,
        fecha: _iso(i.fecha),
      );
}

class Compra {
  Compra({
    required this.id, required this.fecha, required this.desc,
    this.desc2, required this.valor, required this.cantidad,
    required this.unidad, required this.cod, required this.factura,
    required this.proveedor, required this.tipo,
    this.plantaRef, this.soporteName, this.createdByUserId,
  });
  final int id;
  final String fecha, desc, cod, factura, proveedor, tipo, unidad;
  final String? desc2, soporteName;
  final String? createdByUserId;
  final double valor, cantidad;
  final int? plantaRef;

  factory Compra.fromDrift(drift.Compra c, String proveedorNombre) => Compra(
        id: c.id, fecha: _iso(c.fecha),
        desc: c.descripcion1, desc2: c.descripcion2,
        valor: c.valorTotal, cantidad: c.cantidadBase,
        unidad: c.unidadBase, cod: c.codigo ?? '',
        factura: c.factura ?? '', proveedor: proveedorNombre,
        tipo: c.tipo ?? 'otro',
        plantaRef: c.plantaRef,
        soporteName: c.soportePath,
        createdByUserId: c.createdByUserId,
      );
}

class Planta {
  const Planta({
    required this.id, required this.nombre, required this.especie,
    this.cosechaMin, this.cosechaMax,
    this.abono2Dias,
    required this.metodoSiembra,
    this.germinadorDias, required this.fuenteMetodo,
    this.tipoAbono1, this.tipoAbono2,
    this.tipoCultivoDefault = 'ciclo_unico',
    this.periodicidadCosechaDias,
    this.esperanzaVidaDias,
    this.ciclosAbono = const [],
    this.esComunidad = false,
    this.contribucionesComunidad,
  });
  final int id;
  final int? cosechaMin, cosechaMax, abono2Dias;
  final int? germinadorDias;
  final int? periodicidadCosechaDias, esperanzaVidaDias;
  final String nombre, especie, metodoSiembra, fuenteMetodo;
  final String tipoCultivoDefault;
  final String? tipoAbono1, tipoAbono2;
  final List<CicloAbono> ciclosAbono;
  /// Variedad del banco comunitario (caché local, solo lectura en listado).
  final bool esComunidad;
  final int? contribucionesComunidad;

  bool get esPerenneDefault => tipoCultivoDefault == 'perenne';
  String get tipoCultivoEtiqueta =>
      esPerenneDefault ? 'Cultivo perenne' : 'Ciclo único';

  /// Etiqueta para selectores (p. ej. agregar cultivo).
  String get nombreEnSelector =>
      esComunidad ? '$nombre (comunidad)' : nombre;

  factory Planta.fromDrift(drift.Planta p) => Planta(
        id: p.id,
        nombre: p.nombreComun,
        especie: p.especie ?? '',
        cosechaMin: p.tiempoCosechaMinDias,
        cosechaMax: p.tiempoCosechaMaxDias,
        abono2Dias: p.diasAbono2,
        metodoSiembra: p.metodoSiembra ?? 'directa',
        germinadorDias: p.germinadorDias,
        fuenteMetodo: p.fuenteMetodo ?? '',
        tipoAbono1: p.tipoAbono1,
        tipoAbono2: p.tipoAbono2,
        tipoCultivoDefault: p.tipoCultivoDefault,
        periodicidadCosechaDias: p.periodicidadCosechaDias,
        esperanzaVidaDias: p.esperanzaVidaDias,
        ciclosAbono: decodeCiclosAbonoJson(
          p.ciclosAbonoJson,
          tipoAbono1: p.tipoAbono1,
          tipoAbono2: p.tipoAbono2,
          diasAbono2: p.diasAbono2,
        ),
      );

  factory Planta.fromComunidadCache(drift.VariedadesComunitariasCacheData c) {
    final abonos = <CicloAbono>[];
    if (c.tipoAbono1 != null && c.tipoAbono1!.isNotEmpty) {
      abonos.add(CicloAbono(tipo: c.tipoAbono1!, dias: 0));
    }
    if (c.tipoAbono2 != null &&
        c.tipoAbono2!.isNotEmpty &&
        c.abono2Dias != null) {
      abonos.add(CicloAbono(tipo: c.tipoAbono2!, dias: c.abono2Dias!));
    }
    return Planta(
      id: -c.id,
      nombre: c.nombreComun,
      especie: c.especie ?? '',
      cosechaMin: c.cosechaMinDias,
      cosechaMax: c.cosechaMaxDias,
      abono2Dias: c.abono2Dias,
      metodoSiembra: c.metodoSiembra ?? 'directa',
      germinadorDias: c.germinadorDias,
      fuenteMetodo: c.fuente ?? 'Comunidad NEXUS',
      tipoAbono1: c.tipoAbono1,
      tipoAbono2: c.tipoAbono2,
      ciclosAbono: abonos,
      esComunidad: true,
      contribucionesComunidad: c.contribuciones,
    );
  }
}

class Cultivo {
  const Cultivo({
    required this.id, required this.predioId, required this.plantaId,
    required this.lote, required this.sembrado, required this.hh,
    this.horaValor, this.finalizadoFecha, this.lat, this.lng, this.altM,
    this.areaBaseM2, this.loteId,
    this.tipoCultivo = 'ciclo_unico',
    this.cosecha1Dias,
    this.cosecha2Dias,
    this.periodicidadCosechaDias,
    this.esperanzaVidaDias,
  });
  factory Cultivo.fromDrift(drift.Cultivo c) => Cultivo(
        id: c.id, predioId: c.predioId, plantaId: c.plantaId,
        lote: c.nombreLote ?? '',
        sembrado: _iso(c.fechaSiembra),
        hh: c.hhTotal,
        horaValor: c.horaValor,
        finalizadoFecha: c.finalizadoFecha != null ? _iso(c.finalizadoFecha!) : null,
        lat: c.lat, lng: c.lng, altM: c.altM,
        areaBaseM2: c.areaBaseM2,
        loteId: c.loteId,
        tipoCultivo: c.tipoCultivo,
        cosecha1Dias: c.cosecha1Dias,
        cosecha2Dias: c.cosecha2Dias,
        periodicidadCosechaDias: c.periodicidadCosechaDias,
        esperanzaVidaDias: c.esperanzaVidaDias,
      );
  final int id, predioId, plantaId;
  final String lote, sembrado;
  final double hh;
  final double? horaValor, lat, lng, altM, areaBaseM2;
  final int? loteId;
  final String? finalizadoFecha;
  final String tipoCultivo;
  final int? cosecha1Dias, cosecha2Dias, periodicidadCosechaDias, esperanzaVidaDias;
  bool get isFinalizado => finalizadoFecha != null;
  bool get esPerenne => tipoCultivo == 'perenne';

  String get tipoCultivoEtiqueta =>
      esPerenne ? 'Cultivo perenne' : 'Ciclo único';

  /// Líneas legibles de los periodos configurados al crear el cultivo.
  List<String> get lineasPeriodosConfigurados {
    if (esPerenne) {
      return [
        if (cosecha1Dias != null) 'Primera cosecha: $cosecha1Dias d',
        if (periodicidadCosechaDias != null)
          'Periodicidad: $periodicidadCosechaDias d',
        if (esperanzaVidaDias != null) 'Vida útil: $esperanzaVidaDias d',
      ];
    }
    return [
      if (cosecha1Dias != null) 'Cosecha 1: $cosecha1Dias d',
      if (cosecha2Dias != null) 'Cosecha 2: $cosecha2Dias d',
    ];
  }

  /// Resumen compacto para la lista de cultivos.
  String get resumenPeriodosCorto {
    final p = lineasPeriodosConfigurados;
    if (p.isEmpty) return tipoCultivoEtiqueta;
    return '$tipoCultivoEtiqueta · ${p.take(2).join(' · ')}';
  }
}

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

// ============ Providers de repositorios ============

final _inventoryRepoProvider = Provider<InventoryRepository>(
    (ref) => InventoryRepository(ref.watch(databaseProvider)));

final _compraRepoProvider = Provider<CompraRepository>((ref) => CompraRepository(
      ref.watch(databaseProvider),
      ref.watch(_inventoryRepoProvider),
    ));

final _plantaRepoProvider = Provider<PlantaRepository>(
    (ref) => PlantaRepository(ref.watch(databaseProvider)));

final _proveedorRepoProvider = Provider<ProveedorRepository>(
    (ref) => ProveedorRepository(ref.watch(databaseProvider)));

final _predioRepoProvider = Provider<PredioRepository>(
    (ref) => PredioRepository(ref.watch(databaseProvider)));

final _cultivoRepoProvider = Provider<CultivoRepository>(
    (ref) => CultivoRepository(ref.watch(databaseProvider)));

final _patologiaRepoProvider = Provider<PatologiaRepository>(
    (ref) => PatologiaRepository(ref.watch(databaseProvider)));

final _trashRepoProvider = Provider<TrashRepository>(
    (ref) => TrashRepository(ref.watch(databaseProvider)));

final _analisisRepoProvider = Provider<AnalisisSueloRepository>(
    (ref) => AnalisisSueloRepository(ref.watch(databaseProvider)));

final _condicionesRepoProvider = Provider<CondicionesPredioRepository>(
    (ref) => CondicionesPredioRepository(ref.watch(databaseProvider)));

final _loteRepoProvider = Provider<LoteRepository>(
    (ref) => LoteRepository(ref.watch(databaseProvider)));

final _colaboradorRepoProvider = Provider<ColaboradorRepository>(
    (ref) => ColaboradorRepository(ref.watch(databaseProvider)));

/// Colaboradores de un predio específico.
final colaboradoresPorPredioProvider =
    StreamProvider.family<List<drift.PredioColaboradore>, int>(
        (ref, predioId) {
  return ref.watch(_colaboradorRepoProvider).watchPorPredio(predioId);
});

/// True si el usuario actual es el propietario del predio.
///
/// Reglas (orden de prioridad):
///   - Sin sesión Supabase (modo local puro) → true.
///   - `predio.ownerUserId` está poblado → comparo con mi user_id.
///   - `predio.ownerUserId` es null pero tengo en local una entrada de
///     colaborador con rol='propietario' cuyo user_id NO es el mío →
///     soy invitado (fallback antes de que corra el backfill).
///   - En cualquier otro caso → soy dueño (fue creado localmente).
final soyPropietarioPredioProvider =
    Provider.family<bool, int>((ref, predioId) {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) return true;
  final predios = ref.watch(prediosProvider).maybeWhen(
      data: (l) => l, orElse: () => const <drift.Predio>[]);
  final p = predios.where((x) => x.id == predioId).cast<drift.Predio?>()
      .firstOrNull;
  if (p == null) return true;
  if (p.ownerUserId != null) return p.ownerUserId == currentUser.id;
  // Fallback: revisar el listado local de colaboradores del predio.
  final colabs = ref
      .watch(colaboradoresPorPredioProvider(predioId))
      .maybeWhen(data: (l) => l, orElse: () => const []);
  final tieneOtroPropietario = colabs.any((c) =>
      c.rol == 'propietario' &&
      c.colaboradorUserId != null &&
      c.colaboradorUserId != currentUser.id);
  return !tieneOtroPropietario;
});

extension _FirstOrNullList<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Rol del usuario actual sobre un predio dado. Devuelve uno de:
///   - `'propietario'` — el usuario creó el predio o es el owner_id remoto.
///   - `'trabajador'` — invitado como colaborador con rol='trabajador'.
///   - `'consultor'`  — invitado como colaborador con rol='consultor'.
///   - `null`         — el usuario no tiene ningún vínculo con este predio.
///
/// Consulta la BD local (no golpea red). En modo local puro (sin sesión
/// Supabase) devuelve siempre `'propietario'` — hay un solo usuario.
final rolEnPredioProvider =
    Provider.family<String?, int>((ref, predioId) {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) return 'propietario'; // modo local
  if (ref.watch(soyPropietarioPredioProvider(predioId))) {
    return 'propietario';
  }
  final colabs = ref
      .watch(colaboradoresPorPredioProvider(predioId))
      .maybeWhen(data: (l) => l, orElse: () => const []);
  final miShare = colabs.where((c) =>
      c.colaboradorUserId == currentUser.id && c.deletedAt == null).firstOrNull;
  return miShare?.rol;
});

/// Rol del usuario actual sobre el predio ACTIVO. Alias práctico para la UI
/// que casi siempre razona sobre el predio activo.
final rolEnPredioActivoProvider = Provider<String?>((ref) {
  final predioId = ref.watch(activePredioIdProvider);
  return ref.watch(rolEnPredioProvider(predioId));
});

/// Matriz de permisos por recurso, derivada del rol. Ver README §
/// "Modelo de datos → Reglas de acceso resumidas". Un consultor es
/// siempre solo-lectura; un trabajador puede editar cultivos/eventos/
/// tareas/inventario pero no compras/colaboradores/predio/lotes/suelo/
/// condiciones. El propietario (dueño o colaborador invitado como
/// propietario) puede todo, incluidas compras.
class PermisosPredio {
  const PermisosPredio({
    required this.rol,
    required this.esPropietario,
    required this.puedeVer,
    required this.puedeVerCompras,
    required this.puedeEditarPredioYLotes,
    required this.puedeEditarCultivosYTareas,
    required this.puedeEditarInventario,
    required this.puedeEditarCompras,
    required this.puedeEditarSueloYCondiciones,
    required this.puedeEditarColaboradores,
  });

  final String? rol; // 'propietario' | 'trabajador' | 'consultor' | null
  final bool esPropietario;
  final bool puedeVer;
  /// Compras: solo rol `propietario` (dueño o co-propietario invitado).
  final bool puedeVerCompras;
  final bool puedeEditarPredioYLotes;
  final bool puedeEditarCultivosYTareas;
  final bool puedeEditarInventario;
  final bool puedeEditarCompras;
  final bool puedeEditarSueloYCondiciones;
  final bool puedeEditarColaboradores;

  bool get esSoloLectura => rol == 'consultor';
  bool get esTrabajador => rol == 'trabajador';

  static PermisosPredio fromRol(String? rol) {
    final esPropietario = rol == 'propietario';
    final esTrabajador = rol == 'trabajador';
    final tieneAcceso = rol != null;
    return PermisosPredio(
      rol: rol,
      esPropietario: esPropietario,
      puedeVer: tieneAcceso,
      puedeVerCompras: esPropietario,
      puedeEditarPredioYLotes: esPropietario,
      puedeEditarCultivosYTareas: esPropietario || esTrabajador,
      puedeEditarInventario: esPropietario || esTrabajador,
      puedeEditarCompras: esPropietario,
      puedeEditarSueloYCondiciones: esPropietario,
      puedeEditarColaboradores: esPropietario,
    );
  }
}

/// Permisos del usuario sobre un predio arbitrario.
final permisosPredioProvider =
    Provider.family<PermisosPredio, int>((ref, predioId) {
  final rol = ref.watch(rolEnPredioProvider(predioId));
  return PermisosPredio.fromRol(rol);
});

/// Permisos del usuario sobre el predio ACTIVO. Alias práctico para la UI.
final permisosPredioActivoProvider = Provider<PermisosPredio>((ref) {
  final rol = ref.watch(rolEnPredioActivoProvider);
  return PermisosPredio.fromRol(rol);
});

/// Sincronizador de notificaciones locales con eventos programados.
final eventNotificationSyncProvider = Provider<EventNotificationSync>(
    (ref) => EventNotificationSync(ref.watch(databaseProvider)));

/// Servicio de backup/restore JSON.
final backupServiceProvider = Provider<BackupService>(
    (ref) => BackupService(ref.watch(databaseProvider)));

/// Servicio de sincronización Supabase push/pull.
final syncServiceProvider = Provider<SyncService>(
    (ref) => SyncService(ref.watch(databaseProvider)));

/// Fase 3i: servicio para actualizar el catálogo de patologías desde asset.
final patologiaCatalogServiceProvider = Provider<PatologiaCatalogService>(
    (ref) => PatologiaCatalogService(ref.watch(databaseProvider)));

/// Servicio de mantenimiento de BD (depurar local + reemplazar nube).
final maintenanceServiceProvider = Provider<MaintenanceService>((ref) {
  return MaintenanceService(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
  );
});

/// Eliminación de cuenta (RPC remoto + wipe/limpieza local).
final accountServiceProvider = Provider<AccountService>(
    (ref) => AccountService(ref.watch(databaseProvider)));

/// Micro-encuestas de feedback (C2-9): cola local + envío diferido.
final feedbackServiceProvider = Provider<FeedbackService>(
    (ref) => FeedbackService(ref.watch(databaseProvider)));

/// Encuestas guardadas aún sin subir al servidor (badge en la pantalla).
final feedbackPendientesProvider = FutureProvider<int>((ref) async {
  return ref.watch(feedbackServiceProvider).contarPendientes();
});

/// Servicio de auto-retry de sync al recuperar conexión.
/// Debe `iniciar()`se en un widget listener (app.dart) tras auth OK.
final autoSyncServiceProvider = Provider<AutoSyncService>((ref) {
  final srv = AutoSyncService(
    ref.watch(syncServiceProvider),
    feedback: ref.watch(feedbackServiceProvider), // C2-9
  );
  ref.onDispose(srv.detener);
  return srv;
});

/// Contador reactivo de cambios locales pendientes por subir a la nube.
/// Se re-evalúa al cambiar cualquier stream operativo (cultivos, inventario,
/// etc.), lo que asegura que el badge del AppBar se actualice al instante.
final pendingSyncCountProvider = FutureProvider<int>((ref) async {
  // Toca streams para que el provider se re-ejecute cuando cambien datos
  ref.watch(cultivosActivosProvider);
  ref.watch(cultivosFinalizadosProvider);
  ref.watch(inventoryProvider);
  ref.watch(comprasProvider);
  ref.watch(analisisSueloProvider);
  ref.watch(lotesActivosProvider);
  ref.watch(prediosProvider);
  ref.watch(proveedoresDriftProvider);
  return await ref.read(syncServiceProvider).contarPendientes();
});

/// Catálogo de países.
final paisesProvider = StreamProvider<List<drift.Paise>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.paises)..orderBy([(p) => OrderingTerm.asc(p.nombre)]))
      .watch();
});

/// Regiones de un país.
final regionesProvider =
    StreamProvider.family<List<drift.Regione>, int>((ref, paisId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.regiones)
        ..where((r) => r.paisId.equals(paisId))
        ..orderBy([(r) => OrderingTerm.asc(r.nombre)]))
      .watch();
});

/// Municipios de una región.
final municipiosProvider =
    StreamProvider.family<List<drift.Municipio>, int>((ref, regionId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.municipios)
        ..where((m) => m.regionId.equals(regionId))
        ..orderBy([(m) => OrderingTerm.asc(m.nombre)]))
      .watch();
});

/// Espejo local del banco comunitario de variedades (Supabase).
final variedadesComunitariasCacheProvider =
    StreamProvider<List<drift.VariedadesComunitariasCacheData>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.variedadesComunitariasCache)
        ..orderBy([
          (v) => OrderingTerm.desc(v.contribuciones),
          (v) => OrderingTerm.asc(v.nombreComun),
        ]))
      .watch();
});

/// Papelera del predio activo — refresca al cambiar cualquier stream reactivo.
final papeleraProvider = FutureProvider<List<TrashItem>>((ref) async {
  // Toca los otros streams para que la papelera se re-evalúe cuando cambien.
  ref.watch(cultivosActivosProvider);
  ref.watch(cultivosFinalizadosProvider);
  ref.watch(inventoryProvider);
  ref.watch(comprasProvider);
  final predioId = ref.watch(activePredioIdProvider);
  return await ref.read(_trashRepoProvider).getByPredio(predioId);
});

/// Catálogo de patologías conocidas.
final patologiasCatalogoProvider =
    StreamProvider<List<drift.Patologia>>((ref) {
  return ref.watch(_patologiaRepoProvider).watchCatalogo();
});

/// Mapa: patologiaId -> nombres de plantas afectadas (según planta_patologias).
final patologiasPorPlantasProvider =
    StreamProvider<Map<int, List<String>>>((ref) {
  return ref.watch(_patologiaRepoProvider).watchPatologiasPorPlantas();
});

/// Detecciones activas por cultivo del predio.
final patologiasActivasProvider =
    StreamProvider<List<drift.CultivoPatologia>>((ref) {
  final cultivos = ref.watch(cultivosActivosProvider);
  return ref
      .watch(_patologiaRepoProvider)
      .watchActivasPredio(cultivos.map((c) => c.id).toList());
});

/// Fase 3e-5: detecciones activas de UN cultivo específico.
final patologiasActivasCultivoProvider =
    StreamProvider.family<List<drift.CultivoPatologia>, int>((ref, cultivoId) {
  return ref
      .watch(_patologiaRepoProvider)
      .watchActivasPredio([cultivoId]);
});

// ============================================================
// Fase 3e-8 — Tratamientos por patología (con filtro por país)
// ============================================================

/// Tratamientos recomendados para una patología, ordenados con esta
/// prioridad:
///   1. Los del país del predio activo (regulación/disponibilidad local).
///   2. Los globales (paisIso2=null).
///   3. Los de otros países (referencia).
///
/// Dentro de cada grupo, se ordenan por sostenibilidad (alta primero) y
/// tipo (culturales, biológicos, orgánicos, químicos).
final tratamientosPorPatologiaProvider =
    StreamProvider.family<List<drift.TratamientosPatologia>, int>(
        (ref, patologiaId) async* {
  final db = ref.watch(databaseProvider);
  final paisAct = await ref.watch(predioActivoIsoProvider.future);
  final stream = (db.select(db.tratamientosPatologias)
        ..where((t) => t.patologiaId.equals(patologiaId))
        ..where((t) => t.deletedAt.isNull()))
      .watch();
  const ordenTipo = {
    'cultural': 0,
    'preventivo': 1,
    'biologico': 2,
    'organico': 3,
    'quimico': 4,
  };
  const ordenSost = {'alta': 0, 'media': 1, 'baja': 2};
  await for (final list in stream) {
    final ordenada = [...list]..sort((a, b) {
        // 1. País: activo > global > otros
        int prioridadPais(String? p) {
          if (p == null || p.isEmpty) return 1;
          if (p == paisAct) return 0;
          return 2;
        }

        final dp = prioridadPais(a.paisIso2).compareTo(prioridadPais(b.paisIso2));
        if (dp != 0) return dp;
        // 2. Sostenibilidad: alta > media > baja
        final ds = (ordenSost[a.sostenibilidad] ?? 3)
            .compareTo(ordenSost[b.sostenibilidad] ?? 3);
        if (ds != 0) return ds;
        // 3. Tipo: cultural > preventivo > biológico > orgánico > químico
        final dt = (ordenTipo[a.tipo] ?? 5).compareTo(ordenTipo[b.tipo] ?? 5);
        if (dt != 0) return dt;
        return a.nombreCorto.compareTo(b.nombreCorto);
      });
    yield ordenada;
  }
});

// ============================================================
// Fase 3e-6 — Mapa con capas
// ============================================================

/// Cultivos activos de todos los predios accesibles al usuario (dueño
/// + colaborador). Usado por la capa "Todos mis cultivos" del mapa.
final todosCultivosActivosStreamProvider =
    StreamProvider<List<drift.Cultivo>>((ref) {
  return ref.watch(_cultivoRepoProvider).watchTodosActivos();
});

/// Solo cultivos con coordenadas GNSS válidas. Retorna el modelo UI
/// `Cultivo` (state) — no el `drift.Cultivo` — para poder usarse
/// directamente en widgets que esperan el modelo compartido.
final todosCultivosGeorreferenciadosProvider =
    Provider<List<Cultivo>>((ref) {
  return ref.watch(todosCultivosActivosStreamProvider).maybeWhen(
        data: (l) => l
            .where((c) => c.lat != null && c.lng != null)
            .map(Cultivo.fromDrift)
            .toList(),
        orElse: () => const <Cultivo>[],
      );
});

/// Días sin actividad tras los que un foco pasa a «desatendido» (gris).
/// Debe coincidir con `app_config.patologia_dias_desatendida` (0018).
const int kDiasDesatendida = 60;

/// Punto para el heatmap de patologías con info detallada para el
/// bottom sheet de "zonas calientes" (Fase 3e-7).
class PuntoPatologia {
  final double lat;
  final double lng;
  final String severidad; // inicial | avanzada | ""
  final String patologiaNombre;
  final int? patologiaId;       // id local del catálogo, para linkear tratamientos
  final DateTime fecha;
  final String? fotoPath;       // path local de la foto, si existe
  final int? cultivoId;         // id local si es CultivoPatologia propia
  final bool comunitario;       // true si viene de PatologiasReportadas
  final String? plantaNombre;   // solo para reportes comunitarios
  final String? notas;          // síntomas/observaciones
  /// Última señal de vida del foco (reporte cercano o intervención del
  /// administrador). Null = usar `fecha`. Ver migración 0018.
  final DateTime? ultimaActividad;

  const PuntoPatologia({
    required this.lat,
    required this.lng,
    required this.severidad,
    required this.patologiaNombre,
    this.patologiaId,
    required this.fecha,
    this.fotoPath,
    this.cultivoId,
    this.comunitario = false,
    this.plantaNombre,
    this.notas,
    this.ultimaActividad,
  });

  /// Días transcurridos sin actividad en el foco.
  int get diasSinActividad =>
      DateTime.now().difference(ultimaActividad ?? fecha).inDays;

  /// Un foco se considera «desatendido» tras [kDiasDesatendida] días sin
  /// señales: ni reportes nuevos en coordenadas cercanas, ni intervención
  /// del administrador. Se pinta gris en el mapa (decisión 2026-08-04).
  bool get desatendida => diasSinActividad >= kDiasDesatendida;

  /// Etiqueta corta para chips/marker tooltips.
  String get etiquetaCorta {
    final f =
        '${fecha.year}-${fecha.month.toString().padLeft(2, "0")}-${fecha.day.toString().padLeft(2, "0")}';
    return '$patologiaNombre · $f';
  }
}

/// Puntos de patologías reportadas para el heatmap:
///   - CultivoPatologias del predio activo, no curadas, con lat/lng
///   - PatologiasReportadas (todos los reportes comunitarios locales)
final heatmapPatologiasProvider =
    Provider<List<PuntoPatologia>>((ref) {
  final salida = <PuntoPatologia>[];

  // 1) Detecciones propias activas del predio.
  //    Fallback en cascada para las coordenadas:
  //      reporte (cp.lat) → cultivo (cul.lat) → centroide del lote asignado
  //    Así reportes/cultivos sin GNSS específico siguen siendo visibles en
  //    el heatmap mientras exista información espacial arriba en la cadena.
  final activas = ref.watch(patologiasActivasProvider).maybeWhen(
      data: (l) => l, orElse: () => const <drift.CultivoPatologia>[]);
  final catalogo = ref.watch(patologiasCatalogoProvider).maybeWhen(
      data: (l) => l, orElse: () => const <drift.Patologia>[]);
  final catalogoById = {for (final p in catalogo) p.id: p};
  final cultivosActivos = ref.watch(cultivosActivosProvider);
  final cultivosFinal = ref.watch(cultivosFinalizadosProvider);
  final cultivoById = <int, Cultivo>{
    for (final c in cultivosActivos) c.id: c,
    for (final c in cultivosFinal) c.id: c,
  };
  final lotes = ref.watch(lotesActivosProvider).maybeWhen(
      data: (l) => l, orElse: () => const <drift.Lote>[]);
  final loteById = {for (final l in lotes) l.id: l};
  for (final cp in activas) {
    double? lat = cp.lat;
    double? lng = cp.lng;
    if (lat == null || lng == null) {
      final cul = cultivoById[cp.cultivoId];
      lat = cul?.lat;
      lng = cul?.lng;
      if ((lat == null || lng == null) && cul?.loteId != null) {
        final centro = centroideDeLote(loteById[cul!.loteId!]);
        if (centro != null) {
          lat = centro.lat;
          lng = centro.lng;
        }
      }
    }
    if (lat == null || lng == null) continue; // sin coords → invisible
    final nombre = cp.patologiaId != null
        ? (catalogoById[cp.patologiaId]?.nombreComun ?? 'Patología')
        : 'Patología';
    salida.add(PuntoPatologia(
      lat: lat,
      lng: lng,
      severidad: cp.severidad ?? '',
      patologiaNombre: nombre,
      patologiaId: cp.patologiaId,
      fecha: cp.fechaDeteccion,
      fotoPath: cp.fotoPath,
      cultivoId: cp.cultivoId,
      comunitario: false,
      notas: cp.notas,
      ultimaActividad: cp.updatedAt,
    ));
  }

  // 2) Reportes comunitarios (PatologiasReportadas) locales.
  final async = ref.watch(_patologiasReportadasStreamProvider);
  final reportados = async.maybeWhen(
      data: (l) => l, orElse: () => const <drift.PatologiasReportada>[]);
  // Índice por nombre para resolver patologiaId de reportes comunitarios
  // (que solo guardan el nombre denormalizado).
  final catalogoByNombre = <String, drift.Patologia>{
    for (final p in catalogo) p.nombreComun.toLowerCase(): p,
  };
  for (final pr in reportados) {
    if (pr.deletedAt != null) continue;
    final patLocal = catalogoByNombre[pr.patologiaNombre.toLowerCase()];
    salida.add(PuntoPatologia(
      lat: pr.lat,
      lng: pr.lng,
      severidad: pr.severidad ?? '',
      patologiaNombre: pr.patologiaNombre,
      patologiaId: patLocal?.id,
      fecha: pr.fechaDeteccion,
      fotoPath: pr.fotoLocalPath,
      comunitario: true,
      plantaNombre: pr.plantaNombre,
      notas: pr.sintomas,
      ultimaActividad: pr.ultimaActividadAt ?? pr.updatedAt,
    ));
  }
  return salida;
});

/// Calcula el centroide de un lote a partir de su `poligonoGeoJson`
/// (JSON array de pares `[lat, lng]`). Retorna null si el polígono es
/// inválido o el lote es null.
///
/// Se usa como fallback de coordenadas: si un cultivo o un reporte de
/// patología no tiene GNSS propio pero está asignado a un lote con
/// polígono, se usa este centroide para posicionarlo en el mapa.
({double lat, double lng})? centroideDeLote(drift.Lote? lote) {
  if (lote == null) return null;
  final json = lote.poligonoGeoJson;
  if (json == null || json.isEmpty) return null;
  try {
    final list = jsonDecode(json) as List<dynamic>;
    double sumLat = 0, sumLng = 0;
    var n = 0;
    for (final item in list) {
      if (item is List && item.length >= 2) {
        sumLat += (item[0] as num).toDouble();
        sumLng += (item[1] as num).toDouble();
        n++;
      }
    }
    if (n == 0) return null;
    return (lat: sumLat / n, lng: sumLng / n);
  } catch (_) {
    return null;
  }
}

/// Stream de PatologiasReportadas locales (todos, incluidos los de otros
/// predios sincronizados desde la comunidad).
final _patologiasReportadasStreamProvider =
    StreamProvider<List<drift.PatologiasReportada>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.patologiasReportadas)
        ..where((r) => r.deletedAt.isNull()))
      .watch();
});

/// Detecciones curadas históricas.
final patologiasHistoricoProvider =
    StreamProvider<List<drift.CultivoPatologia>>((ref) {
  final cultivos = ref.watch(cultivosActivosProvider) +
      ref.watch(cultivosFinalizadosProvider);
  return ref
      .watch(_patologiaRepoProvider)
      .watchHistoricoPredio(cultivos.map((c) => c.id).toList());
});

// ============ Predios y lotes ============

/// Listado de todos los predios (para pantalla /predios).
final prediosProvider = StreamProvider<List<drift.Predio>>((ref) {
  return ref.watch(_predioRepoProvider).watchAll();
});

/// Lotes de un predio específico.
final lotesPorPredioProvider =
    StreamProvider.family<List<drift.Lote>, int>((ref, predioId) {
  return ref.watch(_loteRepoProvider).watchByPredio(predioId);
});

/// Lotes del predio activo.
final lotesActivosProvider = StreamProvider<List<drift.Lote>>((ref) {
  final predioId = ref.watch(activePredioIdProvider);
  return ref.watch(_loteRepoProvider).watchByPredio(predioId);
});

/// Código ISO2 del país del predio activo (ej: 'CO' para Colombia).
/// Retorna null si el predio activo no tiene país asignado.
/// Se usa para habilitar/deshabilitar servicios geográficos abiertos
/// específicos de cada país (ej: Catastro IGAC solo aplica en Colombia).
final predioActivoIsoProvider = FutureProvider<String?>((ref) async {
  final predioId = ref.watch(activePredioIdProvider);
  final db = ref.watch(databaseProvider);
  final predio = await (db.select(db.predios)
        ..where((p) => p.id.equals(predioId)))
      .getSingleOrNull();
  if (predio?.paisId == null) return null;
  final pais = await (db.select(db.paises)
        ..where((p) => p.id.equals(predio!.paisId!)))
      .getSingleOrNull();
  return pais?.iso2;
});

// ============ Análisis de suelo / condiciones edafoclim ============

/// Análisis de suelo del predio activo (ordenados por fecha desc).
final analisisSueloProvider =
    StreamProvider<List<drift.AnalisisSueloData>>((ref) {
  final predioId = ref.watch(activePredioIdProvider);
  return ref.watch(_analisisRepoProvider).watchByPredio(predioId);
});

/// Condiciones edafoclimáticas del predio activo (nullable si no configurado).
final condicionesPredioProvider =
    StreamProvider<drift.CondicionesPredioData?>((ref) {
  final predioId = ref.watch(activePredioIdProvider);
  return ref.watch(_condicionesRepoProvider).watchByPredio(predioId);
});

/// Recomendación agronómica para un cultivo específico. Se basa en:
///  - Planta del cultivo (requerimientos)
///  - Último análisis de suelo del predio
///  - Condiciones edafoclimáticas del predio
final recomendacionCultivoProvider =
    FutureProvider.family<RecomendacionAgronomica?, int>((ref, cultivoId) async {
  // Encuentra el cultivo activo o finalizado
  final activos = ref.watch(cultivosActivosProvider);
  final finalizados = ref.watch(cultivosFinalizadosProvider);
  final all = [...activos, ...finalizados];
  final cul = all.where((c) => c.id == cultivoId).firstOrNull;
  if (cul == null) return null;
  // Planta como fila Drift
  final db = ref.watch(databaseProvider);
  final planta = await (db.select(db.plantas)
        ..where((p) => p.id.equals(cul.plantaId)))
      .getSingleOrNull();
  if (planta == null) return null;
  final predioId = ref.watch(activePredioIdProvider);
  final analisis = await ref
      .watch(_analisisRepoProvider)
      .ultimoDelPredio(predioId, lote: cul.lote);
  final cond = await ref.watch(_condicionesRepoProvider).byPredio(predioId);
  final areaHa =
      cul.areaBaseM2 == null ? null : (cul.areaBaseM2! / 10000.0);
  return MotorRecomendaciones.evaluar(
    planta: planta,
    analisis: analisis,
    condiciones: cond,
    areaHa: areaHa,
  );
});

// ============ Predio activo ============

/// Config persistida en la BD. Stream reactivo.
/// Encabezado de reportes con los datos REALES del predio activo
/// (2026-07-20 — antes los exports usaban valores fijos de ejemplo).
final reportPredioProvider = FutureProvider<ReportPredio>((ref) async {
  final db = ref.watch(databaseProvider);
  final predioId = ref.watch(activePredioIdProvider);
  final predio = await (db.select(db.predios)
        ..where((p) => p.id.equals(predioId)))
      .getSingleOrNull();
  if (predio == null) return const ReportPredio(nombre: 'Predio');
  final mun = predio.municipioId == null
      ? null
      : (await (db.select(db.municipios)
                ..where((m) => m.id.equals(predio.municipioId!)))
              .getSingleOrNull())
          ?.nombre;
  final reg = predio.regionId == null
      ? null
      : (await (db.select(db.regiones)
                ..where((r) => r.id.equals(predio.regionId!)))
              .getSingleOrNull())
          ?.nombre;
  final pais = predio.paisId == null
      ? null
      : (await (db.select(db.paises)
                ..where((x) => x.id.equals(predio.paisId!)))
              .getSingleOrNull())
          ?.nombre;
  return ReportPredio(
    nombre: predio.nombre,
    municipio: mun,
    region: reg,
    pais: pais,
    propietario: predio.propietario,
  );
});

final configProvider = StreamProvider<drift.Config?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.configs)..limit(1)).watchSingleOrNull();
});

/// ID del predio activo, reactivo a cambios en la tabla `configs`.
/// Cambia automáticamente después del onboarding y cuando el usuario
/// cambia de predio activo desde la UI.
final activePredioIdProvider = Provider<int>((ref) {
  final cfg = ref.watch(configProvider);
  return cfg.maybeWhen(
    data: (row) => row?.predioActivoId ?? 1,
    orElse: () => 1,
  );
});

/// True mientras el usuario no haya completado el onboarding.
final primeraEjecucionProvider = Provider<bool>((ref) {
  final cfg = ref.watch(configProvider);
  return cfg.maybeWhen(
    data: (row) => row?.primeraEjecucion ?? true,
    orElse: () => true,
  );
});

// ============ Streams de datos ============

/// Lista de proveedores desde Drift.
final proveedoresDriftProvider =
    StreamProvider<List<drift.Proveedore>>((ref) {
  return ref.watch(_proveedorRepoProvider).watchAll();
});

/// Set de nombres de proveedores para Autocomplete.
final proveedoresProvider = Provider<Set<String>>((ref) {
  return ref
          .watch(proveedoresDriftProvider)
          .maybeWhen(
            data: (list) => list.map((p) => p.nombre).toSet(),
            orElse: () => <String>{},
          );
});

/// Lista de plantas (catálogo) desde Drift.
final plantasProvider = Provider<List<Planta>>((ref) {
  return ref.watch(_plantasStreamProvider).maybeWhen(
        data: (list) => list.map(Planta.fromDrift).toList(),
        orElse: () => <Planta>[],
      );
});

/// Catálogo propio + variedades comunitarias en caché local (sin duplicar
/// por nombre+especie). Las comunitarias van después de las propias.
final plantasListadoProvider = Provider<List<Planta>>((ref) {
  final propias = ref.watch(plantasProvider);
  final cache =
      ref.watch(variedadesComunitariasCacheProvider).valueOrNull ?? const [];
  final clavesPropias = {
    for (final p in propias)
      '${p.nombre.toLowerCase()}|${p.especie.toLowerCase()}',
  };
  final comunidad = <Planta>[];
  for (final c in cache) {
    final key =
        '${c.nombreComun.toLowerCase()}|${(c.especie ?? '').toLowerCase()}';
    if (clavesPropias.contains(key)) continue;
    comunidad.add(Planta.fromComunidadCache(c));
  }
  return [...propias, ...comunidad];
});

final _plantasStreamProvider =
    StreamProvider<List<drift.Planta>>((ref) => ref.watch(_plantaRepoProvider).watchAll());

/// Fase 3h: número de patologías asociadas a una planta (via PlantaPatologias).
final patologiasAsociadasCountProvider =
    FutureProvider.family<int, int>((ref, plantaId) {
  return ref.watch(_plantaRepoProvider).countPatologiasAsociadas(plantaId);
});

/// Inventario del predio activo, adaptado a InvItem.
final inventoryProvider = Provider<List<InvItem>>((ref) {
  final predioId = ref.watch(activePredioIdProvider);
  return ref.watch(_inventoryStreamProvider(predioId)).maybeWhen(
        data: (list) => list.map(InvItem.fromDrift).toList(),
        orElse: () => <InvItem>[],
      );
});

final _inventoryStreamProvider =
    StreamProvider.family<List<drift.Inventario>, int>((ref, predioId) {
  return ref.watch(_inventoryRepoProvider).watchByPredio(predioId);
});

/// Compras del predio activo con nombre de proveedor resuelto.
/// Solo visible para rol `propietario` (dueño o co-propietario invitado).
final comprasProvider = Provider<List<Compra>>((ref) {
  if (!ref.watch(permisosPredioActivoProvider).puedeVerCompras) {
    return const [];
  }
  final predioId = ref.watch(activePredioIdProvider);
  final rows = ref.watch(_comprasStreamProvider(predioId)).valueOrNull ?? const [];
  final provs = ref.watch(proveedoresDriftProvider).valueOrNull ?? const [];
  final byId = {for (final p in provs) p.id: p.nombre};
  return rows
      .map((c) => Compra.fromDrift(c,
          byId[c.proveedorId ?? -1] ?? (c.proveedorId != null ? 'Prov #${c.proveedorId}' : 'Sin proveedor')))
      .toList();
});

final _comprasStreamProvider =
    StreamProvider.family<List<drift.Compra>, int>((ref, predioId) {
  return ref.watch(_compraRepoProvider).watchByPredio(predioId);
});

/// Cultivos activos (no finalizados, no eliminados) del predio.
final cultivosActivosProvider = Provider<List<Cultivo>>((ref) {
  final predioId = ref.watch(activePredioIdProvider);
  return ref.watch(_cultivosActivosStream(predioId)).maybeWhen(
        data: (list) => list.map(Cultivo.fromDrift).toList(),
        orElse: () => <Cultivo>[],
      );
});

final _cultivosActivosStream =
    StreamProvider.family<List<drift.Cultivo>, int>((ref, predioId) {
  return ref.watch(_cultivoRepoProvider).watchActivosByPredio(predioId);
});

/// Cultivos finalizados del predio.
final cultivosFinalizadosProvider = Provider<List<Cultivo>>((ref) {
  final predioId = ref.watch(activePredioIdProvider);
  return ref.watch(_cultivosFinStream(predioId)).maybeWhen(
        data: (list) => list.map(Cultivo.fromDrift).toList(),
        orElse: () => <Cultivo>[],
      );
});

final _cultivosFinStream =
    StreamProvider.family<List<drift.Cultivo>, int>((ref, predioId) {
  return ref.watch(_cultivoRepoProvider).watchFinalizadosByPredio(predioId);
});

/// Estado (verde/naranja/rojo) calculado on-demand por ID de cultivo.
///
/// Reactivo: se recalcula automáticamente cuando cambian las patologías
/// activas o los eventos del cultivo. Sin estos watches el FutureProvider
/// quedaba cacheado y el StatusDot no reflejaba nuevas patologías.
final estadoCultivoProvider =
    FutureProvider.family<EstadoInfo, int>((ref, cultivoId) {
  // Trigger de invalidación cuando cambia algo relevante.
  ref.watch(patologiasActivasProvider);
  ref.watch(_eventosStreamByPredio(ref.watch(activePredioIdProvider)));
  return ref.watch(_cultivoRepoProvider).computarEstado(cultivoId);
});

// ============ Modelos UI de eventos y tareas ============

class Evento {
  const Evento({
    required this.id, required this.cultivoId, required this.tipo,
    required this.descripcion, required this.fechaProgramada,
    this.fechaEjecutada,
  });
  factory Evento.fromDrift(drift.EventosCultivoData e) => Evento(
        id: e.id, cultivoId: e.cultivoId, tipo: e.tipo,
        descripcion: e.descripcion ?? '',
        fechaProgramada: e.fechaProgramada ?? DateTime.now(),
        fechaEjecutada: e.fechaEjecutada,
      );
  final int id, cultivoId;
  final String tipo, descripcion;
  final DateTime fechaProgramada;
  final DateTime? fechaEjecutada;
  bool get ejecutada => fechaEjecutada != null;
  DateTime get fechaEfectiva => fechaEjecutada ?? fechaProgramada;
}

class InsumoUsado {
  const InsumoUsado({required this.desc, required this.cantidad, required this.unidad});
  final String desc;
  final double cantidad;
  final String unidad;
  Map<String, dynamic> toJson() => {'desc': desc, 'cantidad': cantidad, 'unidad': unidad};
}

class TareaCompletada {
  const TareaCompletada({
    required this.id, required this.cultivoId, required this.fecha,
    required this.hh, required this.actividades,
    this.insumos = const [], this.notas,
    this.createdByUserId,
  });
  factory TareaCompletada.fromDrift(drift.TareasCompletada t) {
    List<String> acts = [];
    try {
      acts = (jsonDecode(t.actividadesJson) as List).cast<String>();
    } catch (_) {}
    List<InsumoUsado> ins = [];
    try {
      final list = jsonDecode(t.insumosJson) as List<dynamic>;
      ins = list.whereType<Map>().map((m) => InsumoUsado(
            desc: m['desc']?.toString() ?? '',
            cantidad: (m['cantidad'] as num?)?.toDouble() ?? 0,
            unidad: m['unidad']?.toString() ?? '',
          )).toList();
    } catch (_) {}
    return TareaCompletada(
      id: t.id, cultivoId: t.cultivoId, fecha: t.fecha,
      hh: t.hh, actividades: acts, insumos: ins, notas: t.notas,
      createdByUserId: t.createdByUserId,
    );
  }
  final int id, cultivoId;
  final DateTime fecha;
  final double hh;
  final List<String> actividades;
  final List<InsumoUsado> insumos;
  final String? notas;
  /// UUID Supabase del autor (Fase 3g). Null = tarea legacy o modo local.
  final String? createdByUserId;
}

/// Todos los eventos de cultivos activos del predio (Drift stream con JOIN).
final eventosPredioProvider = Provider<List<Evento>>((ref) {
  final predioId = ref.watch(activePredioIdProvider);
  final asyncEvs = ref.watch(_eventosStreamByPredio(predioId));
  return asyncEvs.maybeWhen(
    data: (list) => list.map(Evento.fromDrift).toList(),
    orElse: () => const <Evento>[],
  );
});

/// Eventos del cronograma de un cultivo, ordenados por fecha efectiva.
final eventosCultivoProvider = Provider.family<List<Evento>, int>((ref, cultivoId) {
  final eventos = ref.watch(eventosPredioProvider)
      .where((e) => e.cultivoId == cultivoId)
      .toList();
  eventos.sort((a, b) => a.fechaEfectiva.compareTo(b.fechaEfectiva));
  return eventos;
});

final _eventosStreamByPredio =
    StreamProvider.family<List<drift.EventosCultivoData>, int>((ref, predioId) {
  return ref.watch(_cultivoRepoProvider).watchEventosByPredio(predioId);
});

/// Tareas completadas de todos los cultivos del predio (activos y finalizados).
final tareasPredioProvider = Provider<List<TareaCompletada>>((ref) {
  final predioId = ref.watch(activePredioIdProvider);
  final asyncTs = ref.watch(_tareasStreamByPredio(predioId));
  return asyncTs.maybeWhen(
    data: (list) => list.map(TareaCompletada.fromDrift).toList(),
    orElse: () => const <TareaCompletada>[],
  );
});

final _tareasStreamByPredio =
    StreamProvider.family<List<drift.TareasCompletada>, int>((ref, predioId) {
  return ref.watch(_cultivoRepoProvider).watchTareasByPredio(predioId);
});

/// HH por mes del año en curso (agregado desde tareas_completadas).
final hhPorMesProvider = Provider<Map<int, double>>((ref) {
  final anio = DateTime.now().year;
  final tareas = ref.watch(tareasPredioProvider);
  final map = <int, double>{};
  for (final t in tareas) {
    if (t.fecha.year != anio) continue;
    map[t.fecha.month] = (map[t.fecha.month] ?? 0) + t.hh;
  }
  return map;
});

/// HH por usuario en el año en curso (Fase 3g). Clave = createdByUserId
/// (UUID) o cadena vacía "" para tareas legacy/anónimas.
final hhPorUsuarioProvider = Provider<Map<String, double>>((ref) {
  final anio = DateTime.now().year;
  final tareas = ref.watch(tareasPredioProvider);
  final map = <String, double>{};
  for (final t in tareas) {
    if (t.fecha.year != anio) continue;
    final key = t.createdByUserId ?? '';
    map[key] = (map[key] ?? 0) + t.hh;
  }
  return map;
});

/// Resolver UUID → email con caché en memoria. Usa RPC `email_de_usuario`
/// (SECURITY DEFINER en Postgres). Retorna null si no hay sesión Supabase
/// o si la RPC falla.
class _EmailUsuarioCache {
  final Map<String, String?> _cache = {};

  Future<String?> resolver(String userId) async {
    if (_cache.containsKey(userId)) return _cache[userId];
    final srv = SupabaseService.instance.client;
    if (srv == null) {
      _cache[userId] = null;
      return null;
    }
    try {
      final res = await srv.rpc(
        'email_de_usuario',
        params: {'p_user_id': userId},
      );
      final email = res as String?;
      _cache[userId] = email;
      return email;
    } catch (_) {
      _cache[userId] = null;
      return null;
    }
  }

  void invalidar() => _cache.clear();
}

final _emailUsuarioCacheProvider =
    Provider<_EmailUsuarioCache>((ref) => _EmailUsuarioCache());

/// FutureProvider.family que retorna el email asociado a un UUID Supabase.
final emailPorUserIdProvider =
    FutureProvider.family<String?, String>((ref, userId) async {
  if (userId.isEmpty) return null;
  return ref.watch(_emailUsuarioCacheProvider).resolver(userId);
});

/// Proveedores únicos por descripción de ítem (case-insensitive).
/// Se computa desde compras: cada ítem de inventario "conoce" los proveedores
/// de donde ha sido adquirido a lo largo del tiempo.
final proveedoresPorItemProvider = Provider<Map<String, List<String>>>((ref) {
  final compras = ref.watch(comprasProvider);
  final byDesc = <String, Set<String>>{};
  for (final c in compras) {
    if (c.proveedor.trim().isEmpty || c.proveedor.startsWith('Sin proveedor')) {
      continue;
    }
    (byDesc[c.desc.trim().toLowerCase()] ??= <String>{}).add(c.proveedor);
  }
  return byDesc.map((k, v) {
    final list = v.toList()..sort();
    return MapEntry(k, list);
  });
});

/// Lista consolidada de nombres de insumos ya conocidos (para Autocomplete
/// de Descripción 1 en Nueva compra).
final knownProductNamesProvider = Provider<Set<String>>((ref) {
  final plantas = ref.watch(plantasProvider);
  final compras = ref.watch(comprasProvider);
  final inv = ref.watch(inventoryProvider);
  final set = <String>{};
  for (final p in plantas) {
    set.add('Semilla ${p.nombre}');
  }
  for (final c in compras) {
    set.add(c.desc);
  }
  for (final i in inv) {
    set.add(i.desc);
  }
  return set;
});

// ============ Mutations (UI-friendly) ============

/// Wrapper para llamar a los repositorios desde la UI sin exponer Drift.
class DataMutations {
  DataMutations(this.ref);
  final Ref ref;

  int get _predioId => ref.read(activePredioIdProvider);

  /// Lectura async del predio ID que espera a que configProvider haya emitido
  /// para garantizar que se use el valor real (no el fallback 1).
  Future<int> _getPredioIdAsync() async {
    try {
      final cfg = await ref.read(configProvider.future);
      final id = cfg?.predioActivoId;
      if (id != null) return id;
    } catch (_) {}
    // Fallback: consulta el primer predio existente en la BD.
    final db = ref.read(databaseProvider);
    final predio = await (db.select(db.predios)
          ..where((p) => p.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
    return predio?.id ?? 1;
  }

  Future<int> addCompra({
    required String fecha,
    required String desc,
    String? desc2,
    required double valor,
    required double cantidad,
    required String unidad,
    required String cod,
    required String factura,
    required String proveedor,
    required String tipo,
    int? plantaRef,
    String? soporteName,
  }) async {
    if (!ref.read(permisosPredioActivoProvider).puedeEditarCompras) {
      throw StateError('Sin permiso para registrar compras en este predio');
    }
    final predioId = await _getPredioIdAsync();
    final provRepo = ref.read(_proveedorRepoProvider);
    final proveedorId = proveedor.trim().isEmpty
        ? null
        : await provRepo.addIfMissing(proveedor.trim());
    String? autorUserId;
    try {
      autorUserId = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      autorUserId = null;
    }
    return await ref.read(_compraRepoProvider).add(
          predioId: predioId,
          fecha: DateTime.parse(fecha),
          desc: desc,
          desc2: desc2,
          valor: valor,
          cantidad: cantidad,
          unidad: unidad,
          codigo: cod,
          factura: factura,
          proveedorId: proveedorId,
          proveedorNombre: proveedor.trim().isEmpty ? null : proveedor.trim(),
          tipo: tipo,
          plantaRef: plantaRef,
          soporteName: soporteName,
          soporteTipo: soporteName?.toLowerCase().endsWith('.pdf') == true
              ? 'application/pdf'
              : (soporteName != null ? 'image/*' : null),
          createdByUserId: autorUserId,
        );
  }

  Future<void> updateCompra({
    required int id,
    required String fecha,
    required String desc,
    String? desc2,
    required double valor,
    required double cantidad,
    required String unidad,
    required String cod,
    required String factura,
    required String proveedor,
    required String tipo,
    int? plantaRef,
    String? soporteName,
  }) async {
    if (!ref.read(permisosPredioActivoProvider).puedeEditarCompras) {
      throw StateError('Sin permiso para editar compras en este predio');
    }
    final predioId = await _getPredioIdAsync();
    final provRepo = ref.read(_proveedorRepoProvider);
    final proveedorId = proveedor.trim().isEmpty
        ? null
        : await provRepo.addIfMissing(proveedor.trim());
    await ref.read(_compraRepoProvider).update(
          id: id,
          predioId: predioId,
          fecha: DateTime.parse(fecha),
          desc: desc,
          desc2: desc2,
          valor: valor,
          cantidad: cantidad,
          unidad: unidad,
          codigo: cod,
          factura: factura,
          proveedorId: proveedorId,
          proveedorNombre: proveedor.trim().isEmpty ? null : proveedor.trim(),
          tipo: tipo,
          plantaRef: plantaRef,
          soporteName: soporteName,
          soporteTipo: soporteName?.toLowerCase().endsWith('.pdf') == true
              ? 'application/pdf'
              : (soporteName != null ? 'image/*' : null),
        );
  }

  Future<int> addOrIncrementInventory({
    required String descripcion,
    required double cantidad,
    required String unidad,
    String? codigo,
    String? fabricante,
  }) async {
    final predioId = await _getPredioIdAsync();
    // Si el proveedor es nuevo, agrégalo al catálogo automáticamente
    if (fabricante != null && fabricante.trim().isNotEmpty) {
      await ref.read(_proveedorRepoProvider).addIfMissing(fabricante.trim());
    }
    return ref.read(_inventoryRepoProvider).addOrIncrement(
          predioId: predioId,
          descripcion: descripcion,
          cantidad: cantidad,
          unidad: unidad,
          codigo: codigo,
          fabricante: fabricante,
        );
  }

  Future<void> consumeInventory({
    required String descripcion,
    required double cantidad,
    String unidad = 'kg',
  }) async {
    final predioId = await _getPredioIdAsync();
    return ref.read(_inventoryRepoProvider).consume(
          predioId: predioId,
          descripcion: descripcion,
          cantidad: cantidad,
          unidad: unidad,
        );
  }

  /// Consumo directo en unidad base (sin conversión). Se usa cuando la cantidad
  /// del usuario ya está expresada en la misma unidad base del inventario
  /// (ej. desde el modal de Registrar tarea que muestra la unidad base).
  Future<void> consumeInventoryBase({
    required String descripcion,
    required double cantidadBase,
  }) async {
    final predioId = await _getPredioIdAsync();
    return ref.read(_inventoryRepoProvider).consumeBase(
          predioId: predioId,
          descripcion: descripcion,
          cantidadBase: cantidadBase,
        );
  }

  /// Si [pl] es comunitaria (id negativo), la copia al catálogo propio y
  /// devuelve el id local persistido. Idempotente para variedades propias.
  Future<int> ensurePlantaLocal(Planta pl) async {
    if (!pl.esComunidad) return pl.id;
    final esPerenne = pl.esPerenneDefault;
    final res = await addPlanta(
      nombreComun: pl.nombre,
      especie: pl.especie.isEmpty ? null : pl.especie,
      tiempoCosechaMinDias: pl.cosechaMin,
      tiempoCosechaMaxDias: esPerenne ? null : pl.cosechaMax,
      tipoCultivoDefault: pl.tipoCultivoDefault,
      periodicidadCosechaDias:
          esPerenne ? pl.periodicidadCosechaDias : null,
      esperanzaVidaDias: esPerenne ? pl.esperanzaVidaDias : null,
      ciclosAbonoJson: encodeCiclosAbonoJson(pl.ciclosAbono),
      metodoSiembra: pl.metodoSiembra,
      germinadorDias:
          pl.metodoSiembra == 'germinador' ? pl.germinadorDias : null,
      tipoAbono1: pl.tipoAbono1,
      tipoAbono2: pl.tipoAbono2,
      diasAbono2: pl.abono2Dias,
      fuenteMetodo: pl.fuenteMetodo.isEmpty ? null : pl.fuenteMetodo,
    );
    return res.plantaId;
  }

  Future<int> addCultivo({
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
    final resolvedPlantaId = plantaId < 0
        ? await _plantaIdDesdeVariedadComunitaria(-plantaId)
        : plantaId;
    final predioId = await _getPredioIdAsync();
    final id = await ref.read(_cultivoRepoProvider).insert(
          predioId: predioId,
          plantaId: resolvedPlantaId,
          lote: lote,
          fechaSiembra: fechaSiembra,
          areaValor: areaValor,
          areaUnidad: areaUnidad,
          semillaValor: semillaValor,
          semillaUnidad: semillaUnidad,
          hhInicial: hhInicial,
          horaValor: horaValor,
          lat: lat,
          lng: lng,
          altM: altM,
          loteId: loteId,
          tipoCultivo: tipoCultivo,
          cosecha1Dias: cosecha1Dias,
          cosecha2Dias: cosecha2Dias,
          periodicidadCosechaDias: periodicidadCosechaDias,
          esperanzaVidaDias: esperanzaVidaDias,
        );
    if (semillaValor > 0) {
      final plRow = await ref.read(_plantaRepoProvider).findById(resolvedPlantaId);
      if (plRow == null) {
        throw StateError('Planta $resolvedPlantaId no encontrada');
      }
      await ref.read(_inventoryRepoProvider).consume(
            predioId: predioId,
            descripcion: 'Semilla ${plRow.nombreComun}',
            cantidad: semillaValor,
            unidad: semillaUnidad,
          );
    }
    ref.invalidate(_cultivosActivosStream);
    ref.invalidate(_cultivosFinStream);
    ref.invalidate(_eventosStreamByPredio);
    // Reprograma notificaciones tras el nuevo cultivo (asincrónico, no
    // bloquea la respuesta al usuario).
    ref.read(eventNotificationSyncProvider).sincronizar();
    return id;
  }

  Future<void> deleteCultivo(int id) async {
    await ref.read(_cultivoRepoProvider).softDelete(id);
    ref.read(eventNotificationSyncProvider).sincronizar();
  }

  Future<void> finalizeCultivo(int id) async {
    await ref.read(_cultivoRepoProvider).markFinalizado(id);
    ref.read(eventNotificationSyncProvider).sincronizar();
  }

  Future<void> unfinalizeCultivo(int id) =>
      ref.read(_cultivoRepoProvider).unmarkFinalizado(id);

  Future<int> _plantaIdDesdeVariedadComunitaria(int cacheId) async {
    final db = ref.read(databaseProvider);
    final row = await (db.select(db.variedadesComunitariasCache)
          ..where((t) => t.id.equals(cacheId)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError(
          'Variedad comunitaria #$cacheId no encontrada — sincroniza el banco');
    }
    return ensurePlantaLocal(Planta.fromComunidadCache(row));
  }

  // ============================================================
  // Plantas (catálogo)
  // ============================================================

  /// Retorna un par (plantaId, patologiasAutoAñadidas).
  Future<({int plantaId, int patologiasAutoAgregadas})> addPlanta({
    required String nombreComun,
    String? variedad,
    String? especie,
    String? familia,
    int? tiempoCosechaMinDias,
    int? tiempoCosechaMaxDias,
    String tipoCultivoDefault = 'ciclo_unico',
    int? periodicidadCosechaDias,
    int? esperanzaVidaDias,
    String? ciclosAbonoJson,
    String? metodoSiembra,
    int? germinadorDias,
    String? tipoAbono1,
    int? diasAbono2,
    String? tipoAbono2,
    String? fuenteMetodo,
    String? notas,
  }) async {
    final repo = ref.read(_plantaRepoProvider);
    final antesDeInsert = 0; // baseline
    final id = await repo.insert(
      nombreComun: nombreComun,
      variedad: variedad,
      especie: especie,
      familia: familia,
      tiempoCosechaMinDias: tiempoCosechaMinDias,
      tiempoCosechaMaxDias: tiempoCosechaMaxDias,
      tipoCultivoDefault: tipoCultivoDefault,
      periodicidadCosechaDias: periodicidadCosechaDias,
      esperanzaVidaDias: esperanzaVidaDias,
      ciclosAbonoJson: ciclosAbonoJson,
      metodoSiembra: metodoSiembra,
      germinadorDias: germinadorDias,
      tipoAbono1: tipoAbono1,
      diasAbono2: diasAbono2,
      tipoAbono2: tipoAbono2,
      fuenteMetodo: fuenteMetodo,
      notas: notas,
    );
    // insert() ya invocó autoPopularPatologias internamente. Contamos el
    // resultado neto para reportar en snackbar.
    final total = await repo.countPatologiasAsociadas(id);
    return (plantaId: id, patologiasAutoAgregadas: total - antesDeInsert);
  }

  /// Retorna número de patologías NUEVAS auto-añadidas por el cambio
  /// (0 si no cambió la especie o si ya estaban todas).
  Future<int> updatePlanta({
    required int id,
    required String nombreComun,
    String? variedad,
    String? especie,
    String? familia,
    int? tiempoCosechaMinDias,
    int? tiempoCosechaMaxDias,
    String tipoCultivoDefault = 'ciclo_unico',
    int? periodicidadCosechaDias,
    int? esperanzaVidaDias,
    String? ciclosAbonoJson,
    String? metodoSiembra,
    int? germinadorDias,
    String? tipoAbono1,
    int? diasAbono2,
    String? tipoAbono2,
    String? fuenteMetodo,
    String? notas,
  }) async {
    final repo = ref.read(_plantaRepoProvider);
    final antes = await repo.countPatologiasAsociadas(id);
    await repo.update(
      id: id,
      nombreComun: nombreComun,
      variedad: variedad,
      especie: especie,
      familia: familia,
      tiempoCosechaMinDias: tiempoCosechaMinDias,
      tiempoCosechaMaxDias: tiempoCosechaMaxDias,
      tipoCultivoDefault: tipoCultivoDefault,
      periodicidadCosechaDias: periodicidadCosechaDias,
      esperanzaVidaDias: esperanzaVidaDias,
      ciclosAbonoJson: ciclosAbonoJson,
      metodoSiembra: metodoSiembra,
      germinadorDias: germinadorDias,
      tipoAbono1: tipoAbono1,
      diasAbono2: diasAbono2,
      tipoAbono2: tipoAbono2,
      fuenteMetodo: fuenteMetodo,
      notas: notas,
    );
    final despues = await repo.countPatologiasAsociadas(id);
    return despues - antes;
  }

  Future<void> deletePlanta(int id) =>
      ref.read(_plantaRepoProvider).softDelete(id);

  Future<int> countCultivosPlanta(int plantaId) =>
      ref.read(_plantaRepoProvider).countCultivosUsando(plantaId);

  /// Fase 3h: patologías conocidas para una especie (preview en el modal).
  Future<List<drift.Patologia>> patologiasConocidasPorEspecie(String especie) =>
      ref.read(_plantaRepoProvider).patologiasConocidasPorEspecie(especie);

  /// Fase 3h: cuenta patologías ya asociadas a una planta específica.
  Future<int> countPatologiasAsociadas(int plantaId) =>
      ref.read(_plantaRepoProvider).countPatologiasAsociadas(plantaId);

  /// Guarda las preferencias del usuario en la tabla config (persistencia).
  Future<void> savePreferences({
    String? idioma,
    String? estiloUi,
    String? sistemaUnidades,
    String? monedaCodigo,
    bool? consentimientoPatologias,
    // Fase 3i-B: token EPPO. Pasar cadena vacía "" para borrar el guardado.
    String? eppoToken,
  }) async {
    final db = ref.read(databaseProvider);
    // Verifica si existe la fila de config (tras "Reset total" está vacía).
    final existing = await (db.select(db.configs)..limit(1)).getSingleOrNull();
    // Interpretar eppoToken: null = no cambiar; "" = borrar; otro = guardar.
    final Value<String?> eppoValue = eppoToken == null
        ? const Value.absent()
        : (eppoToken.isEmpty ? const Value(null) : Value(eppoToken));
    if (existing == null) {
      // INSERT nuevo con defaults + valores dados
      await db.into(db.configs).insert(
            drift.ConfigsCompanion.insert(
              id: const Value(1),
              idioma: idioma != null ? Value(idioma) : const Value.absent(),
              estiloUi: estiloUi != null
                  ? Value(estiloUi)
                  : const Value.absent(),
              sistemaUnidades: sistemaUnidades != null
                  ? Value(sistemaUnidades)
                  : const Value.absent(),
              monedaCodigo: monedaCodigo != null
                  ? Value(monedaCodigo)
                  : const Value.absent(),
              consentimientoPatologias: consentimientoPatologias != null
                  ? Value(consentimientoPatologias)
                  : const Value.absent(),
              eppoToken: eppoValue,
              updatedAt: Value(DateTime.now()),
            ),
          );
    } else {
      await (db.update(db.configs)..where((c) => c.id.equals(1))).write(
        drift.ConfigsCompanion(
          idioma: idioma != null ? Value(idioma) : const Value.absent(),
          estiloUi:
              estiloUi != null ? Value(estiloUi) : const Value.absent(),
          sistemaUnidades: sistemaUnidades != null
              ? Value(sistemaUnidades)
              : const Value.absent(),
          monedaCodigo: monedaCodigo != null
              ? Value(monedaCodigo)
              : const Value.absent(),
          consentimientoPatologias: consentimientoPatologias != null
              ? Value(consentimientoPatologias)
              : const Value.absent(),
          eppoToken: eppoValue,
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// Marca el onboarding como completado y crea el predio inicial + activa.
  Future<int> completeOnboarding({
    required String nombrePredio,
    required String propietario,
    int? paisId,
    int? regionId,
    int? municipioId,
    double? lat,
    double? lng,
    double? altM,
  }) async {
    final db = ref.read(databaseProvider);
    final predioId = await db.into(db.predios).insert(drift.PrediosCompanion.insert(
          nombre: nombrePredio,
          propietario: Value(propietario.isEmpty ? null : propietario),
          paisId: Value(paisId),
          regionId: Value(regionId),
          municipioId: Value(municipioId),
          lat: Value(lat),
          lng: Value(lng),
          altM: Value(altM),
        ));
    await db.into(db.configs).insertOnConflictUpdate(
          drift.ConfigsCompanion.insert(
            id: const Value(1),
            predioActivoId: Value(predioId),
            primeraEjecucion: const Value(false),
            permisosSolicitados: const Value(true),
            updatedAt: Value(DateTime.now()),
          ),
        );
    return predioId;
  }

  /// Marca el onboarding como completado sin crear ningún predio. Usado por
  /// cuentas colaboradoras que trabajarán solo sobre predios compartidos.
  /// El predio activo queda en null hasta que el usuario sincronice y
  /// reciba alguno o cree uno manualmente desde "Administración de predios".
  Future<void> completeOnboardingSinPredio() async {
    final db = ref.read(databaseProvider);
    // UPSERT: tras "Reset total" la tabla configs queda vacía, así que un
    // UPDATE puro no crearía nada. `insertOnConflictUpdate` inserta si no
    // existe, actualiza si ya existe.
    await db.into(db.configs).insertOnConflictUpdate(
          drift.ConfigsCompanion.insert(
            id: const Value(1),
            predioActivoId: const Value(null),
            primeraEjecucion: const Value(false),
            permisosSolicitados: const Value(true),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  /// Garantiza que país/región/municipio existan en el catálogo local y
  /// retorna sus ids (mejora 2026-07-19: autollenado desde GPS).
  /// Matching por iso2/nombre sin distinguir mayúsculas; crea las filas
  /// que falten — así el catálogo geográfico crece con el uso real.
  Future<({int? paisId, int? regionId, int? municipioId})> asegurarGeografia({
    String? paisNombre,
    String? iso2,
    String? regionNombre,
    String? municipioNombre,
  }) async {
    final db = ref.read(databaseProvider);
    String norm(String s) => s.trim().toLowerCase();

    // País — por iso2 primero (más fiable que el nombre localizado).
    int? paisId;
    if (iso2 != null || paisNombre != null) {
      final paises = await db.select(db.paises).get();
      for (final p in paises) {
        final matchIso = iso2 != null && p.iso2.toUpperCase() == iso2.toUpperCase();
        final matchNombre =
            paisNombre != null && norm(p.nombre) == norm(paisNombre);
        if (matchIso || matchNombre) {
          paisId = p.id;
          break;
        }
      }
      if (paisId == null && paisNombre != null && iso2 != null) {
        paisId = await db.into(db.paises).insert(
            drift.PaisesCompanion.insert(nombre: paisNombre.trim(), iso2: iso2));
      }
    }
    if (paisId == null) {
      return (paisId: null, regionId: null, municipioId: null);
    }

    // Región
    int? regionId;
    if (regionNombre != null) {
      final regiones = await (db.select(db.regiones)
            ..where((r) => r.paisId.equals(paisId!)))
          .get();
      for (final r in regiones) {
        if (norm(r.nombre) == norm(regionNombre)) {
          regionId = r.id;
          break;
        }
      }
      regionId ??= await db.into(db.regiones).insert(
          drift.RegionesCompanion.insert(
              paisId: paisId, nombre: regionNombre.trim()));
    }
    if (regionId == null) {
      return (paisId: paisId, regionId: null, municipioId: null);
    }

    // Municipio
    int? municipioId;
    if (municipioNombre != null) {
      final municipios = await (db.select(db.municipios)
            ..where((m) => m.regionId.equals(regionId!)))
          .get();
      for (final m in municipios) {
        if (norm(m.nombre) == norm(municipioNombre)) {
          municipioId = m.id;
          break;
        }
      }
      municipioId ??= await db.into(db.municipios).insert(
          drift.MunicipiosCompanion.insert(
              regionId: regionId, nombre: municipioNombre.trim()));
    }
    return (paisId: paisId, regionId: regionId, municipioId: municipioId);
  }

  Future<void> restoreTrash(String tipo, int id) async {
    await ref.read(_trashRepoProvider).restore(tipo, id);
    ref.invalidate(papeleraProvider);
  }

  /// Mapping tipo UI (singular) → tabla remota Postgres (plural).
  static const _tipoATablaRemota = <String, String>{
    'cultivo': 'cultivos',
    'compra': 'compras',
    'inventario': 'inventarios',
    'lote': 'lotes',
    'analisis': 'analisis_suelo',
    'predio': 'predios',
    'proveedor': 'proveedores',
  };

  Future<void> hardDeleteTrash(String tipo, int id) async {
    // 1. Propaga el borrado al server (silencioso si no hay red o sesión)
    final tablaRemota = _tipoATablaRemota[tipo];
    if (tablaRemota != null) {
      await ref.read(syncServiceProvider).eliminarRemoto(tablaRemota, id);
    }
    // 2. Borra local
    await ref.read(_trashRepoProvider).hardDelete(tipo, id);
    ref.invalidate(papeleraProvider);
  }

  Future<int> emptyTrash() async {
    // Antes de vaciar local, propaga cada delete al server
    final items = await ref.read(_trashRepoProvider).getByPredio(_predioId);
    for (final it in items) {
      final tablaRemota = _tipoATablaRemota[it.tipo];
      if (tablaRemota != null) {
        await ref.read(syncServiceProvider).eliminarRemoto(tablaRemota, it.id);
      }
    }
    final n = await ref.read(_trashRepoProvider).emptyAll(_predioId);
    ref.invalidate(papeleraProvider);
    return n;
  }

  Future<void> registrarIntervencionPatologia({
    required int cpId,
    required DateTime fecha,
    required String nota,
  }) =>
      ref.read(_patologiaRepoProvider).registrarIntervencion(
            cpId: cpId, fecha: fecha, nota: nota);

  Future<void> marcarPatologiaCurada(int cpId) =>
      ref.read(_patologiaRepoProvider).marcarCurada(cpId);

  /// Mueve una patología del catálogo al grupo indicado del listado.
  /// `tipoManual = null` restaura la agrupación automática.
  Future<void> reclasificarPatologia({
    required int patologiaId,
    required String? tipoManual,
  }) =>
      ref.read(_patologiaRepoProvider).reclasificar(
            patologiaId: patologiaId,
            tipoManual: tipoManual,
          );

  /// Fase 3e-5: registra un reporte de patología en un cultivo. Si el
  /// usuario acepta compartir a comunidad, crea también la entrada
  /// anonimizada en PatologiasReportadas.
  Future<int> reportarPatologia({
    required int cultivoId,
    required int patologiaId,
    required DateTime fechaDeteccion,
    required String severidad,
    String? fotoPath,
    double? lat,
    double? lng,
    double? altM,
    String? notas,
    required bool compartirAComunidad,
    String? patologiaNombre,
    String? patologiaCientifico,
    String? plantaNombre,
    String? paisIso2,
    String? regionNombre,
    String? municipioNombre,
  }) =>
      ref.read(_patologiaRepoProvider).reportarPatologia(
            cultivoId: cultivoId,
            patologiaId: patologiaId,
            fechaDeteccion: fechaDeteccion,
            severidad: severidad,
            fotoPath: fotoPath,
            lat: lat,
            lng: lng,
            altM: altM,
            notas: notas,
            compartirAComunidad: compartirAComunidad,
            patologiaNombre: patologiaNombre,
            patologiaCientifico: patologiaCientifico,
            plantaNombre: plantaNombre,
            paisIso2: paisIso2,
            regionNombre: regionNombre,
            municipioNombre: municipioNombre,
          );

  Future<void> eliminarReportePatologia(int cpId) =>
      ref.read(_patologiaRepoProvider).softDeleteReporte(cpId);

  Future<int> registrarTarea({
    required int cultivoId,
    required DateTime fecha,
    required double hh,
    required List<String> actividades,
    List<InsumoUsado> insumos = const [],
    String? notas,
    int? periodicidadCosechaDias,
  }) async {
    // Fase 3g: si hay sesión Supabase, estampar el UUID del usuario que
    // registra la tarea. En modo local queda null (legacy/anónimo).
    String? autorUserId;
    try {
      autorUserId = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      autorUserId = null;
    }
    final id = await ref.read(_cultivoRepoProvider).registrarTarea(
          cultivoId: cultivoId, fecha: fecha, hh: hh,
          actividades: actividades,
          insumos: insumos.map((i) => i.toJson()).toList(),
          notas: notas,
          createdByUserId: autorUserId,
          periodicidadCosechaDias: periodicidadCosechaDias,
        );
    // Reprograma notificaciones: al cerrar un evento su alerta ya no aplica.
    ref.read(eventNotificationSyncProvider).sincronizar();
    return id;
  }

  Future<void> updateTareaSimple({
    required int id,
    required DateTime fecha,
    required double hh,
    String? notas,
  }) =>
      ref.read(_cultivoRepoProvider).updateTareaSimple(
          id: id, fecha: fecha, hh: hh, notas: notas);

  Future<void> deleteTarea(int id) =>
      ref.read(_cultivoRepoProvider).deleteTarea(id, _predioId);

  /// Recalcula qué eventos deben marcarse como ejecutados a partir de las
  /// tareas ya registradas. Retorna número de eventos cerrados.
  Future<int> resincronizarEventos(int cultivoId) =>
      ref.read(_cultivoRepoProvider).resincronizarEventos(cultivoId);

  Future<void> updateInventoryItem(drift.Inventario updated) =>
      ref.read(_inventoryRepoProvider).update(updated);

  Future<void> updateInventoryFields({
    required int id,
    String? descripcion,
    String? codigo,
    String? fabricante,
    double? cantidadBase,
    String? unidadBase,
  }) async {
    // Auto-registro de proveedor nuevo
    if (fabricante != null && fabricante.trim().isNotEmpty) {
      await ref.read(_proveedorRepoProvider).addIfMissing(fabricante.trim());
    }
    return ref.read(_inventoryRepoProvider).updateFields(
          id: id,
          descripcion: descripcion,
          codigo: codigo,
          fabricante: fabricante,
          cantidadBase: cantidadBase,
          unidadBase: unidadBase,
        );
  }

  Future<void> deleteInventoryItem(int id) =>
      ref.read(_inventoryRepoProvider).softDelete(id);

  // ============ Proveedores ============
  Future<int> addProveedor({
    required String nombre,
    String? nit,
    String? telefono,
    String? email,
    String? web,
    String? direccion,
    String? notas,
  }) =>
      ref.read(_proveedorRepoProvider).insert(
            nombre: nombre,
            nit: nit,
            telefono: telefono,
            email: email,
            web: web,
            direccion: direccion,
            notas: notas,
          );

  Future<void> updateProveedor({
    required int id,
    required String nombre,
    String? nit,
    String? telefono,
    String? email,
    String? web,
    String? direccion,
    String? notas,
  }) =>
      ref.read(_proveedorRepoProvider).update(
            id: id,
            nombre: nombre,
            nit: nit,
            telefono: telefono,
            email: email,
            web: web,
            direccion: direccion,
            notas: notas,
          );

  Future<void> deleteProveedor(int id) =>
      ref.read(_proveedorRepoProvider).softDelete(id);

  // ============ Análisis de suelo ============
  Future<int> addAnalisisSuelo({
    required DateTime fechaMuestreo,
    String? lote,
    String? laboratorio,
    double? profundidadCm,
    String? textura,
    double? densidadGCm3,
    double? conductividadMsCm,
    double? ph,
    double? materiaOrganicaPct,
    double? nPpm,
    double? pPpm,
    double? kPpm,
    double? caMeq,
    double? mgMeq,
    double? naMeq,
    double? cicMeq,
    double? sPpm,
    double? bPpm,
    String? soportePath,
    String? soporteTipo,
    String? notas,
  }) async {
    final predioId = await _getPredioIdAsync();
    return ref.read(_analisisRepoProvider).insert(
          predioId: predioId,
          fechaMuestreo: fechaMuestreo,
          lote: lote,
          laboratorio: laboratorio,
          profundidadCm: profundidadCm,
          textura: textura,
          densidadGCm3: densidadGCm3,
          conductividadMsCm: conductividadMsCm,
          ph: ph,
          materiaOrganicaPct: materiaOrganicaPct,
          nPpm: nPpm,
          pPpm: pPpm,
          kPpm: kPpm,
          caMeq: caMeq,
          mgMeq: mgMeq,
          naMeq: naMeq,
          cicMeq: cicMeq,
          sPpm: sPpm,
          bPpm: bPpm,
          soportePath: soportePath,
          soporteTipo: soporteTipo,
          notas: notas,
        );
  }

  Future<void> updateAnalisisSuelo({
    required int id,
    required DateTime fechaMuestreo,
    String? lote,
    String? laboratorio,
    double? profundidadCm,
    String? textura,
    double? densidadGCm3,
    double? conductividadMsCm,
    double? ph,
    double? materiaOrganicaPct,
    double? nPpm,
    double? pPpm,
    double? kPpm,
    double? caMeq,
    double? mgMeq,
    double? naMeq,
    double? cicMeq,
    double? sPpm,
    double? bPpm,
    String? soportePath,
    String? soporteTipo,
    String? notas,
  }) =>
      ref.read(_analisisRepoProvider).update(
            id: id,
            fechaMuestreo: fechaMuestreo,
            lote: lote,
            laboratorio: laboratorio,
            profundidadCm: profundidadCm,
            textura: textura,
            densidadGCm3: densidadGCm3,
            conductividadMsCm: conductividadMsCm,
            ph: ph,
            materiaOrganicaPct: materiaOrganicaPct,
            nPpm: nPpm,
            pPpm: pPpm,
            kPpm: kPpm,
            caMeq: caMeq,
            mgMeq: mgMeq,
            naMeq: naMeq,
            cicMeq: cicMeq,
            sPpm: sPpm,
            bPpm: bPpm,
            soportePath: soportePath,
            soporteTipo: soporteTipo,
            notas: notas,
          );

  Future<void> deleteAnalisisSuelo(int id) =>
      ref.read(_analisisRepoProvider).softDelete(id);

  // ============ Condiciones edafoclimáticas del predio ============
  // ============ Predios (CRUD) ============
  Future<int> addPredio({
    required String nombre,
    String? propietario,
    int? paisId,
    int? regionId,
    int? municipioId,
    double? lat,
    double? lng,
    double? altM,
    String? notas,
  }) =>
      ref.read(_predioRepoProvider).insert(
            nombre: nombre,
            propietario: propietario,
            paisId: paisId,
            regionId: regionId,
            municipioId: municipioId,
            lat: lat,
            lng: lng,
            altM: altM,
            notas: notas,
          );

  Future<void> updatePredio({
    required int id,
    required String nombre,
    String? propietario,
    int? paisId,
    int? regionId,
    int? municipioId,
    double? lat,
    double? lng,
    double? altM,
    String? notas,
  }) =>
      ref.read(_predioRepoProvider).update(
            id: id,
            nombre: nombre,
            propietario: propietario,
            paisId: paisId,
            regionId: regionId,
            municipioId: municipioId,
            lat: lat,
            lng: lng,
            altM: altM,
            notas: notas,
          );

  Future<void> deletePredio(int id) =>
      ref.read(_predioRepoProvider).softDelete(id);

  /// Cambia el predio activo. Todos los providers reactivos (cultivos,
  /// inventario, compras, lotes, análisis, etc.) se actualizan
  /// automáticamente porque están basados en `activePredioIdProvider`,
  /// que a su vez sigue el stream de `configs`.
  Future<void> setPredioActivo(int predioId) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.configs)..where((c) => c.id.equals(1))).write(
      drift.ConfigsCompanion(
        predioActivoId: Value(predioId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ============ Lotes (CRUD) ============
  Future<int> addLote({
    required int predioId,
    required String nombre,
    String? administrador,
    double? altitudMsnm,
    double? areaM2,
    String? poligonoGeoJson,
    String? notas,
  }) =>
      ref.read(_loteRepoProvider).insert(
            predioId: predioId,
            nombre: nombre,
            administrador: administrador,
            altitudMsnm: altitudMsnm,
            areaM2: areaM2,
            poligonoGeoJson: poligonoGeoJson,
            notas: notas,
          );

  Future<void> updateLote({
    required int id,
    required String nombre,
    String? administrador,
    double? altitudMsnm,
    double? areaM2,
    String? poligonoGeoJson,
    String? notas,
  }) =>
      ref.read(_loteRepoProvider).update(
            id: id,
            nombre: nombre,
            administrador: administrador,
            altitudMsnm: altitudMsnm,
            areaM2: areaM2,
            poligonoGeoJson: poligonoGeoJson,
            notas: notas,
          );

  Future<void> deleteLote(int id) =>
      ref.read(_loteRepoProvider).softDelete(id);

  // ============ Colaboradores del predio (Fase 3e) ============

  /// Busca en Supabase un usuario por email. Retorna su UUID o null.
  /// Usa la función RPC `buscar_usuario_por_email` (SECURITY DEFINER).
  Future<String?> buscarUsuarioPorEmail(String email) async {
    final srv = SupabaseService.instance.client;
    if (srv == null) return null;
    try {
      final res = await srv.rpc(
        'buscar_usuario_por_email',
        params: {'p_email': email.trim().toLowerCase()},
      );
      if (res == null) return null;
      return res as String;
    } catch (_) {
      return null;
    }
  }

  /// Invita a un colaborador al predio. Requiere que el usuario ya tenga
  /// cuenta en Supabase — si no, retorna null y la UI muestra error.
  Future<int?> invitarColaborador({
    required int predioId,
    required String email,
    required String rol,
  }) async {
    final userId = await buscarUsuarioPorEmail(email);
    if (userId == null) return null;
    final id = await ref.read(_colaboradorRepoProvider).insert(
          predioId: predioId,
          email: email.trim().toLowerCase(),
          userId: userId,
          rol: rol,
          aceptadoAt: DateTime.now(), // auto-aceptación
        );
    // Dispara sync para propagar la invitación al server
    ref.read(syncServiceProvider).sincronizar();
    return id;
  }

  Future<void> actualizarRolColaborador({
    required int id,
    required String rol,
  }) async {
    await ref.read(_colaboradorRepoProvider).actualizarRol(id: id, rol: rol);
    ref.read(syncServiceProvider).sincronizar();
  }

  Future<void> removerColaborador(int id) async {
    await ref.read(_colaboradorRepoProvider).softDelete(id);
    ref.read(syncServiceProvider).sincronizar();
  }

  // ============ Notificaciones ============
  /// Reprograma todas las notificaciones locales según los eventos
  /// pendientes actuales. Se debe llamar tras cambios en cultivos/tareas.
  Future<int> resincronizarNotificaciones() =>
      ref.read(eventNotificationSyncProvider).sincronizar();

  /// Actualiza la configuración de notificaciones.
  Future<void> updateConfigNotificaciones({
    required bool habilitadas,
    required int antelacionDias,
  }) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.configs)..where((c) => c.id.equals(1))).write(
      drift.ConfigsCompanion(
        notificacionesHabilitadas: Value(habilitadas),
        notificacionAntelacionDias: Value(antelacionDias),
        updatedAt: Value(DateTime.now()),
      ),
    );
    // Reaplica: si fue deshabilitada limpia todas; si habilitada reprograma.
    await ref.read(eventNotificationSyncProvider).sincronizar();
  }

  Future<void> mostrarNotifPrueba() =>
      NotificationService.instance.mostrarAhora(
        titulo: '🌱 NEXUS Siembras',
        cuerpo: 'Prueba de notificación funcionando correctamente.',
      );

  Future<void> upsertCondicionesPredio({
    double? altitudMsnm,
    double? precipitacionAnualMm,
    double? tempMediaC,
    double? tempMinC,
    double? tempMaxC,
    double? humedadRelativaPct,
    String? zonaClimatica,
    String? pisoTermico,
    String? fuente,
    String? notas,
  }) async {
    final predioId = await _getPredioIdAsync();
    return ref.read(_condicionesRepoProvider).upsert(
          predioId: predioId,
          altitudMsnm: altitudMsnm,
          precipitacionAnualMm: precipitacionAnualMm,
          tempMediaC: tempMediaC,
          tempMinC: tempMinC,
          tempMaxC: tempMaxC,
          humedadRelativaPct: humedadRelativaPct,
          zonaClimatica: zonaClimatica,
          pisoTermico: pisoTermico,
          fuente: fuente,
          notas: notas,
        );
  }
}

final dataMutationsProvider = Provider<DataMutations>((ref) => DataMutations(ref));

// ============ HH (todavía mock) ============

/// Suma total de HH acumuladas por cultivo — provider mock por ahora.
/// Fase 2h: leer desde tabla `cultivos.hh_total` reactivamente.
final hhByCultivoProvider = StateProvider<Map<int, double>>((ref) => {
      1: 8, 2: 5, 3: 12,
    });
