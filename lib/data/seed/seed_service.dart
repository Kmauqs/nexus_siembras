// NEXUS Siembras — Seed mínimo (solo catálogos, sin datos operativos).
// Al primer arranque solo se cargan:
//   - Catálogo de unidades de medida
//   - Geografía base (país/región/municipio)
//   - Catálogo de plantas (variedades)
//   - Catálogo de patologías + join planta_patologias
//   - Config con primeraEjecucion=true (dispara onboarding en la UI)
//
// El usuario crea predio/proveedores/compras/inventario/cultivos desde la app.

import 'dart:convert';
import 'package:drift/drift.dart';
import '../database/database.dart';

class SeedService {
  SeedService(this.db);
  final AppDatabase db;

  Future<void> run() async {
    // IDEMPOTENTE (fix 2026-07-19): `onCreate` puede re-ejecutarse sobre
    // una BD ya poblada (p. ej. la migración a SQLCipher no copiaba el
    // user_version y Drift re-corría onCreate). Cada sección se salta si
    // su catálogo ya tiene filas, y la config NUNCA se sobreescribe
    // (insertOrReplace machacaba predioActivoId y primeraEjecucion).
    final hayUnidades =
        (await (db.select(db.unidadesMedida)..limit(1)).get()).isNotEmpty;
    if (!hayUnidades) await _seedUnidades();

    final hayPaises = (await (db.select(db.paises)..limit(1)).get()).isNotEmpty;
    if (!hayPaises) await _seedGeoBase();

    final hayPlantas =
        (await (db.select(db.plantas)..limit(1)).get()).isNotEmpty;
    if (!hayPlantas) {
      final plantaIds = await _seedPlantas();
      await _seedPatologias(plantaIds);
    }

    // Config inicial: primeraEjecucion true → activa onboarding en la UI.
    // insertOrIgnore: si ya existe una config (usuario a mitad de camino o
    // instalación previa), se conserva tal cual.
    await db.into(db.configs).insert(
          ConfigsCompanion.insert(),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _seedUnidades() async {
    Future<void> ins(String c, String n, String d, String s, double f, String b) =>
        db.into(db.unidadesMedida).insert(UnidadesMedidaCompanion.insert(
              codigo: c, nombre: n, dimension: d, sistema: s,
              factorSi: Value(f), unidadBase: b,
            ));
    // Peso
    await ins('ton','Tonelada','peso','SI',1000,'kg');
    await ins('kg','Kilogramo','peso','SI',1,'kg');
    await ins('gr','Gramo','peso','SI',0.001,'kg');
    await ins('lb','Libra','peso','imperial',0.45359237,'kg');
    await ins('oz','Onza','peso','imperial',0.0283495,'kg');
    await ins('@','Arroba (12.5 kg)','peso','universal',12.5,'kg');
    await ins('carga','Carga (125 kg)','peso','universal',125.0,'kg');
    await ins('bulto22','Bulto 22.5 kg','peso','universal',22.5,'kg');
    await ins('bulto25','Bulto 25 kg','peso','universal',25.0,'kg');
    await ins('bulto50','Bulto 50 kg','peso','universal',50.0,'kg');
    await ins('bulto70','Bulto 70 kg','peso','universal',70.0,'kg');
    // Volumen
    await ins('m3','Metro cúbico','volumen','SI',1,'m3');
    await ins('l','Litro','volumen','SI',0.001,'m3');
    await ins('ml','Mililitro','volumen','SI',1e-6,'m3');
    await ins('gal','Galón (US)','volumen','imperial',0.003785411,'m3');
    // Longitud
    await ins('m','Metro','longitud','SI',1,'m');
    await ins('cm','Centímetro','longitud','SI',0.01,'m');
    await ins('km','Kilómetro','longitud','SI',1000,'m');
    // Área
    await ins('m2','Metro cuadrado','area','SI',1,'m2');
    await ins('ha','Hectárea','area','SI',10000,'m2');
    await ins('cuadra','Cuadra (Col ≈ 80×80 m)','area','universal',6400,'m2');
    await ins('acre','Acre','area','imperial',4046.856,'m2');
    // Unidad
    await ins('und','Unidad','unidad','universal',1,'und');
  }

  Future<void> _seedGeoBase() async {
    Future<int> pais(String nombre, String iso2) =>
        db.into(db.paises).insert(PaisesCompanion.insert(nombre: nombre, iso2: iso2));
    Future<int> region(int paisId, String nombre) =>
        db.into(db.regiones).insert(RegionesCompanion.insert(paisId: paisId, nombre: nombre));
    Future<void> muni(int regionId, String nombre) => db
        .into(db.municipios).insert(MunicipiosCompanion.insert(regionId: regionId, nombre: nombre));

    // Colombia (con departamentos y municipios comunes de zonas cafeteras)
    final co = await pais('Colombia', 'CO');
    final quindio = await region(co, 'Quindío');
    await muni(quindio, 'Armenia');
    await muni(quindio, 'Calarcá');
    await muni(quindio, 'Circasia');
    await muni(quindio, 'Filandia');
    await muni(quindio, 'Salento');
    final risaralda = await region(co, 'Risaralda');
    await muni(risaralda, 'Pereira');
    await muni(risaralda, 'Dosquebradas');
    final caldas = await region(co, 'Caldas');
    await muni(caldas, 'Manizales');
    await muni(caldas, 'Chinchiná');
    final antioquia = await region(co, 'Antioquia');
    await muni(antioquia, 'Medellín');
    await muni(antioquia, 'Envigado');
    final cundinamarca = await region(co, 'Cundinamarca');
    await muni(cundinamarca, 'Bogotá D.C.');
    // Otros países LATAM (solo capital/región principal para MVP)
    final mx = await pais('México', 'MX');
    final cdmx = await region(mx, 'Ciudad de México');
    await muni(cdmx, 'Ciudad de México');
    final br = await pais('Brasil', 'BR');
    final sp = await region(br, 'São Paulo');
    await muni(sp, 'São Paulo');
  }

  Future<Map<String, int>> _seedPlantas() async {
    final ids = <String, int>{};
    Future<int> p({
      required String nombre, required String especie,
      required int cosMin, required int cosMax, required int abono2,
      required String metodo, int? germDias, required String fuente,
      String? tipoAb1, String? tipoAb2,
      // Edafoclimáticos (v3)
      double? phMin, double? phMax, double? phOpt,
      double? tempMin, double? tempMax,
      double? precipMin, double? precipMax,
      double? altMin, double? altMax,
      // Nutricionales (v3)
      double? nKgHa, double? pKgHa, double? kKgHa,
      double? moMin, List<String>? texturas,
      String? fuenteAgro,
    }) async {
      final id = await db.into(db.plantas).insert(PlantasCompanion.insert(
            nombreComun: nombre,
            especie: Value(especie),
            tiempoCosechaMinDias: Value(cosMin),
            tiempoCosechaMaxDias: Value(cosMax),
            diasAbono1: const Value(1),
            diasAbono2: Value(abono2),
            tipoAbono1: Value(tipoAb1),
            tipoAbono2: Value(tipoAb2),
            metodoSiembra: Value(metodo),
            germinadorDias: Value(germDias),
            fuenteMetodo: Value(fuente),
            phMin: Value(phMin),
            phMax: Value(phMax),
            phOptimo: Value(phOpt),
            tempMinC: Value(tempMin),
            tempMaxC: Value(tempMax),
            precipMinMm: Value(precipMin),
            precipMaxMm: Value(precipMax),
            altitudMinM: Value(altMin),
            altitudMaxM: Value(altMax),
            requerimientoNKgHa: Value(nKgHa),
            requerimientoPKgHa: Value(pKgHa),
            requerimientoKKgHa: Value(kKgHa),
            materiaOrganicaMinPct: Value(moMin),
            texturasRecomendadasJson:
                Value(texturas != null ? jsonEncode(texturas) : null),
            fuenteAgronomica: Value(fuenteAgro),
          ));
      ids[nombre] = id;
      return id;
    }
    await p(
        nombre:'Maíz ICA V-305', especie:'Zea mays L.',
        cosMin:90, cosMax:100, abono2:45,
        metodo:'directa', fuente:'ICA — Siembra directa',
        tipoAb1:'Gallinaza', tipoAb2:'Urea 15-15-15',
        phMin:5.5, phMax:7.5, phOpt:6.5,
        tempMin:15, tempMax:30, precipMin:500, precipMax:1200,
        altMin:0, altMax:2600,
        nKgHa:120, pKgHa:60, kKgHa:80, moMin:3.0,
        texturas:['franco','franco-arenoso','franco-arcilloso'],
        fuenteAgro:'ICA / Corpoica');
    await p(
        nombre:'Frijol Cargamanto', especie:'Phaseolus vulgaris',
        cosMin:90, cosMax:140, abono2:35,
        metodo:'directa', fuente:'CIAT — Siembra directa',
        tipoAb1:'Gallinaza', tipoAb2:'DAP 18-46-0',
        phMin:6.0, phMax:7.5, phOpt:6.5,
        tempMin:15, tempMax:27, precipMin:300, precipMax:600,
        altMin:1200, altMax:2400,
        nKgHa:40, pKgHa:60, kKgHa:40, moMin:3.0,
        texturas:['franco','franco-arenoso'],
        fuenteAgro:'CIAT / Corpoica');
    await p(
        nombre:'Papaya Melona', especie:'Carica papaya',
        cosMin:210, cosMax:240, abono2:90,
        metodo:'germinador', germDias:45,
        fuente:'ICA — Semillero 45 días, trasplante',
        tipoAb1:'Compost', tipoAb2:'Triple 15',
        phMin:6.0, phMax:7.0, phOpt:6.5,
        tempMin:21, tempMax:33, precipMin:1200, precipMax:2000,
        altMin:0, altMax:1500,
        nKgHa:200, pKgHa:60, kKgHa:300, moMin:4.0,
        texturas:['franco','franco-arenoso'],
        fuenteAgro:'FAO / ICA');
    await p(
        nombre:'Pimentón California Wonder', especie:'Capsicum annuum',
        cosMin:90, cosMax:120, abono2:40,
        metodo:'germinador', germDias:35,
        fuente:'FAO — Semillero 30-40 días, trasplante',
        tipoAb1:'Bocashi', tipoAb2:'Nitrato Ca',
        phMin:6.0, phMax:7.0, phOpt:6.5,
        tempMin:18, tempMax:27, precipMin:600, precipMax:1200,
        altMin:500, altMax:2000,
        nKgHa:150, pKgHa:100, kKgHa:200, moMin:3.5,
        texturas:['franco','franco-arenoso','franco-arcilloso'],
        fuenteAgro:'FAO');
    return ids;
  }

  /// Rellena los requerimientos agronómicos (v3) para las plantas del seed
  /// que ya fueron creadas en versiones anteriores. Llamado desde onUpgrade.
  Future<void> seedRequerimientosPlantasV3() async {
    Future<void> upd(String nombre, PlantasCompanion c) async {
      await (db.update(db.plantas)
            ..where((p) => p.nombreComun.equals(nombre)))
          .write(c);
    }
    await upd('Maíz ICA V-305', PlantasCompanion(
      phOptimo: const Value(6.5),
      requerimientoNKgHa: const Value(120),
      requerimientoPKgHa: const Value(60),
      requerimientoKKgHa: const Value(80),
      materiaOrganicaMinPct: const Value(3.0),
      texturasRecomendadasJson: Value(jsonEncode(
          ['franco', 'franco-arenoso', 'franco-arcilloso'])),
      fuenteAgronomica: const Value('ICA / Corpoica'),
    ));
    await upd('Frijol Cargamanto', PlantasCompanion(
      phOptimo: const Value(6.5),
      requerimientoNKgHa: const Value(40),
      requerimientoPKgHa: const Value(60),
      requerimientoKKgHa: const Value(40),
      materiaOrganicaMinPct: const Value(3.0),
      texturasRecomendadasJson: Value(jsonEncode(['franco', 'franco-arenoso'])),
      fuenteAgronomica: const Value('CIAT / Corpoica'),
    ));
    await upd('Papaya Melona', PlantasCompanion(
      phOptimo: const Value(6.5),
      requerimientoNKgHa: const Value(200),
      requerimientoPKgHa: const Value(60),
      requerimientoKKgHa: const Value(300),
      materiaOrganicaMinPct: const Value(4.0),
      texturasRecomendadasJson: Value(jsonEncode(['franco', 'franco-arenoso'])),
      fuenteAgronomica: const Value('FAO / ICA'),
    ));
    await upd('Pimentón California Wonder', PlantasCompanion(
      phOptimo: const Value(6.5),
      requerimientoNKgHa: const Value(150),
      requerimientoPKgHa: const Value(100),
      requerimientoKKgHa: const Value(200),
      materiaOrganicaMinPct: const Value(3.5),
      texturasRecomendadasJson: Value(jsonEncode(
          ['franco', 'franco-arenoso', 'franco-arcilloso'])),
      fuenteAgronomica: const Value('FAO'),
    ));
  }

  Future<void> _seedPatologias(Map<String, int> plantas) async {
    Future<int> pat(String nombre, String cientifico, String tipo,
        List<String> plantasAfectadas,
        {List<String> especiesAfectadas = const []}) async {
      final id = await db.into(db.patologias).insert(
          PatologiasCompanion.insert(
              nombreComun: nombre,
              nombreCientifico: Value(cientifico),
              tipo: Value(tipo),
              fuente: const Value('EPPO/PlantVillage')));
      // 1) Relaciones directas planta ↔ patología (variedades del seed).
      for (final pn in plantasAfectadas) {
        final pid = plantas[pn];
        if (pid != null) {
          await db.into(db.plantaPatologias).insert(
              PlantaPatologiasCompanion.insert(
                  plantaId: pid,
                  patologiaId: id,
                  prevalencia: const Value('media')));
        }
      }
      // 2) Mapa patología ↔ especie botánica (Fase 3h) — permite
      //    auto-poblar futuras variedades que el usuario cree con la
      //    misma especie.
      for (final esp in especiesAfectadas) {
        await db.into(db.patologiasEspecies).insert(
              PatologiasEspeciesCompanion.insert(
                  patologiaId: id,
                  especie: esp,
                  prevalencia: const Value('media')),
              mode: InsertMode.insertOrIgnore,
            );
      }
      return id;
    }
    await pat('Roya', 'Puccinia spp.', 'hongo',
        ['Maíz ICA V-305'],
        especiesAfectadas: ['Zea mays L.', 'Zea mays']);
    await pat('Antracnosis', 'Colletotrichum spp.', 'hongo',
        ['Frijol Cargamanto', 'Papaya Melona', 'Pimentón California Wonder'],
        especiesAfectadas: [
          'Phaseolus vulgaris',
          'Carica papaya',
          'Capsicum annuum',
          'Solanum lycopersicum',
        ]);
    await pat('Tizón tardío', 'Phytophthora infestans', 'hongo',
        ['Pimentón California Wonder'],
        especiesAfectadas: [
          'Capsicum annuum',
          'Solanum lycopersicum',
          'Solanum tuberosum',
        ]);
    await pat('Virus mancha anillada', 'Papaya ringspot virus', 'virus',
        ['Papaya Melona'],
        especiesAfectadas: ['Carica papaya']);
    await pat('Mosca blanca', 'Bemisia tabaci', 'plaga',
        ['Pimentón California Wonder', 'Frijol Cargamanto'],
        especiesAfectadas: [
          'Capsicum annuum',
          'Phaseolus vulgaris',
          'Solanum lycopersicum',
          'Cucurbita pepo',
        ]);
  }

  /// Fase 3h (v10): puebla `patologias_especies` para instalaciones ya
  /// existentes, donde `Patologias` ya tiene filas pero `PatologiasEspecies`
  /// está vacía tras la migración. Idempotente: usa insertOrIgnore.
  Future<void> seedPatologiasEspeciesV10() async {
    final rows = <(String, String)>[
      // (nombre_comun_patologia, especie_afectada)
      ('Roya', 'Zea mays L.'),
      ('Roya', 'Zea mays'),
      ('Antracnosis', 'Phaseolus vulgaris'),
      ('Antracnosis', 'Carica papaya'),
      ('Antracnosis', 'Capsicum annuum'),
      ('Antracnosis', 'Solanum lycopersicum'),
      ('Tizón tardío', 'Capsicum annuum'),
      ('Tizón tardío', 'Solanum lycopersicum'),
      ('Tizón tardío', 'Solanum tuberosum'),
      ('Virus mancha anillada', 'Carica papaya'),
      ('Mosca blanca', 'Capsicum annuum'),
      ('Mosca blanca', 'Phaseolus vulgaris'),
      ('Mosca blanca', 'Solanum lycopersicum'),
      ('Mosca blanca', 'Cucurbita pepo'),
    ];
    for (final (nombre, especie) in rows) {
      final pat = await (db.select(db.patologias)
            ..where((p) => p.nombreComun.equals(nombre))
            ..limit(1))
          .getSingleOrNull();
      if (pat == null) continue;
      await db.into(db.patologiasEspecies).insert(
            PatologiasEspeciesCompanion.insert(
              patologiaId: pat.id,
              especie: especie,
              prevalencia: const Value('media'),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }
}
