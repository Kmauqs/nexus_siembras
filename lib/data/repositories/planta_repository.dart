import 'package:drift/drift.dart';
import '../database/database.dart';

class PlantaRepository {
  PlantaRepository(this.db);
  final AppDatabase db;

  Stream<List<Planta>> watchAll() {
    return (db.select(db.plantas)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.nombreComun)]))
        .watch();
  }

  Future<Planta?> findById(int id) =>
      (db.select(db.plantas)..where((p) => p.id.equals(id))).getSingleOrNull();

  // ============================================================
  // Mutaciones
  // ============================================================

  Future<int> insert({
    required String nombreComun,
    String? variedad,
    String? especie,
    String? familia,
    int? tiempoCosechaMinDias,
    int? tiempoCosechaMaxDias,
    String? metodoSiembra, // 'directa' | 'germinador'
    int? germinadorDias,
    String? tipoAbono1,
    int? diasAbono2,
    String? tipoAbono2,
    String? fuenteMetodo,
    String? notas,
  }) async {
    final id = await db.into(db.plantas).insert(PlantasCompanion.insert(
          nombreComun: nombreComun,
          variedad: Value(variedad),
          especie: Value(especie),
          familia: Value(familia),
          tiempoCosechaMinDias: Value(tiempoCosechaMinDias),
          tiempoCosechaMaxDias: Value(tiempoCosechaMaxDias),
          metodoSiembra: Value(metodoSiembra),
          germinadorDias: Value(germinadorDias),
          tipoAbono1: Value(tipoAbono1),
          diasAbono2: Value(diasAbono2),
          tipoAbono2: Value(tipoAbono2),
          fuenteMetodo: Value(fuenteMetodo),
          notas: Value(notas),
        ));
    // Fase 3h: auto-poblar PlantaPatologias con las patologías conocidas
    // para la especie botánica. Idempotente y silencioso.
    await autoPopularPatologias(plantaId: id, especie: especie);
    return id;
  }

  Future<void> update({
    required int id,
    required String nombreComun,
    String? variedad,
    String? especie,
    String? familia,
    int? tiempoCosechaMinDias,
    int? tiempoCosechaMaxDias,
    String? metodoSiembra,
    int? germinadorDias,
    String? tipoAbono1,
    int? diasAbono2,
    String? tipoAbono2,
    String? fuenteMetodo,
    String? notas,
  }) async {
    await (db.update(db.plantas)..where((p) => p.id.equals(id))).write(
      PlantasCompanion(
        nombreComun: Value(nombreComun),
        variedad: Value(variedad),
        especie: Value(especie),
        familia: Value(familia),
        tiempoCosechaMinDias: Value(tiempoCosechaMinDias),
        tiempoCosechaMaxDias: Value(tiempoCosechaMaxDias),
        metodoSiembra: Value(metodoSiembra),
        germinadorDias: Value(germinadorDias),
        tipoAbono1: Value(tipoAbono1),
        diasAbono2: Value(diasAbono2),
        tipoAbono2: Value(tipoAbono2),
        fuenteMetodo: Value(fuenteMetodo),
        notas: Value(notas),
        updatedAt: Value(DateTime.now()),
      ),
    );
    // Fase 3h: si la especie cambió, autopoblar nuevas patologías.
    // No borramos las relaciones existentes (el usuario podría haberlas
    // ajustado manualmente); solo insertamos las que falten.
    await autoPopularPatologias(plantaId: id, especie: especie);
  }

  Future<void> softDelete(int id) async {
    await (db.update(db.plantas)..where((p) => p.id.equals(id))).write(
      PlantasCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Cuenta cuántos cultivos ACTIVOS o FINALIZADOS usan esta planta.
  /// Bloquea el borrado si > 0 para evitar inconsistencias.
  Future<int> countCultivosUsando(int plantaId) async {
    final query = db.selectOnly(db.cultivos)
      ..addColumns([db.cultivos.id.count()])
      ..where(db.cultivos.plantaId.equals(plantaId))
      ..where(db.cultivos.deletedAt.isNull());
    final row = await query.getSingle();
    return row.read(db.cultivos.id.count()) ?? 0;
  }

  // ============================================================
  // Fase 3h — Auto-población de patologías por especie
  // ============================================================

  /// Consulta el catálogo `PatologiasEspecies` y crea las relaciones
  /// faltantes en `PlantaPatologias`. Idempotente y silencioso.
  ///
  /// Retorna el número de relaciones NUEVAS creadas (0 si la especie ya
  /// tenía todas sus patologías cargadas o si `especie` es null/vacía).
  Future<int> autoPopularPatologias({
    required int plantaId,
    String? especie,
  }) async {
    final esp = especie?.trim() ?? '';
    if (esp.isEmpty) return 0;
    // Patologías conocidas para esta especie (o cualquier alias).
    final conocidas = await (db.select(db.patologiasEspecies)
          ..where((pe) => pe.especie.equals(esp)))
        .get();
    if (conocidas.isEmpty) return 0;
    // Relaciones ya existentes para esta planta.
    final yaExistentes = (await (db.select(db.plantaPatologias)
              ..where((pp) => pp.plantaId.equals(plantaId)))
            .get())
        .map((r) => r.patologiaId)
        .toSet();
    var creadas = 0;
    for (final pe in conocidas) {
      if (yaExistentes.contains(pe.patologiaId)) continue;
      try {
        await db.into(db.plantaPatologias).insert(
              PlantaPatologiasCompanion.insert(
                plantaId: plantaId,
                patologiaId: pe.patologiaId,
                prevalencia: Value(pe.prevalencia),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        creadas++;
      } catch (_) {
        // Ignorar errores de unicidad (race conditions).
      }
    }
    return creadas;
  }

  /// Lista de Patologías conocidas para una especie botánica (consulta
  /// el catálogo de referencia `PatologiasEspecies`). Se usa en la UI
  /// del modal Agregar/Editar variedad para mostrar preview.
  Future<List<Patologia>> patologiasConocidasPorEspecie(String especie) async {
    if (especie.trim().isEmpty) return const [];
    final query = db.select(db.patologias).join([
      innerJoin(
          db.patologiasEspecies,
          db.patologiasEspecies.patologiaId.equalsExp(db.patologias.id)),
    ])
      ..where(db.patologiasEspecies.especie.equals(especie.trim()))
      ..where(db.patologias.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(db.patologias.nombreComun)]);
    final rows = await query.get();
    return rows.map((r) => r.readTable(db.patologias)).toList();
  }

  /// Cuenta patologías asociadas a una planta a través de `PlantaPatologias`.
  Future<int> countPatologiasAsociadas(int plantaId) async {
    final query = db.selectOnly(db.plantaPatologias)
      ..addColumns([db.plantaPatologias.patologiaId.count()])
      ..where(db.plantaPatologias.plantaId.equals(plantaId));
    final row = await query.getSingle();
    return row.read(db.plantaPatologias.patologiaId.count()) ?? 0;
  }
}
