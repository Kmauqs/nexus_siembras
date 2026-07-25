// NEXUS Siembras — Servicio de actualización del catálogo de patologías
//
// Fase 3i-A: Carga el asset bundleado `assets/data/catalogo_patologias.json`
// y hace merge idempotente en las tablas locales:
//   - Patologias (por nombre_comun + nombre_cientifico como clave natural)
//   - PatologiasEspecies (por patologia_id + especie)
//
// Después del merge, ejecuta autoPopularPatologias sobre TODAS las plantas
// existentes del usuario para propagar cualquier relación nueva.
//
// Ventajas de este enfoque vs. API remota:
//   - Funciona offline (100% assets)
//   - Sin credenciales
//   - Cualquier plataforma (móvil, web, desktop)
//   - Se actualiza subiendo una nueva versión de la app con el JSON expandido
//
// Fase 3i-B (opcional futura): añadir cliente EPPO que consulte online
// como capa complementaria cuando el usuario tenga token configurado.

import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../data/database/database.dart';
import '../data/repositories/planta_repository.dart';
import 'eppo_client.dart';

class CatalogUpdateResult {
  final int patologiasNuevas;
  final int patologiasActualizadas;
  final int relacionesEspecieNuevas;
  final int relacionesPlantaAutoAgregadas;
  /// Contadores independientes de la capa EPPO (Fase 3i-B).
  final int eppoPatologiasNuevas;
  final int eppoRelacionesEspecieNuevas;
  /// Aviso informativo cuando EPPO no se ejecutó o falló parcialmente.
  final String? eppoAviso;
  /// Fase 3e-8: tratamientos recomendados nuevos.
  final int tratamientosNuevos;
  final Duration duracion;
  final String? error;

  const CatalogUpdateResult({
    required this.patologiasNuevas,
    required this.patologiasActualizadas,
    required this.relacionesEspecieNuevas,
    required this.relacionesPlantaAutoAgregadas,
    this.eppoPatologiasNuevas = 0,
    this.eppoRelacionesEspecieNuevas = 0,
    this.eppoAviso,
    this.tratamientosNuevos = 0,
    required this.duracion,
    this.error,
  });

  bool get exito => error == null;

  /// Resumen humano para snackbar.
  String get resumen {
    if (!exito) return 'Error: $error';
    final huboCambios = patologiasNuevas > 0 ||
        relacionesEspecieNuevas > 0 ||
        relacionesPlantaAutoAgregadas > 0 ||
        eppoPatologiasNuevas > 0 ||
        eppoRelacionesEspecieNuevas > 0 ||
        tratamientosNuevos > 0;
    if (!huboCambios) {
      return eppoAviso ?? 'El catálogo ya estaba al día. Sin cambios.';
    }
    final partes = <String>[];
    if (patologiasNuevas > 0) {
      partes.add('+$patologiasNuevas patología'
          '${patologiasNuevas == 1 ? "" : "s"} local'
          '${patologiasNuevas == 1 ? "" : "es"}');
    }
    if (patologiasActualizadas > 0) {
      partes.add('~$patologiasActualizadas actualizada'
          '${patologiasActualizadas == 1 ? "" : "s"}');
    }
    if (relacionesEspecieNuevas > 0) {
      partes.add('+$relacionesEspecieNuevas relación'
          '${relacionesEspecieNuevas == 1 ? "" : "es"} especie');
    }
    if (eppoPatologiasNuevas > 0) {
      partes.add('+$eppoPatologiasNuevas EPPO nueva'
          '${eppoPatologiasNuevas == 1 ? "" : "s"}');
    }
    if (eppoRelacionesEspecieNuevas > 0) {
      partes.add('+$eppoRelacionesEspecieNuevas EPPO especie');
    }
    if (relacionesPlantaAutoAgregadas > 0) {
      partes.add('+$relacionesPlantaAutoAgregadas asociada'
          '${relacionesPlantaAutoAgregadas == 1 ? "" : "s"} a tus variedades');
    }
    if (tratamientosNuevos > 0) {
      partes.add('+$tratamientosNuevos tratamiento'
          '${tratamientosNuevos == 1 ? "" : "s"}');
    }
    final resumenBase = partes.join(' · ');
    return eppoAviso == null ? resumenBase : '$resumenBase · $eppoAviso';
  }
}

class PatologiaCatalogService {
  PatologiaCatalogService(this.db);
  final AppDatabase db;
  static const _assetPath = 'assets/data/catalogo_patologias.json';
  static const _assetTratamientos =
      'assets/data/tratamientos_patologias.json';

  Future<CatalogUpdateResult> actualizarDesdeAsset() async {
    final start = DateTime.now();
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final lista = (json['patologias'] as List).cast<Map<String, dynamic>>();
      var pNuevas = 0;
      var pActualizadas = 0;
      var especiesNuevas = 0;

      for (final item in lista) {
        final nombreComun = (item['nombre_comun'] as String).trim();
        final nombreCient = (item['nombre_cientifico'] as String?)?.trim();
        final tipo = (item['tipo'] as String?)?.trim();
        final sintomas = (item['sintomas'] as String?)?.trim();
        final fuente = (item['fuente'] as String?)?.trim() ?? 'EPPO/FAO';
        final prevalencia = (item['prevalencia'] as String?)?.trim();
        final especies = (item['especies_afectadas'] as List? ?? const [])
            .cast<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

        // Merge Patología por clave natural (nombre_comun + nombre_cientifico)
        final existente = await (db.select(db.patologias)
              ..where((p) => p.nombreComun.equals(nombreComun))
              ..where((p) => nombreCient == null
                  ? p.nombreCientifico.isNull()
                  : p.nombreCientifico.equals(nombreCient))
              ..limit(1))
            .getSingleOrNull();

        int patId;
        if (existente == null) {
          patId = await db.into(db.patologias).insert(
                PatologiasCompanion.insert(
                  nombreComun: nombreComun,
                  nombreCientifico: Value(nombreCient),
                  tipo: Value(tipo),
                  sintomas: Value(sintomas),
                  fuente: Value(fuente),
                ),
              );
          pNuevas++;
        } else {
          patId = existente.id;
          // Actualiza solo si cambiaron los campos descriptivos.
          final cambia = existente.tipo != tipo ||
              existente.sintomas != sintomas ||
              existente.fuente != fuente;
          if (cambia) {
            await (db.update(db.patologias)
                  ..where((p) => p.id.equals(patId)))
                .write(PatologiasCompanion(
              tipo: Value(tipo),
              sintomas: Value(sintomas),
              fuente: Value(fuente),
              updatedAt: Value(DateTime.now()),
            ));
            pActualizadas++;
          }
        }

        // Merge relaciones patología ↔ especie
        for (final esp in especies) {
          final ya = await (db.select(db.patologiasEspecies)
                ..where((pe) => pe.patologiaId.equals(patId))
                ..where((pe) => pe.especie.equals(esp))
                ..limit(1))
              .getSingleOrNull();
          if (ya == null) {
            await db.into(db.patologiasEspecies).insert(
                  PatologiasEspeciesCompanion.insert(
                    patologiaId: patId,
                    especie: esp,
                    prevalencia: Value(prevalencia),
                  ),
                  mode: InsertMode.insertOrIgnore,
                );
            especiesNuevas++;
          }
        }
      }

      // Fase 3i-B: si hay token EPPO configurado, complementar con
      // consultas al catálogo remoto. Silencioso si falla (aviso en resumen).
      int eppoPatNuevas = 0;
      int eppoEspNuevas = 0;
      String? eppoAviso;
      final config = await (db.select(db.configs)..limit(1)).getSingleOrNull();
      final token = config?.eppoToken?.trim();
      if (token != null && token.isNotEmpty) {
        final client = EppoClient(token);
        try {
          final r = await _consultarEppo(client);
          eppoPatNuevas = r.patologiasNuevas;
          eppoEspNuevas = r.relacionesEspecieNuevas;
        } on EppoException catch (e) {
          eppoAviso = 'EPPO: ${e.mensaje}';
        } catch (e) {
          eppoAviso = 'EPPO no disponible';
        } finally {
          client.close();
        }
      }

      // Propagar nuevas relaciones (locales + EPPO) a plantas existentes.
      final repo = PlantaRepository(db);
      var autoAgregadas = 0;
      final plantas = await (db.select(db.plantas)
            ..where((p) => p.deletedAt.isNull()))
          .get();
      for (final pl in plantas) {
        autoAgregadas += await repo.autoPopularPatologias(
          plantaId: pl.id,
          especie: pl.especie,
        );
      }

      // Fase 3e-8: merge de tratamientos desde asset bundleado.
      final tratNuevos = await _mergeTratamientosDesdeAsset();

      // Backfill de tipos taxonómicos vacíos (patologías importadas antes
      // de la heurística de clasificación, o cuyo tipo quedó null tras
      // importar de EPPO). Aplica inferirTipoTaxonomico al nombreCientifico.
      await _backfillTiposVacios();

      return CatalogUpdateResult(
        patologiasNuevas: pNuevas,
        patologiasActualizadas: pActualizadas,
        relacionesEspecieNuevas: especiesNuevas,
        relacionesPlantaAutoAgregadas: autoAgregadas,
        eppoPatologiasNuevas: eppoPatNuevas,
        eppoRelacionesEspecieNuevas: eppoEspNuevas,
        eppoAviso: eppoAviso,
        tratamientosNuevos: tratNuevos,
        duracion: DateTime.now().difference(start),
      );
    } catch (e) {
      return CatalogUpdateResult(
        patologiasNuevas: 0,
        patologiasActualizadas: 0,
        relacionesEspecieNuevas: 0,
        relacionesPlantaAutoAgregadas: 0,
        duracion: DateTime.now().difference(start),
        error: e.toString(),
      );
    }
  }

  /// Fase 3e-8: merge idempotente del catálogo de tratamientos.
  /// Clave natural: (patologiaId, tipo, nombreCorto, paisIso2).
  /// Silencioso si el asset no existe o alguna referencia no matchea.
  Future<int> _mergeTratamientosDesdeAsset() async {
    try {
      final raw = await rootBundle.loadString(_assetTratamientos);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final lista = (json['tratamientos'] as List).cast<Map<String, dynamic>>();
      var nuevos = 0;
      for (final t in lista) {
        final patNombre =
            (t['patologia_nombre'] as String?)?.trim() ?? '';
        final patCient =
            (t['patologia_cientifico'] as String?)?.trim();
        // Resolver patologiaId por clave natural (científico > común).
        Patologia? pat;
        if (patCient != null && patCient.isNotEmpty) {
          pat = await (db.select(db.patologias)
                ..where((p) => p.nombreCientifico.equals(patCient))
                ..limit(1))
              .getSingleOrNull();
        }
        pat ??= patNombre.isNotEmpty
            ? await (db.select(db.patologias)
                  ..where((p) => p.nombreComun.equals(patNombre))
                  ..limit(1))
                .getSingleOrNull()
            : null;
        if (pat == null) continue; // patología no está en el catálogo local
        final paisIso = (t['pais_iso2'] as String?)?.trim();
        final tipo = (t['tipo'] as String?)?.trim() ?? 'cultural';
        final nombreCorto = (t['nombre_corto'] as String).trim();
        // ¿Ya existe la entrada?
        final existente = await (db.select(db.tratamientosPatologias)
              ..where((tt) => tt.patologiaId.equals(pat!.id))
              ..where((tt) => tt.tipo.equals(tipo))
              ..where((tt) => tt.nombreCorto.equals(nombreCorto))
              ..where((tt) => paisIso == null
                  ? tt.paisIso2.isNull()
                  : tt.paisIso2.equals(paisIso))
              ..limit(1))
            .getSingleOrNull();
        if (existente != null) continue;
        final productos = t['productos'];
        await db.into(db.tratamientosPatologias).insert(
              TratamientosPatologiasCompanion.insert(
                patologiaId: pat.id,
                paisIso2: Value(paisIso),
                tipo: tipo,
                nombreCorto: nombreCorto,
                descripcion:
                    Value((t['descripcion'] as String?)?.trim()),
                productos: Value(productos is List
                    ? jsonEncode(productos)
                    : null),
                dosis: Value((t['dosis'] as String?)?.trim()),
                frecuencia: Value((t['frecuencia'] as String?)?.trim()),
                sostenibilidad:
                    Value((t['sostenibilidad'] as String?)?.trim()),
                fuente: Value((t['fuente'] as String?)?.trim()),
                notas: Value((t['notas'] as String?)?.trim()),
              ),
            );
        nuevos++;
      }
      return nuevos;
    } catch (_) {
      // Silencioso: sin el asset o sin patologías coincidentes no hay merge.
      return 0;
    }
  }

  // ==================================================
  // Fase 3i-B — EPPO Global Database
  // ==================================================

  /// Consulta EPPO para las especies únicas presentes en las plantas del
  /// usuario y hace merge de las patologías encontradas.
  /// Retorna un mini-resultado con contadores propios.
  Future<_EppoMergeResult> _consultarEppo(EppoClient client) async {
    // 1. Especies únicas de las plantas del usuario (con especie no vacía).
    final plantas = await (db.select(db.plantas)
          ..where((p) => p.deletedAt.isNull())
          ..where((p) => p.especie.isNotNull()))
        .get();
    final especies = plantas
        .map((p) => p.especie?.trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (especies.isEmpty) {
      return const _EppoMergeResult(
          patologiasNuevas: 0, relacionesEspecieNuevas: 0);
    }

    // 2. Resolver EPPO codes de hosts en una sola llamada batch.
    final hostCodes = await client.resolverEppoCodes(especies);
    if (hostCodes.isEmpty) {
      return const _EppoMergeResult(
          patologiasNuevas: 0, relacionesEspecieNuevas: 0);
    }
    // Mapa inverso: eppocode → nombre científico usado por el usuario.
    final codeToEspecie = <String, String>{};
    hostCodes.forEach((esp, code) => codeToEspecie[code] = esp);

    // 3. Para cada host, pedir pests.
    final pestsPorHost = <String, List<EppoPest>>{};
    for (final code in hostCodes.values) {
      try {
        pestsPorHost[code] = await client.getPestsForHost(code);
      } on EppoException {
        // silencioso — seguimos con el siguiente host
      }
    }

    // 4. Recolectar pests únicos con su prefname (viene incluido en la
    //    respuesta paginada de /taxons/taxon/{code}/pests en v2).
    final pestUnicos = <String, String?>{}; // code → prefname
    for (final lista in pestsPorHost.values) {
      for (final p in lista) {
        pestUnicos.putIfAbsent(p.eppocode, () => p.prefname);
      }
    }
    if (pestUnicos.isEmpty) {
      return const _EppoMergeResult(
          patologiasNuevas: 0, relacionesEspecieNuevas: 0);
    }

    // 5. Merge en Patologias + PatologiasEspecies.
    //    Clave natural para Patologias: nombre_cientifico (más único que
    //    nombre_comun para datos EPPO). Si ya existe una patología con ese
    //    nombre científico, solo añadimos la relación de especie.
    var patNuevas = 0;
    var espNuevas = 0;
    for (final entry in pestsPorHost.entries) {
      final hostCode = entry.key;
      final host = codeToEspecie[hostCode];
      if (host == null) continue;
      for (final pest in entry.value) {
        final prefname = pestUnicos[pest.eppocode]?.trim();
        final nombreCient =
            (prefname != null && prefname.isNotEmpty) ? prefname : null;
        if (nombreCient == null) continue;
        // ¿Ya existe la patología por nombre científico?
        final existente = await (db.select(db.patologias)
              ..where((p) => p.nombreCientifico.equals(nombreCient))
              ..limit(1))
            .getSingleOrNull();
        int patId;
        if (existente == null) {
          patId = await db.into(db.patologias).insert(
                PatologiasCompanion.insert(
                  // Usamos el prefname como nombre común de arranque;
                  // el usuario puede renombrarlo.
                  nombreComun: nombreCient,
                  nombreCientifico: Value(nombreCient),
                  tipo: Value(inferirTipoTaxonomico(nombreCient)),
                  fuente: const Value('EPPO Global DB'),
                ),
              );
          patNuevas++;
        } else {
          patId = existente.id;
          // Backfill de tipo si estaba null (importadas antes de la heurística).
          if (existente.tipo == null || existente.tipo!.isEmpty) {
            final tipoInferido = inferirTipoTaxonomico(nombreCient);
            if (tipoInferido != null) {
              await (db.update(db.patologias)
                    ..where((p) => p.id.equals(patId)))
                  .write(PatologiasCompanion(tipo: Value(tipoInferido)));
            }
          }
        }
        // Añade la relación patología ↔ especie si no existe.
        final yaRel = await (db.select(db.patologiasEspecies)
              ..where((pe) => pe.patologiaId.equals(patId))
              ..where((pe) => pe.especie.equals(host))
              ..limit(1))
            .getSingleOrNull();
        if (yaRel == null) {
          await db.into(db.patologiasEspecies).insert(
                PatologiasEspeciesCompanion.insert(
                  patologiaId: patId,
                  especie: host,
                  prevalencia: const Value('media'),
                ),
                mode: InsertMode.insertOrIgnore,
              );
          espNuevas++;
        }
      }
    }

    return _EppoMergeResult(
        patologiasNuevas: patNuevas, relacionesEspecieNuevas: espNuevas);
  }

  /// Recorre todas las patologías con `tipo` null/vacío y aplica la
  /// heurística de inferencia sobre su nombre científico. Idempotente:
  /// las que no matchean ninguna regla quedan como estaban.
  Future<void> _backfillTiposVacios() async {
    final sinTipo = await (db.select(db.patologias)
          ..where((p) => p.deletedAt.isNull())
          ..where((p) => p.tipo.isNull() | p.tipo.equals('')))
        .get();
    for (final p in sinTipo) {
      final tipoInferido = inferirTipoTaxonomico(p.nombreCientifico);
      if (tipoInferido == null) continue;
      await (db.update(db.patologias)..where((r) => r.id.equals(p.id)))
          .write(PatologiasCompanion(tipo: Value(tipoInferido)));
    }
  }
}

class _EppoMergeResult {
  final int patologiasNuevas;
  final int relacionesEspecieNuevas;
  const _EppoMergeResult({
    required this.patologiasNuevas,
    required this.relacionesEspecieNuevas,
  });
}
