// NEXUS Siembras — Asistente paso a paso (2026-07-20).
//
// Guía la configuración inicial en 10 pasos, en orden:
//   1. Predio (obligatorio)   2. Lote (obligatorio)
//   3. Condiciones (opcional) 4. Análisis de suelo (opcional)
//   5. Proveedores (oblig. si no hay)  6. Plantas (oblig. si no hay)
//   7. Compra (opcional)      8. Inventario (oblig. si vacío)
//   9. Cultivos               10. Mapa (final)
//
// Diseño: el asistente NO duplica formularios — cada paso muestra el
// estado real (desde la BD) y navega con `push` a la pantalla existente;
// al volver, el estado se refresca solo (providers reactivos). El paso
// actual vive en `wizardStepProvider` (app_state), así que salir del
// asistente y volver no pierde el avance. Los pasos obligatorios bloquean
// "Siguiente" hasta cumplirse.
//
// Accesos: diálogo post-onboarding (Dashboard), botón en la barra
// superior (junto al ícono de inicio) y menú desplegable.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/navigation/app_nav.dart';
import '../../core/theme/themes.dart';
import '../../core/widgets/app_shell.dart';
import '../../state/app_state.dart';
import '../../state/data_state.dart';

const _totalPasos = 10;

class WizardScreen extends ConsumerWidget {
  const WizardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paso = ref.watch(wizardStepProvider).clamp(0, _totalPasos - 1);
    final def = _pasoDef(context, ref, paso);

    return AppShell(
      title: 'Asistente — Paso ${paso + 1} de $_totalPasos',
      child: Column(
        children: [
          LinearProgressIndicator(
            value: (paso + 1) / _totalPasos,
            minHeight: 6,
            color: AppThemes.colorOk,
            backgroundColor: Colors.grey.shade300,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(children: [
                  Expanded(
                    child: Text(def.titulo,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  _Badge(
                    texto: def.obligatorio ? 'Obligatorio' : 'Opcional',
                    color: def.obligatorio
                        ? Colors.orange.shade700
                        : Colors.blueGrey,
                  ),
                ]),
                const SizedBox(height: 6),
                Text(def.descripcion,
                    style: TextStyle(
                        fontSize: 13, color: Theme.of(context).hintColor)),
                const SizedBox(height: 16),
                ...def.contenido,
              ],
            ),
          ),
          // Barra de navegación del asistente (pasos Anterior/Siguiente)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (paso > 0)
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(wizardStepProvider.notifier).state =
                            paso - 1,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Anterior'),
                  )
                else
                  const SizedBox(width: 110),
                const Spacer(),
                if (!def.cumplido && def.obligatorio)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text('Completa este paso\npara continuar',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade800)),
                  ),
                if (paso < _totalPasos - 1)
                  FilledButton.icon(
                    onPressed: (def.cumplido || !def.obligatorio)
                        ? () => ref
                            .read(wizardStepProvider.notifier)
                            .state = paso + 1
                        : null,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: Text(def.cumplido || def.obligatorio
                        ? 'Siguiente'
                        : 'Omitir'),
                  )
                else
                  FilledButton.icon(
                    onPressed: () {
                      ref.read(wizardStepProvider.notifier).state = 0;
                      AppNav.open(context, '/map');
                    },
                    icon: const Icon(Icons.map, size: 18),
                    label: const Text('Finalizar en el mapa'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // Definición de pasos
  // ================================================================
  _PasoDef _pasoDef(BuildContext context, WidgetRef ref, int paso) {
    switch (paso) {
      case 0:
        return _pasoPredio(context, ref);
      case 1:
        return _pasoLote(context, ref);
      case 2:
        return _pasoCondiciones(context, ref);
      case 3:
        return _pasoAnalisis(context, ref);
      case 4:
        return _pasoProveedores(context, ref);
      case 5:
        return _pasoPlantas(context, ref);
      case 6:
        return _pasoCompra(context, ref);
      case 7:
        return _pasoInventario(context, ref);
      case 8:
        return _pasoCultivos(context, ref);
      default:
        return _pasoFinal(context, ref);
    }
  }

  _PasoDef _pasoPredio(BuildContext context, WidgetRef ref) {
    final prediosAsync = ref.watch(prediosProvider);
    final activo = ref.watch(activePredioIdProvider);
    final predios = prediosAsync.maybeWhen(
        data: (l) => l.where((p) => p.deletedAt == null).toList(),
        orElse: () => <dynamic>[]);
    return _PasoDef(
      titulo: '1. Predio de trabajo',
      descripcion:
          'Selecciona el predio activo o crea uno nuevo. Si iniciaste '
          'sesión y te compartieron predios, aparecerán tras sincronizar.',
      obligatorio: true,
      cumplido: predios.isNotEmpty,
      contenido: [
        if (predios.isEmpty)
          const _Vacio('Aún no hay predios registrados.')
        else
          ...predios.map((p) => Card(
                child: RadioListTile<int>(
                  value: p.id as int,
                  groupValue: activo,
                  title: Text(p.nombre as String),
                  subtitle: Text(p.id == activo
                      ? 'Predio activo'
                      : 'Tocar para activar'),
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(dataMutationsProvider).setPredioActivo(v);
                    }
                  },
                ),
              )),
        const SizedBox(height: 8),
        _AccionBtn(
          icono: Icons.add_home_work_outlined,
          texto: 'Crear / administrar predios',
          onTap: () => AppNav.open(context, '/predios'),
        ),
      ],
    );
  }

  _PasoDef _pasoLote(BuildContext context, WidgetRef ref) {
    final lotes = ref.watch(lotesActivosProvider).maybeWhen(
        data: (l) => l.where((x) => x.deletedAt == null).toList(),
        orElse: () => <dynamic>[]);
    final predioId = ref.watch(activePredioIdProvider);
    return _PasoDef(
      titulo: '2. Lotes del predio',
      descripcion:
          'Divide el predio activo en lotes de trabajo. Cada cultivo se '
          'asigna a un lote.',
      obligatorio: true,
      cumplido: lotes.isNotEmpty,
      contenido: [
        if (lotes.isEmpty)
          const _Vacio('El predio activo no tiene lotes.')
        else
          ...lotes.map((l) => ListTile(
                dense: true,
                leading: const Icon(Icons.crop_square, size: 18),
                title: Text(l.nombre as String),
              )),
        const SizedBox(height: 8),
        _AccionBtn(
          icono: Icons.add,
          texto: 'Crear lote',
          onTap: () => AppNav.open(context, '/predios/$predioId/lotes/new'),
        ),
      ],
    );
  }

  _PasoDef _pasoCondiciones(BuildContext context, WidgetRef ref) {
    final cond = ref
        .watch(condicionesPredioProvider)
        .maybeWhen(data: (c) => c, orElse: () => null);
    return _PasoDef(
      titulo: '3. Condiciones del predio',
      descripcion:
          'Altitud, precipitación, temperaturas y piso térmico. Alimentan '
          'las recomendaciones agronómicas por cultivo.',
      obligatorio: false,
      cumplido: cond != null,
      contenido: [
        _Estado(
            ok: cond != null,
            okTxt: 'Condiciones registradas ✓',
            noTxt: 'Sin registrar (puedes omitir este paso)'),
        const SizedBox(height: 8),
        _AccionBtn(
          icono: Icons.thermostat,
          texto: cond == null
              ? 'Registrar condiciones'
              : 'Ver / editar condiciones',
          onTap: () => AppNav.open(context, '/plot-conditions'),
        ),
      ],
    );
  }

  _PasoDef _pasoAnalisis(BuildContext context, WidgetRef ref) {
    final analisis = ref
        .watch(analisisSueloProvider)
        .maybeWhen(data: (l) => l, orElse: () => <dynamic>[]);
    return _PasoDef(
      titulo: '4. Análisis de suelo',
      descripcion:
          'Registra los análisis fisicoquímicos del laboratorio (puedes '
          'adjuntar el PDF). Se usan para la proyección de fertilización.',
      obligatorio: false,
      cumplido: analisis.isNotEmpty,
      contenido: [
        _Estado(
            ok: analisis.isNotEmpty,
            okTxt: '${analisis.length} análisis registrado(s) ✓',
            noTxt: 'Sin análisis (puedes omitir este paso)'),
        const SizedBox(height: 8),
        _AccionBtn(
          icono: Icons.science_outlined,
          texto: 'Agregar análisis de suelo',
          onTap: () => AppNav.open(context, '/soil-analysis/add'),
        ),
        _AccionBtn(
          icono: Icons.list_alt,
          texto: 'Ver análisis existentes',
          onTap: () => AppNav.open(context, '/soil-analysis'),
        ),
      ],
    );
  }

  _PasoDef _pasoProveedores(BuildContext context, WidgetRef ref) {
    final provs = ref.watch(proveedoresDriftProvider).maybeWhen(
        data: (l) => l.where((x) => x.deletedAt == null).toList(),
        orElse: () => <dynamic>[]);
    return _PasoDef(
      titulo: '5. Proveedores',
      descripcion:
          'Directorio de proveedores para asociarlos a las compras.',
      obligatorio: provs.isEmpty, // obligatorio solo si no existe ninguno
      cumplido: provs.isNotEmpty,
      contenido: [
        if (provs.isEmpty)
          const _Vacio('Sin proveedores — crea al menos uno.')
        else
          ...provs.take(6).map((pr) => ListTile(
                dense: true,
                leading: const Icon(Icons.storefront, size: 18),
                title: Text(pr.nombre as String),
              )),
        if (provs.length > 6)
          Text('… y ${provs.length - 6} más',
              style: TextStyle(color: Theme.of(context).hintColor)),
        const SizedBox(height: 8),
        _AccionBtn(
          icono: Icons.add_business_outlined,
          texto: 'Agregar / ver proveedores',
          onTap: () => AppNav.open(context, '/suppliers'),
        ),
      ],
    );
  }

  _PasoDef _pasoPlantas(BuildContext context, WidgetRef ref) {
    final plantas = ref.watch(plantasListadoProvider);
    final propias = ref.watch(plantasProvider);
    final comunitarias = plantas.length - propias.length;
    return _PasoDef(
      titulo: '6. Variedades de plantas',
      descripcion:
          'El catálogo trae variedades comunes precargadas. Puedes agregar '
          'las tuyas o sincronizar variedades compartidas por la comunidad.',
      obligatorio: plantas.isEmpty,
      cumplido: plantas.isNotEmpty,
      contenido: [
        _Estado(
            ok: plantas.isNotEmpty,
            okTxt: comunitarias > 0
                ? '${plantas.length} variedad(es) (${propias.length} propias + $comunitarias comunidad) ✓'
                : '${plantas.length} variedad(es) en el catálogo ✓',
            noTxt: 'Catálogo vacío — crea una variedad o sincroniza comunidad'),
        const SizedBox(height: 8),
        _AccionBtn(
          icono: Icons.grass,
          texto: 'Ver catálogo / nueva variedad',
          onTap: () => AppNav.open(context, '/plants'),
        ),
      ],
    );
  }

  _PasoDef _pasoCompra(BuildContext context, WidgetRef ref) {
    final permisos = ref.watch(permisosPredioActivoProvider);
    if (!permisos.puedeVerCompras) {
      return _PasoDef(
        titulo: '7. Primera compra',
        descripcion:
            'Las compras del predio solo están disponibles para usuarios '
            'con rol Propietario. Como colaborador Trabajador o Consultor '
            'puedes omitir este paso.',
        obligatorio: false,
        cumplido: true,
        contenido: const [
          _Estado(
            ok: true,
            okTxt: 'No aplica a tu rol en este predio',
            noTxt: '',
          ),
        ],
      );
    }
    final compras = ref.watch(comprasProvider);
    return _PasoDef(
      titulo: '7. Primera compra',
      descripcion:
          'Registra compras de insumos con su comprobante. Las compras de '
          'semilla, abono o pesticida cargan automáticamente el inventario.',
      obligatorio: false,
      cumplido: compras.isNotEmpty,
      contenido: [
        _Estado(
            ok: compras.isNotEmpty,
            okTxt: '${compras.length} compra(s) registrada(s) ✓',
            noTxt: 'Sin compras (puedes omitir este paso)'),
        const SizedBox(height: 8),
        _AccionBtn(
          icono: Icons.receipt_long,
          texto: 'Registrar / ver compras',
          onTap: () => AppNav.open(context, '/purchases'),
        ),
      ],
    );
  }

  _PasoDef _pasoInventario(BuildContext context, WidgetRef ref) {
    final inv = ref.watch(inventoryProvider);
    return _PasoDef(
      titulo: '8. Inventario de insumos',
      descripcion:
          'Insumos disponibles en bodega. Las tareas de campo descuentan '
          'de aquí lo que consumen.',
      obligatorio: inv.isEmpty, // obligatorio si está vacío
      cumplido: inv.isNotEmpty,
      contenido: [
        if (inv.isEmpty)
          const _Vacio('Inventario vacío — agrega al menos un insumo '
              '(o regístralo como compra en el paso anterior).')
        else
          ...inv.take(6).map((i) => ListTile(
                dense: true,
                leading: const Icon(Icons.inventory_2_outlined, size: 18),
                title: Text(i.desc),
                trailing: Text('${i.cantidad} ${i.unidad}'),
              )),
        if (inv.length > 6)
          Text('… y ${inv.length - 6} más',
              style: TextStyle(color: Theme.of(context).hintColor)),
        const SizedBox(height: 8),
        _AccionBtn(
          icono: Icons.inventory_2,
          texto: 'Agregar / ver inventario',
          onTap: () => AppNav.open(context, '/inventory'),
        ),
      ],
    );
  }

  _PasoDef _pasoCultivos(BuildContext context, WidgetRef ref) {
    final cultivos = ref.watch(cultivosActivosProvider);
    final plantas = ref.watch(plantasProvider);
    final plantasById = {for (final p in plantas) p.id: p};
    return _PasoDef(
      titulo: '9. Cultivos',
      descripcion:
          'Registra las siembras: variedad, lote, fecha y cantidad. El '
          'cronograma de eventos se genera automáticamente.',
      obligatorio: false,
      cumplido: cultivos.isNotEmpty,
      contenido: [
        if (cultivos.isEmpty)
          const _Vacio('Sin cultivos activos.')
        else
          ...cultivos.take(6).map((c) => ListTile(
                dense: true,
                leading: const Icon(Icons.eco, size: 18),
                title: Text(
                    '${plantasById[c.plantaId]?.nombre ?? '?'} · ${c.lote}'),
                subtitle: Text('Sembrado: ${c.sembrado}'),
              )),
        const SizedBox(height: 8),
        _AccionBtn(
          icono: Icons.add_circle_outline,
          texto: 'Agregar cultivo',
          onTap: () => AppNav.open(context, '/add'),
        ),
        _AccionBtn(
          icono: Icons.eco,
          texto: 'Ver cultivos',
          onTap: () => AppNav.open(context, '/crops'),
        ),
      ],
    );
  }

  _PasoDef _pasoFinal(BuildContext context, WidgetRef ref) {
    return _PasoDef(
      titulo: '10. ¡Listo!',
      descripcion:
          'Configuración inicial completa. El mapa muestra tus predios, '
          'lotes y cultivos georreferenciados; desde el Dashboard tienes '
          'alertas, cronograma y reportes.',
      obligatorio: false,
      cumplido: true,
      contenido: [
        Card(
          color: Colors.green.shade50,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(children: [
              Text('🌱', style: TextStyle(fontSize: 48)),
              SizedBox(height: 8),
              Text(
                  'Puedes volver a ejecutar este asistente cuando quieras '
                  'desde el menú o el botón de la barra superior.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13)),
            ]),
          ),
        ),
      ],
    );
  }
}

// ================================================================
// Widgets auxiliares
// ================================================================

class _PasoDef {
  const _PasoDef({
    required this.titulo,
    required this.descripcion,
    required this.obligatorio,
    required this.cumplido,
    required this.contenido,
  });
  final String titulo;
  final String descripcion;
  final bool obligatorio;
  final bool cumplido;
  final List<Widget> contenido;
}

class _Badge extends StatelessWidget {
  const _Badge({required this.texto, required this.color});
  final String texto;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(28),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 0.8),
        ),
        child: Text(texto,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      );
}

class _Vacio extends StatelessWidget {
  const _Vacio(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(Icons.info_outline, size: 18, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

class _Estado extends StatelessWidget {
  const _Estado({required this.ok, required this.okTxt, required this.noTxt});
  final bool ok;
  final String okTxt, noTxt;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18, color: ok ? Colors.green : Colors.grey),
        const SizedBox(width: 8),
        Expanded(
            child: Text(ok ? okTxt : noTxt,
                style: TextStyle(
                    fontSize: 13,
                    color: ok ? Colors.green.shade800 : Colors.grey))),
      ]);
}

class _AccionBtn extends StatelessWidget {
  const _AccionBtn(
      {required this.icono, required this.texto, required this.onTap});
  final IconData icono;
  final String texto;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icono, size: 18),
            label: Text(texto),
          ),
        ),
      );
}
