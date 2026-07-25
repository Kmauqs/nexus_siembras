import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_shell.dart';
import '../../state/data_state.dart';

class PrediosAdminScreen extends ConsumerWidget {
  const PrediosAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(prediosProvider);
    final activeId = ref.watch(activePredioIdProvider);
    return AppShell(
      title: 'Administración de predios',
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: () => _openEditor(context, ref, null),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo predio'),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Sin predios registrados'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _PredioCard(
                        p: list[i],
                        isActive: list[i].id == activeId,
                        soyPropietario: ref.watch(
                            soyPropietarioPredioProvider(list[i].id)),
                        onOpen: () => context.go('/predios/${list[i].id}'),
                        onEdit: () => _openEditor(context, ref, list[i]),
                        onDelete: () =>
                            _confirmDelete(context, ref, list[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(
      BuildContext context, WidgetRef ref, dynamic existing) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PredioEditor(existing: existing),
    );
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              existing == null ? 'Predio creado' : 'Predio actualizado')));
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, dynamic p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar predio'),
        content: Text(
            '¿Enviar "${p.nombre}" a la papelera? Los cultivos y lotes asociados se conservan pero quedarán huérfanos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(dataMutationsProvider).deletePredio(p.id as int);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Predio enviado a papelera')));
      }
    }
  }
}

class _PredioCard extends StatelessWidget {
  const _PredioCard({
    required this.p,
    required this.isActive,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    this.soyPropietario = true,
  });
  final dynamic p; // drift.Predio
  final bool isActive;
  final VoidCallback onOpen, onEdit, onDelete;
  final bool soyPropietario;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.landscape,
                  color: isActive ? Colors.green : Colors.grey.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(p.nombre as String,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16))),
                      if (isActive)
                        const Chip(
                            label: Text('Activo',
                                style: TextStyle(fontSize: 10)),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact),
                    ]),
                    if (p.propietario != null)
                      Text('Propietario: ${p.propietario}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).hintColor)),
                    if (p.lat != null && p.lng != null)
                      Text(
                          '📍 ${(p.lat as double).toStringAsFixed(4)}, '
                          '${(p.lng as double).toStringAsFixed(4)}'
                          '${p.altM != null ? " · ${(p.altM as double).toStringAsFixed(0)} msnm" : ""}',
                          style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              if (soyPropietario)
                IconButton(
                    icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
              if (soyPropietario)
                IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: onDelete)
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade200)),
                  child: const Text('Compartido',
                      style: TextStyle(fontSize: 9, color: Colors.blue)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PredioEditor extends ConsumerStatefulWidget {
  const _PredioEditor({this.existing});
  final dynamic existing;

  @override
  ConsumerState<_PredioEditor> createState() => _PredioEditorState();
}

class _PredioEditorState extends ConsumerState<_PredioEditor> {
  late final TextEditingController _nombre;
  late final TextEditingController _propietario;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late final TextEditingController _alt;
  late final TextEditingController _notas;
  int? _paisId, _regionId, _municipioId;
  bool _saving = false;
  bool _obtainingGnss = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nombre = TextEditingController(text: e?.nombre ?? '');
    _propietario = TextEditingController(text: e?.propietario ?? '');
    _lat = TextEditingController(
        text: e?.lat != null ? (e.lat as double).toStringAsFixed(6) : '');
    _lng = TextEditingController(
        text: e?.lng != null ? (e.lng as double).toStringAsFixed(6) : '');
    _alt = TextEditingController(
        text: e?.altM != null ? (e.altM as double).toStringAsFixed(0) : '');
    _notas = TextEditingController(text: e?.notas ?? '');
    _paisId = e?.paisId as int?;
    _regionId = e?.regionId as int?;
    _municipioId = e?.municipioId as int?;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _propietario.dispose();
    _lat.dispose();
    _lng.dispose();
    _alt.dispose();
    _notas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paises = ref.watch(paisesProvider).maybeWhen(
        data: (l) => l, orElse: () => const []);
    final regiones = _paisId == null
        ? const []
        : ref.watch(regionesProvider(_paisId!)).maybeWhen(
            data: (l) => l, orElse: () => const []);
    final munis = _regionId == null
        ? const []
        : ref.watch(municipiosProvider(_regionId!)).maybeWhen(
            data: (l) => l, orElse: () => const []);
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEdit ? 'Editar predio' : 'Nuevo predio',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _nombre,
              decoration: const InputDecoration(
                  labelText: 'Nombre del predio *',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _propietario,
              decoration: const InputDecoration(
                  labelText: 'Propietario', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _paisId,
              items: paises
                  .map<DropdownMenuItem<int>>((p) => DropdownMenuItem(
                        value: p.id as int,
                        child: Text(p.nombre as String),
                      ))
                  .toList(),
              onChanged: (v) => setState(() {
                _paisId = v;
                _regionId = null;
                _municipioId = null;
              }),
              decoration: const InputDecoration(
                  labelText: 'País', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _regionId,
              items: regiones
                  .map<DropdownMenuItem<int>>((r) => DropdownMenuItem(
                        value: r.id as int,
                        child: Text(r.nombre as String),
                      ))
                  .toList(),
              onChanged: _paisId == null
                  ? null
                  : (v) => setState(() {
                        _regionId = v;
                        _municipioId = null;
                      }),
              decoration: const InputDecoration(
                  labelText: 'Región / departamento',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _municipioId,
              items: munis
                  .map<DropdownMenuItem<int>>((m) => DropdownMenuItem(
                        value: m.id as int,
                        child: Text(m.nombre as String),
                      ))
                  .toList(),
              onChanged: _regionId == null
                  ? null
                  : (v) => setState(() => _municipioId = v),
              decoration: const InputDecoration(
                  labelText: 'Municipio', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _lat,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: const InputDecoration(
                      labelText: 'Latitud', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _lng,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: const InputDecoration(
                      labelText: 'Longitud', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _alt,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Altitud (msnm)',
                      border: OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _obtainingGnss ? null : _obtenerGnss,
                icon: _obtainingGnss
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 18),
                label: Text(_obtainingGnss ? 'Obteniendo…' : 'Usar GNSS'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _lat.clear();
                  _lng.clear();
                  _alt.clear();
                }),
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Limpiar'),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _notas,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Notas', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancelar')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(isEdit ? 'Guardar' : 'Crear'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  double? _d(TextEditingController c) {
    final v = c.text.trim();
    if (v.isEmpty) return null;
    return double.tryParse(v.replaceAll(',', '.'));
  }

  /// Captura las coordenadas actuales del dispositivo (GPS/GNSS).
  /// Rellena los campos lat, lng y altitud si están disponibles.
  Future<void> _obtenerGnss() async {
    setState(() => _obtainingGnss = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Activa el servicio de ubicación del sistema')));
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Permiso de ubicación denegado')));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      if (!mounted) return;
      setState(() {
        _lat.text = pos.latitude.toStringAsFixed(6);
        _lng.text = pos.longitude.toStringAsFixed(6);
        if (!pos.altitude.isNaN) {
          _alt.text = pos.altitude.toStringAsFixed(0);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Coordenadas capturadas '
              '(±${pos.accuracy.toStringAsFixed(0)} m'
              '${!pos.altitude.isNaN ? " · alt ${pos.altitude.toStringAsFixed(0)} msnm" : ""})')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'No se pudo obtener GNSS: $e — puedes ingresar manualmente')));
    } finally {
      if (mounted) setState(() => _obtainingGnss = false);
    }
  }

  String? _s(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    if (_nombre.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El nombre es obligatorio')));
      return;
    }
    setState(() => _saving = true);
    try {
      final mut = ref.read(dataMutationsProvider);
      if (widget.existing == null) {
        await mut.addPredio(
          nombre: _nombre.text.trim(),
          propietario: _s(_propietario),
          paisId: _paisId,
          regionId: _regionId,
          municipioId: _municipioId,
          lat: _d(_lat),
          lng: _d(_lng),
          altM: _d(_alt),
          notas: _s(_notas),
        );
      } else {
        await mut.updatePredio(
          id: widget.existing.id as int,
          nombre: _nombre.text.trim(),
          propietario: _s(_propietario),
          paisId: _paisId,
          regionId: _regionId,
          municipioId: _municipioId,
          lat: _d(_lat),
          lng: _d(_lng),
          altM: _d(_alt),
          notas: _s(_notas),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
