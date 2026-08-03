// NEXUS Siembras — Esquema Drift (SQLite local)
// Alineado con 02_ESQUEMA_BD.md
// Genera código con: dart run build_runner build --delete-conflicting-outputs

import 'package:drift/drift.dart';
import '../seed/seed_service.dart';

// Conector nativo (Android/iOS/Windows/macOS/Linux) vs stub para web.
// El archivo real ('_native.dart') usa dart:ffi; el stub ('_web.dart') lanza
// UnsupportedError para que se integre drift_wasm en Fase 3.
import 'db_connection_stub.dart'
    if (dart.library.io) 'db_connection_native.dart';

part 'database.g.dart';

// ============================================================
// CATÁLOGOS
// ============================================================

class Paises extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text().withLength(min: 1, max: 100).unique()();
  TextColumn get iso2 => text().withLength(min: 2, max: 2).unique()();
}

class Regiones extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get paisId => integer().references(Paises, #id)();
  TextColumn get nombre => text()();
}

class Municipios extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get regionId => integer().references(Regiones, #id)();
  TextColumn get nombre => text()();
}

class UnidadesMedida extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get codigo => text().unique()();
  TextColumn get nombre => text()();
  TextColumn get dimension => text()(); // peso|volumen|longitud|unidad
  TextColumn get sistema => text()();   // SI|imperial|tecnico|cgs|universal
  RealColumn get factorSi => real().withDefault(const Constant(1.0))();
  TextColumn get unidadBase => text()(); // kg|m3|m|und
}

// ============================================================
// PREDIOS
// ============================================================

class Predios extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text()();
  TextColumn get propietario => text().nullable()();
  IntColumn get paisId => integer().nullable().references(Paises, #id)();
  IntColumn get regionId => integer().nullable().references(Regiones, #id)();
  IntColumn get municipioId => integer().nullable().references(Municipios, #id)();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  RealColumn get altM => real().nullable()();
  TextColumn get logoPath => text().nullable()();
  TextColumn get notas => text().nullable()();
  /// UUID (auth.users.id) del propietario original en la nube.
  /// Null → predio creado local (soy dueño por defecto).
  /// Distinto a mi user_id → soy colaborador, NO propietario.
  TextColumn get ownerUserId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

// ============================================================
// PROVEEDORES
// ============================================================

class Proveedores extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text()();
  TextColumn get nit => text().nullable()();
  TextColumn get telefono => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get web => text().nullable()();
  TextColumn get direccion => text().nullable()();
  TextColumn get notas => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

// ============================================================
// PLANTAS
// ============================================================

class Plantas extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombreComun => text()();
  TextColumn get variedad => text().nullable()();
  TextColumn get especie => text().nullable()();
  TextColumn get familia => text().nullable()();
  TextColumn get ciclo => text().nullable()(); // anual|bianual|perenne

  IntColumn get tiempoCosechaMinDias => integer().nullable()();
  IntColumn get tiempoCosechaMaxDias => integer().nullable()();

  /// Tipo de cultivo por defecto al crear un cultivo: `ciclo_unico` | `perenne`.
  TextColumn get tipoCultivoDefault =>
      text().withDefault(const Constant('ciclo_unico'))();
  /// Periodicidad entre cosechas (días) para variedad perenne.
  IntColumn get periodicidadCosechaDias => integer().nullable()();
  /// Esperanza de vida hasta renovación (días) para variedad perenne.
  IntColumn get esperanzaVidaDias => integer().nullable()();
  /// Ciclos de abono JSON: [{tipo, dias}, …] desde fecha base fenológica.
  TextColumn get ciclosAbonoJson => text().nullable()();

  IntColumn get diasAbono1 => integer().nullable()();
  TextColumn get tipoAbono1 => text().nullable()();
  RealColumn get dosisAbono1KgHa => real().nullable()();
  IntColumn get diasAbono2 => integer().nullable()();
  TextColumn get tipoAbono2 => text().nullable()();
  RealColumn get dosisAbono2KgHa => real().nullable()();

  // Método de siembra (v4)
  TextColumn get metodoSiembra => text().nullable()(); // directa|germinador
  IntColumn get germinadorDias => integer().nullable()();
  TextColumn get fuenteMetodo => text().nullable()();

  // Condiciones edafoclimáticas óptimas
  RealColumn get phMin => real().nullable()();
  RealColumn get phMax => real().nullable()();
  RealColumn get phOptimo => real().nullable()();
  RealColumn get tempMinC => real().nullable()();
  RealColumn get tempMaxC => real().nullable()();
  RealColumn get precipMinMm => real().nullable()();
  RealColumn get precipMaxMm => real().nullable()();
  RealColumn get altitudMinM => real().nullable()();
  RealColumn get altitudMaxM => real().nullable()();

  // Requerimientos nutricionales (v3)
  RealColumn get requerimientoNKgHa => real().nullable()();
  RealColumn get requerimientoPKgHa => real().nullable()();
  RealColumn get requerimientoKKgHa => real().nullable()();
  RealColumn get materiaOrganicaMinPct => real().nullable()();
  TextColumn get texturasRecomendadasJson => text().nullable()(); // JSON array
  TextColumn get fuenteAgronomica => text().nullable()(); // ICA|FAO|Corpoica...

  TextColumn get notas => text().nullable()();
  TextColumn get fuente => text().nullable()(); // Wikimedia|ICA|manual
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {nombreComun, variedad}
      ];
}

class PlantaFotos extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get plantaId => integer().references(Plantas, #id, onDelete: KeyAction.cascade)();
  TextColumn get tipo => text()(); // general|hoja|fruto|flor
  TextColumn get path => text()();
  TextColumn get fuente => text().nullable()();
  TextColumn get licencia => text().nullable()();
  TextColumn get autor => text().nullable()();
  TextColumn get urlOriginal => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ============================================================
// PATOLOGÍAS
// ============================================================

class Patologias extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombreComun => text()();
  TextColumn get nombreCientifico => text().nullable()();
  TextColumn get tipo => text().nullable()(); // hongo|bacteria|virus|plaga|nutricional|abiotica|otra
  /// Reclasificación manual del usuario (mismos valores que `tipo`). Cuando
  /// no es null manda sobre `tipo` para agrupar en el listado. Va en columna
  /// aparte porque `PatologiaCatalogService` reescribe `tipo` en cada
  /// "Actualizar" y la elección del usuario tiene que sobrevivir a eso.
  TextColumn get tipoManual => text().nullable()();
  TextColumn get descripcion => text().nullable()();
  TextColumn get sintomas => text().nullable()();
  TextColumn get fuente => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

class PatologiaLinks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get patologiaId => integer().references(Patologias, #id, onDelete: KeyAction.cascade)();
  TextColumn get titulo => text()();
  TextColumn get url => text()();
  TextColumn get tipo => text().nullable()(); // intervencion|prevencion|referencia|imagen
}

class PlantaPatologias extends Table {
  IntColumn get plantaId => integer().references(Plantas, #id, onDelete: KeyAction.cascade)();
  IntColumn get patologiaId => integer().references(Patologias, #id, onDelete: KeyAction.cascade)();
  TextColumn get prevalencia => text().nullable()(); // alta|media|baja

  @override
  Set<Column> get primaryKey => {plantaId, patologiaId};
}

/// Mapa "qué patología afecta qué ESPECIE botánica" (nivel científico),
/// independiente de las variedades del usuario (Fase 3h). Sirve como base
/// de conocimiento: al crear una variedad con especie X, la app consulta
/// esta tabla para auto-poblar `PlantaPatologias` con las patologías
/// conocidas de la especie.
///
/// Datos poblados desde el seed y (en Fase 3i) actualizados desde
/// fuentes externas EPPO/PlantVillage. Es un catálogo local de referencia
/// — no se sincroniza entre dispositivos del usuario.
/// Tratamientos recomendados para una patología (Fase 3e-8). Filtrable
/// por país (paisIso2=null → aplica global). Cada patología puede tener
/// varios tratamientos de distintos tipos (culturales, biológicos,
/// orgánicos, químicos) y niveles de sostenibilidad.
///
/// Se popula desde `assets/data/tratamientos_patologias.json` al pulsar
/// "Actualizar" en Patologías. Es catálogo local de referencia — no se
/// sincroniza entre dispositivos.
class TratamientosPatologias extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get patologiaId =>
      integer().references(Patologias, #id, onDelete: KeyAction.cascade)();
  /// ISO2 del país al que aplica; null = tratamiento aplicable globalmente.
  TextColumn get paisIso2 => text().nullable()();
  /// preventivo | biologico | organico | quimico | cultural
  TextColumn get tipo => text()();
  /// Nombre corto para listar (ej. "Rotación con Poaceae").
  TextColumn get nombreCorto => text()();
  TextColumn get descripcion => text().nullable()();
  /// JSON array opcional con productos comerciales/genéricos sugeridos.
  TextColumn get productos => text().nullable()();
  /// Dosis y frecuencia como texto libre.
  TextColumn get dosis => text().nullable()();
  TextColumn get frecuencia => text().nullable()();
  /// alta | media | baja — impacto ambiental (alta = más sostenible).
  TextColumn get sostenibilidad => text().nullable()();
  TextColumn get fuente => text().nullable()();
  TextColumn get notas => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

class PatologiasEspecies extends Table {
  IntColumn get patologiaId =>
      integer().references(Patologias, #id, onDelete: KeyAction.cascade)();
  TextColumn get especie => text()(); // nombre científico normalizado
  TextColumn get prevalencia => text().nullable()(); // alta|media|baja

  @override
  Set<Column> get primaryKey => {patologiaId, especie};
}

// ============================================================
// INVENTARIO
// ============================================================

class Inventarios extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get predioId => integer().references(Predios, #id)();
  DateTimeColumn get fecha => dateTime()();
  TextColumn get codigo => text().nullable()();
  TextColumn get descripcion => text()();
  TextColumn get fabricante => text().nullable()();
  RealColumn get cantidadBase => real()();
  TextColumn get unidadBase => text()();
  RealColumn get cantidadDisplay => real().nullable()();
  IntColumn get unidadDisplayId => integer().nullable().references(UnidadesMedida, #id)();
  TextColumn get notas => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

// ============================================================
// COMPRAS
// ============================================================

class Compras extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get predioId => integer().references(Predios, #id)();
  IntColumn get proveedorId => integer().nullable().references(Proveedores, #id)();
  DateTimeColumn get fecha => dateTime()();
  TextColumn get descripcion1 => text()();
  TextColumn get descripcion2 => text().nullable()();
  RealColumn get valorTotal => real()();
  RealColumn get cantidadBase => real()();
  TextColumn get unidadBase => text()();
  RealColumn get cantidadDisplay => real().nullable()();
  IntColumn get unidadDisplayId => integer().nullable().references(UnidadesMedida, #id)();
  TextColumn get codigo => text().nullable()();
  TextColumn get factura => text().nullable()();
  TextColumn get soportePath => text().nullable()();
  TextColumn get soporteTipo => text().nullable()(); // application/pdf | image/*
  TextColumn get idUnico => text().nullable()(); // Descripción1-YYMMDD
  TextColumn get tipo => text().nullable()(); // semilla|abono|pesticida|herramienta|servicio|otro
  IntColumn get plantaRef => integer().nullable().references(Plantas, #id)();
  TextColumn get notas => text().nullable()();
  /// UUID Supabase del usuario que registró la compra (co-propietarios).
  TextColumn get createdByUserId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

// ============================================================
// LOTES (v4)
// ============================================================

/// Un lote es una subdivisión del predio con nombre propio, administrador,
/// altitud y polígono georreferenciado (JSON array de [lat, lng]).
class Lotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get predioId => integer().references(Predios, #id)();
  TextColumn get nombre => text()();
  TextColumn get administrador => text().nullable()();
  RealColumn get altitudMsnm => real().nullable()();
  /// Área del lote en m² (opcional, se puede calcular del polígono).
  RealColumn get areaM2 => real().nullable()();
  /// Polígono: JSON array de [lat, lng]. Se cierra automáticamente en la vista.
  TextColumn get poligonoGeoJson => text().nullable()();
  TextColumn get notas => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

// ============================================================
// CULTIVOS
// ============================================================

class Cultivos extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get predioId => integer().references(Predios, #id)();
  IntColumn get plantaId => integer().references(Plantas, #id)();
  IntColumn get compraId => integer().nullable().references(Compras, #id)();
  /// FK opcional al lote (v4). Si es null, el cultivo usa `nombreLote` libre.
  IntColumn get loteId => integer().nullable().references(Lotes, #id)();

  TextColumn get nombreLote => text().nullable()();
  DateTimeColumn get fechaSiembra => dateTime()();
  DateTimeColumn get fechaCosechaEstimada => dateTime().nullable()();

  RealColumn get areaBaseM2 => real().nullable()();
  RealColumn get areaDisplay => real().nullable()();
  IntColumn get areaUnidadId => integer().nullable().references(UnidadesMedida, #id)();

  RealColumn get cantidadSemillaBase => real().nullable()();
  TextColumn get cantidadSemillaUnidadBase => text().nullable()();
  RealColumn get cantidadSemillaDisplay => real().nullable()();
  IntColumn get cantidadSemillaUnidadId => integer().nullable().references(UnidadesMedida, #id)();

  // Georreferenciación
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  RealColumn get altM => real().nullable()();
  TextColumn get poligonoGeoJson => text().nullable()();

  // Mano de obra
  RealColumn get hhTotal => real().withDefault(const Constant(0))();
  RealColumn get horaValor => real().nullable()();

  // Estado
  TextColumn get estadoManual => text().nullable()(); // override manual
  DateTimeColumn get finalizadoFecha => dateTime().nullable()();
  TextColumn get notas => text().nullable()();

  /// Tipo de ciclo productivo: `ciclo_unico` (anual/temporal) o `perenne`.
  TextColumn get tipoCultivo =>
      text().withDefault(const Constant('ciclo_unico'))();
  /// Días desde la fecha base fenológica hasta Cosecha 1 (ciclo único)
  /// o hasta la primera cosecha (cultivo perenne).
  IntColumn get cosecha1Dias => integer().nullable()();
  /// Días desde la fecha base fenológica hasta Cosecha 2 (ciclo único).
  IntColumn get cosecha2Dias => integer().nullable()();
  /// Periodicidad entre cosechas en días (cultivo perenne).
  IntColumn get periodicidadCosechaDias => integer().nullable()();
  /// Esperanza de vida / ciclo hasta renovación en días (cultivo perenne).
  IntColumn get esperanzaVidaDias => integer().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

class EventosCultivo extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cultivoId => integer().references(Cultivos, #id, onDelete: KeyAction.cascade)();
  TextColumn get tipo => text()(); // siembra|abono|riego|control_fito|poda|cosecha|observacion|otro
  DateTimeColumn get fechaProgramada => dateTime().nullable()();
  DateTimeColumn get fechaEjecutada => dateTime().nullable()();
  TextColumn get descripcion => text().nullable()();
  RealColumn get cantidadBase => real().nullable()();
  TextColumn get unidadBase => text().nullable()();
  RealColumn get cantidadDisplay => real().nullable()();
  IntColumn get unidadDisplayId => integer().nullable().references(UnidadesMedida, #id)();
  IntColumn get inventarioId => integer().nullable().references(Inventarios, #id)();
  TextColumn get notas => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

class TareasCompletadas extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cultivoId => integer().references(Cultivos, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get fecha => dateTime()();
  RealColumn get hh => real().withDefault(const Constant(0))();
  TextColumn get actividadesJson => text()(); // JSON array de strings
  /// JSON array de {desc, cantidad, unidad} para consumo del inventario.
  /// Persistir insumos por tarea permite restaurar el inventario si se borra
  /// la tarea, y mostrar los insumos usados en la vista de cada cultivo.
  TextColumn get insumosJson => text().withDefault(const Constant('[]'))();
  TextColumn get notas => text().nullable()();
  /// UUID del usuario Supabase que registró la tarea (Fase 3g). Nullable
  /// para (a) tareas creadas antes de la migración v9, y (b) tareas
  /// creadas en modo local sin sesión.
  TextColumn get createdByUserId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class CosechasRegistradas extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cultivoId => integer().references(Cultivos, #id, onDelete: KeyAction.cascade)();
  TextColumn get tipo => text()(); // cosecha1|cosecha2
  DateTimeColumn get fecha => dateTime()();
  RealColumn get cantidad => real()();
  TextColumn get unidad => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class ActividadesCustom extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cultivoId => integer().references(Cultivos, #id, onDelete: KeyAction.cascade)();
  TextColumn get nombre => text()();
}

class CultivoPatologias extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cultivoId => integer().references(Cultivos, #id, onDelete: KeyAction.cascade)();
  IntColumn get patologiaId => integer().nullable().references(Patologias, #id)();
  /// Nombre denormalizado para sync entre colaboradores (el catálogo local
  /// no se sincroniza; el peer resuelve o crea la patología por nombre).
  TextColumn get patologiaNombre => text().nullable()();
  DateTimeColumn get fechaDeteccion => dateTime()();
  TextColumn get severidad => text().nullable()(); // inicial|avanzada
  TextColumn get fotoPath => text().nullable()();
  TextColumn get fuenteDiagnostico => text().nullable()(); // lens|manual|clasificador_local
  RealColumn get confianza => real().nullable()();
  DateTimeColumn get resueltaAt => dateTime().nullable()();
  DateTimeColumn get curaFecha => dateTime().nullable()();
  TextColumn get intervencionesJson => text().withDefault(const Constant('[]'))();
  TextColumn get notas => text().nullable()();
  // GNSS del reporte (v12 — Fase 3e-5). Se capturan al levantar el reporte
  // para poder pintar el mapa de patologías del predio y (si se comparte)
  // enviar como reporte comunitario anonimizado.
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  RealColumn get altM => real().nullable()();
  /// True si el reporte se envió a la tabla comunitaria PatologiasReportadas.
  BoolColumn get compartida =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

// ============================================================
// ANÁLISIS DE SUELO Y CONDICIONES EDAFOCLIMÁTICAS (v3)
// ============================================================

/// Registro puntual de un muestreo/análisis físico-químico de suelo.
class AnalisisSuelo extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get predioId => integer().references(Predios, #id)();
  TextColumn get lote => text().nullable()();
  DateTimeColumn get fechaMuestreo => dateTime()();
  TextColumn get laboratorio => text().nullable()();
  RealColumn get profundidadCm => real().nullable()();

  // Físicas
  TextColumn get textura => text().nullable()(); // arenoso|franco|arcilloso|franco-arenoso|franco-arcilloso
  RealColumn get densidadGCm3 => real().nullable()();
  RealColumn get conductividadMsCm => real().nullable()();

  // Químicas
  RealColumn get ph => real().nullable()();
  RealColumn get materiaOrganicaPct => real().nullable()();
  RealColumn get nPpm => real().nullable()();
  RealColumn get pPpm => real().nullable()();
  RealColumn get kPpm => real().nullable()();
  RealColumn get caMeq => real().nullable()();
  RealColumn get mgMeq => real().nullable()();
  RealColumn get naMeq => real().nullable()();
  RealColumn get cicMeq => real().nullable()();
  RealColumn get sPpm => real().nullable()();
  RealColumn get bPpm => real().nullable()();

  TextColumn get soportePath => text().nullable()();
  TextColumn get soporteTipo => text().nullable()(); // application/pdf | image/*
  TextColumn get notas => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// Condiciones edafoclimáticas del predio (una fila por predio).
class CondicionesPredio extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get predioId => integer().references(Predios, #id).unique()();
  RealColumn get altitudMsnm => real().nullable()();
  RealColumn get precipitacionAnualMm => real().nullable()();
  RealColumn get tempMediaC => real().nullable()();
  RealColumn get tempMinC => real().nullable()();
  RealColumn get tempMaxC => real().nullable()();
  RealColumn get humedadRelativaPct => real().nullable()();
  TextColumn get zonaClimatica => text().nullable()(); // tropical seco|tropical húmedo|templado|frío|páramo
  TextColumn get pisoTermico => text().nullable()(); // cálido|templado|frío|páramo
  TextColumn get fuente => text().nullable()(); // IDEAM|medición propia|estimación
  DateTimeColumn get fechaActualizacion => dateTime().withDefault(currentDateAndTime)();
  TextColumn get notas => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

// ============================================================
// COLABORADORES DE PREDIO (Fase 3e - multi-usuario)
// ============================================================

/// Espejo local de `predio_shares` remoto. Guarda quiénes son los
/// colaboradores de cada predio del usuario, más los predios en los
/// que el usuario ha sido invitado como colaborador.
class PredioColaboradores extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get predioId => integer().references(Predios, #id, onDelete: KeyAction.cascade)();
  /// Email del colaborador (para display; el matching remoto es por UUID)
  TextColumn get colaboradorEmail => text()();
  /// UUID de auth.users del colaborador
  TextColumn get colaboradorUserId => text().nullable()();
  /// Rol: propietario | trabajador | consultor
  TextColumn get rol => text()();
  DateTimeColumn get invitadoAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get aceptadoAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

// ============================================================
// PATOLOGÍAS REPORTADAS (Fase 3e - contribución comunitaria)
// ============================================================

/// Reportes de patologías detectadas por el usuario, con foto y GNSS.
/// Se sincronizan al servidor si el usuario aceptó el consentimiento.
class PatologiasReportadas extends Table {
  IntColumn get id => integer().autoIncrement()();
  /// Opcional: link a la detección en `cultivo_patologias`
  IntColumn get cultivoPatologiaId =>
      integer().nullable().references(CultivoPatologias, #id)();
  TextColumn get patologiaNombre => text()();
  TextColumn get patologiaCientifico => text().nullable()();
  TextColumn get plantaNombre => text().nullable()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  RealColumn get altM => real().nullable()();
  DateTimeColumn get fechaDeteccion => dateTime()();
  TextColumn get severidad => text().nullable()(); // inicial | avanzada
  TextColumn get sintomas => text().nullable()();
  /// Path local de la foto (en documents/patologias/uuid.jpg)
  TextColumn get fotoLocalPath => text().nullable()();
  /// URL Supabase Storage después de subir (null si aún no sincronizado)
  TextColumn get fotoRemoteUrl => text().nullable()();
  TextColumn get paisIso2 => text().nullable()();
  TextColumn get regionNombre => text().nullable()();
  TextColumn get municipioNombre => text().nullable()();
  RealColumn get climaTempC => real().nullable()();
  RealColumn get climaHumedadPct => real().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

// ============================================================
// SYNC STATE (Fase 3d - Supabase sync)
// ============================================================

/// Mapping local ↔ remoto por fila sincronizada.
///
/// Cada fila representa una fila de una tabla local que fue subida
/// al menos una vez a Supabase. Se usa para:
///   - Evitar duplicar registros al re-sincronizar (buscar por local_id
///     antes de insertar)
///   - Resolver FKs al hacer push (traducir predio_id local → remoto)
///   - Aplicar last-write-wins con `last_pushed_at`
class SyncMappings extends Table {
  IntColumn get id => integer().autoIncrement()();
  /// Nombre lógico de la tabla local (predios, cultivos, etc.)
  TextColumn get tabla => text()();
  /// ID de la fila en la BD local
  IntColumn get localId => integer()();
  /// ID de la fila en Supabase (BIGSERIAL)
  IntColumn get remoteId => integer()();
  /// Timestamp del último push exitoso hacia la nube
  DateTimeColumn get lastPushedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {tabla, localId},
        {tabla, remoteId},
      ];
}

/// Estado global de sincronización por tabla.
class SyncTables extends Table {
  TextColumn get tabla => text()();
  /// Timestamp del último pull exitoso de esta tabla (para el filtro
  /// `updated_at > last_pulled_at` en la consulta remota).
  DateTimeColumn get lastPulledAt => dateTime().nullable()();
  /// Timestamp del último intento de sync (push + pull), exitoso o no.
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  /// Último error legible por el usuario, null si el último intento fue OK.
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {tabla};
}

/// Cola persistente de operaciones remotas (v14 — Fase B5, 2026-07-20).
///
/// El sync por estado (updated_at vs lastPushedAt) cubre inserts/updates:
/// la propia BD local es la "cola". Lo que NO cubre son las operaciones
/// puntuales que fallan sin conexión — principalmente los DELETE remotos
/// al vaciar la papelera: antes se perdían y la fila revivía en el
/// siguiente pull. Estas operaciones se encolan aquí y se procesan al
/// inicio de cada sincronización, con reintentos y descarte tras un
/// máximo de intentos (cola envenenada).
class SyncOps extends Table {
  IntColumn get id => integer().autoIncrement()();
  /// Tipo de operación: 'delete_remoto' (extensible a futuro).
  TextColumn get tipo => text()();
  /// Tabla remota objetivo (predios, cultivos, …).
  TextColumn get tabla => text()();
  /// ID remoto sobre el que opera (para delete_remoto).
  IntColumn get remoteId => integer().nullable()();
  /// Datos adicionales de la operación (JSON), según el tipo.
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();
  IntColumn get intentos => integer().withDefault(const Constant(0))();
  TextColumn get ultimoError => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ============================================================
// CONFIGURACIÓN (single row)
// ============================================================

class Configs extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get idioma => text().withDefault(const Constant('es'))();
  TextColumn get estiloUi => text().withDefault(const Constant('material'))();
  TextColumn get sistemaUnidades => text().withDefault(const Constant('SI'))();
  IntColumn get predioActivoId => integer().nullable().references(Predios, #id)();
  TextColumn get monedaCodigo => text().withDefault(const Constant('COP'))();
  BoolColumn get primeraEjecucion => boolean().withDefault(const Constant(true))();
  BoolColumn get permisosSolicitados => boolean().withDefault(const Constant(false))();
  // Notificaciones locales (v5)
  BoolColumn get notificacionesHabilitadas =>
      boolean().withDefault(const Constant(true))();
  /// Cuántos días antes de la fecha programada se dispara el aviso.
  IntColumn get notificacionAntelacionDias =>
      integer().withDefault(const Constant(3))();
  // Consentimiento comunitario (v7)
  /// Opt-in para compartir reportes de patologías con la comunidad.
  BoolColumn get consentimientoPatologias =>
      boolean().withDefault(const Constant(false))();
  /// Token personal para EPPO Global Database (v11 — Fase 3i-B). Nullable:
  /// si es null la app solo usa el catálogo bundleado local.
  TextColumn get eppoToken => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Espejo local de `variedades_comunitarias` (Supabase). Se refresca al
/// arrancar la app (con sesión) para autocompletar el modal "Nueva variedad"
/// sin depender de una búsqueda remota en cada tecleo.
class VariedadesComunitariasCache extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get remoteId => integer().unique()();
  TextColumn get nombreComun => text()();
  /// Clave de especie normalizada ('' si no hay) para deduplicar localmente.
  TextColumn get especieKey => text().withDefault(const Constant(''))();
  TextColumn get especie => text().nullable()();
  TextColumn get metodoSiembra => text().nullable()();
  IntColumn get germinadorDias => integer().nullable()();
  IntColumn get cosechaMinDias => integer().nullable()();
  IntColumn get cosechaMaxDias => integer().nullable()();
  TextColumn get tipoAbono1 => text().nullable()();
  TextColumn get tipoAbono2 => text().nullable()();
  IntColumn get abono2Dias => integer().nullable()();
  TextColumn get fuente => text().nullable()();
  IntColumn get contribuciones => integer().withDefault(const Constant(1))();
  DateTimeColumn get remoteUpdatedAt => dateTime().nullable()();
  DateTimeColumn get syncedAt => dateTime().withDefault(currentDateAndTime)();
}

// ============================================================
// DATABASE CLASS
// ============================================================

@DriftDatabase(tables: [
  Paises, Regiones, Municipios, UnidadesMedida,
  Predios, Proveedores,
  Plantas, PlantaFotos,
  Patologias, PatologiaLinks, PlantaPatologias, PatologiasEspecies,
  TratamientosPatologias,
  Inventarios, Compras,
  Lotes,
  Cultivos, EventosCultivo, TareasCompletadas, CosechasRegistradas,
  ActividadesCustom, CultivoPatologias,
  AnalisisSuelo, CondicionesPredio,
  PredioColaboradores, PatologiasReportadas,
  SyncMappings, SyncTables, SyncOps,
  VariedadesComunitariasCache,
  Configs,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase()
      : _skipSeed = false,
        super(openConnection());

  /// BD en memoria (o executor inyectado) sin catálogo seed — solo tests.
  AppDatabase.forTesting(QueryExecutor executor)
      : _skipSeed = true,
        super(executor);

  final bool _skipSeed;

  @override
  int get schemaVersion => 20;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          if (!_skipSeed) {
            await SeedService(this).run();
          }
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2: agrega insumos_json a tareas_completadas
            await m.addColumn(tareasCompletadas, tareasCompletadas.insumosJson);
          }
          if (from < 3) {
            // v3: análisis de suelo, condiciones edafoclim del predio,
            // requerimientos nutricionales por planta
            await m.createTable(analisisSuelo);
            await m.createTable(condicionesPredio);
            await m.addColumn(plantas, plantas.phOptimo);
            await m.addColumn(plantas, plantas.requerimientoNKgHa);
            await m.addColumn(plantas, plantas.requerimientoPKgHa);
            await m.addColumn(plantas, plantas.requerimientoKKgHa);
            await m.addColumn(plantas, plantas.materiaOrganicaMinPct);
            await m.addColumn(plantas, plantas.texturasRecomendadasJson);
            await m.addColumn(plantas, plantas.fuenteAgronomica);
            await SeedService(this).seedRequerimientosPlantasV3();
          }
          if (from < 4) {
            // v4: Lotes como entidad + FK opcional en Cultivos
            await m.createTable(lotes);
            await m.addColumn(cultivos, cultivos.loteId);
          }
          if (from < 5) {
            // v5: config de notificaciones locales
            await m.addColumn(configs, configs.notificacionesHabilitadas);
            await m.addColumn(configs, configs.notificacionAntelacionDias);
          }
          if (from < 6) {
            // v6: sync con Supabase — tablas de mapping y estado
            await m.createTable(syncMappings);
            await m.createTable(syncTables);
          }
          if (from < 7) {
            // v7: multi-usuario (colaboradores) + patologías comunitarias
            await m.createTable(predioColaboradores);
            await m.createTable(patologiasReportadas);
            await m.addColumn(configs, configs.consentimientoPatologias);
          }
          if (from < 8) {
            // v8: guardar UUID del propietario remoto en predios
            // (para determinar rol correctamente al listar colaboradores)
            await m.addColumn(predios, predios.ownerUserId);
          }
          if (from < 9) {
            // v9: trazabilidad — quién registró cada tarea completada.
            // NULL = tarea legacy (antes de v9) o creada en modo local.
            await m.addColumn(
                tareasCompletadas, tareasCompletadas.createdByUserId);
          }
          if (from < 10) {
            // v10: mapa patología↔especie botánica (Fase 3h) para
            // auto-poblar PlantaPatologias al crear una nueva variedad.
            await m.createTable(patologiasEspecies);
            await SeedService(this).seedPatologiasEspeciesV10();
          }
          if (from < 11) {
            // v11: token EPPO Global Database (Fase 3i-B).
            await m.addColumn(configs, configs.eppoToken);
          }
          if (from < 12) {
            // v12: GNSS + flag compartida en reportes de patologías
            // (Fase 3e-5). Se llenan al levantar cada reporte.
            await m.addColumn(cultivoPatologias, cultivoPatologias.lat);
            await m.addColumn(cultivoPatologias, cultivoPatologias.lng);
            await m.addColumn(cultivoPatologias, cultivoPatologias.altM);
            await m.addColumn(
                cultivoPatologias, cultivoPatologias.compartida);
          }
          if (from < 13) {
            // v13: catálogo de tratamientos por patología (Fase 3e-8).
            // Se popula posteriormente vía "Actualizar" en Patologías.
            await m.createTable(tratamientosPatologias);
          }
          if (from < 14) {
            // v14: cola persistente de operaciones remotas (Fase B5).
            await m.createTable(syncOps);
          }
          if (from < 15) {
            // v15: tipo de cultivo (ciclo único vs perenne) y parámetros
            // de cosecha / renovación.
            await m.addColumn(cultivos, cultivos.tipoCultivo);
            await m.addColumn(cultivos, cultivos.cosecha1Dias);
            await m.addColumn(cultivos, cultivos.cosecha2Dias);
            await m.addColumn(cultivos, cultivos.periodicidadCosechaDias);
            await m.addColumn(cultivos, cultivos.esperanzaVidaDias);
          }
          if (from < 16) {
            // v16: tipo de cultivo y periodos en catálogo de plantas +
            // ciclos de abono dinámicos.
            await m.addColumn(plantas, plantas.tipoCultivoDefault);
            await m.addColumn(plantas, plantas.periodicidadCosechaDias);
            await m.addColumn(plantas, plantas.esperanzaVidaDias);
            await m.addColumn(plantas, plantas.ciclosAbonoJson);
          }
          if (from < 17) {
            // v17: reclasificación manual de patologías del catálogo
            // (override de la agrupación automática por tipo taxonómico).
            await m.addColumn(patologias, patologias.tipoManual);
          }
          if (from < 18) {
            // v18: caché local del banco comunitario de variedades.
            await m.createTable(variedadesComunitariasCache);
          }
          if (from < 19) {
            // v19: autor de cada compra (trazabilidad entre co-propietarios).
            await m.addColumn(compras, compras.createdByUserId);
          }
          if (from < 20) {
            // v20: sync de patologías por cultivo entre colaboradores.
            // NO usar m.addColumn para updatedAt: su default
            // (currentDateAndTime) no es constante y SQLite lo prohíbe en
            // ALTER TABLE ("Cannot add a column with non-constant default",
            // bug 2026-07-31). Se agrega con default constante y se
            // backfillea desde created_at. Guard por PRAGMA para tolerar
            // una migración previa que quedó a medias.
            final cols = await customSelect(
              "SELECT name FROM pragma_table_info('cultivo_patologias')",
            ).get();
            final nombres = {
              for (final row in cols) row.read<String>('name'),
            };
            if (!nombres.contains('patologia_nombre')) {
              await m.addColumn(
                  cultivoPatologias, cultivoPatologias.patologiaNombre);
            }
            if (!nombres.contains('updated_at')) {
              await customStatement(
                  'ALTER TABLE cultivo_patologias '
                  'ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
              await customStatement(
                  'UPDATE cultivo_patologias SET updated_at = created_at');
            }
          }
        },
      );
}

// _openConnection() está definido en db_connection_native.dart (móvil/desktop)
// o en db_connection_stub.dart (web — pendiente drift_wasm).
