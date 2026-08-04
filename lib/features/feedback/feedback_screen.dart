// NEXUS Siembras — Micro-encuesta de feedback (Revisión C2-9, 2026-08-03).
//
// Pensada para el tester en campo: 3 toques bastan (estrellas → enviar).
// Funciona SIN conexión: todo se guarda en la cola local y se sube solo
// cuando hay red y sesión.
//
// Accesos: menú lateral ("Enviar comentarios"), y `mostrarMicroEncuesta`
// como hoja modal desde cualquier pantalla (p. ej. al terminar el
// asistente o tras generar un reporte).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_shell.dart';
import '../../data/database/database.dart';
import '../../state/data_state.dart';

/// Aspectos sugeridos por tipo de encuesta (chips de selección múltiple).
const _aspectos = <String, List<String>>{
  'general': [
    'Fácil de usar',
    'Rápida',
    'Me faltó una función',
    'Encontré un error',
    'Textos confusos',
    'Se ve bien',
  ],
  'wizard': [
    'Los pasos son claros',
    'Me perdí en algún paso',
    'Faltó explicación',
    'Demasiados pasos',
  ],
  'reporte': [
    'El PDF se ve bien',
    'Faltan datos',
    'No pude compartirlo',
    'Muy útil',
  ],
};

class FeedbackScreen extends ConsumerWidget {
  const FeedbackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(
      title: 'Enviar comentarios',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _FormularioEncuesta(tipo: 'general'),
          SizedBox(height: 12),
          _HistorialCard(),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Abre la micro-encuesta como hoja modal (para usarla al final de un
/// flujo concreto: asistente, reporte, etc.).
Future<void> mostrarMicroEncuesta(
  BuildContext context, {
  String tipo = 'general',
  String? titulo,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: _FormularioEncuesta(tipo: tipo, tituloOverride: titulo),
      ),
    ),
  );
}

class _FormularioEncuesta extends ConsumerStatefulWidget {
  const _FormularioEncuesta({required this.tipo, this.tituloOverride});
  final String tipo;
  final String? tituloOverride;

  @override
  ConsumerState<_FormularioEncuesta> createState() =>
      _FormularioEncuestaState();
}

class _FormularioEncuestaState extends ConsumerState<_FormularioEncuesta> {
  int? _calificacion;
  final Set<String> _seleccionados = {};
  final _comentario = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_calificacion == null &&
        _seleccionados.isEmpty &&
        _comentario.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Escribe un comentario o elige una calificación')));
      return;
    }
    setState(() => _enviando = true);
    final srv = ref.read(feedbackServiceProvider);
    try {
      await srv.guardar(
        tipo: widget.tipo,
        calificacion: _calificacion,
        respuestas: {'aspectos': _seleccionados.toList()},
        comentario: _comentario.text,
      );
      ref.invalidate(feedbackPendientesProvider);
      if (!mounted) return;
      // Cierra si está en hoja modal.
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            '¡Gracias! Tu comentario se guardó y se enviará automáticamente '
            'cuando haya conexión.'),
        duration: Duration(seconds: 5),
      ));
      setState(() {
        _calificacion = null;
        _seleccionados.clear();
        _comentario.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = _aspectos[widget.tipo] ?? _aspectos['general']!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.rate_review_outlined, color: Colors.green),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    widget.tituloOverride ?? '¿Cómo te fue con la app?',
                    style: theme.textTheme.titleMedium),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
                'Tu respuesta ayuda a mejorar NEXUS Siembras. Funciona sin '
                'conexión: se envía sola cuando vuelvas a tener internet.',
                style: TextStyle(fontSize: 12, color: theme.hintColor)),
            const SizedBox(height: 12),
            // Estrellas
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final valor = i + 1;
                  final activa =
                      _calificacion != null && valor <= _calificacion!;
                  return IconButton(
                    tooltip: '$valor de 5',
                    iconSize: 34,
                    icon: Icon(
                      activa ? Icons.star : Icons.star_border,
                      color: activa ? Colors.amber.shade700 : Colors.grey,
                    ),
                    onPressed: () =>
                        setState(() => _calificacion = valor),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: chips
                  .map((a) => FilterChip(
                        label: Text(a,
                            style: const TextStyle(fontSize: 12)),
                        selected: _seleccionados.contains(a),
                        onSelected: (sel) => setState(() {
                          if (sel) {
                            _seleccionados.add(a);
                          } else {
                            _seleccionados.remove(a);
                          }
                        }),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _comentario,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Comentario (opcional)',
                hintText: 'Cuéntanos qué funcionó bien o qué falló…',
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _enviando ? null : _enviar,
                icon: _enviando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, size: 18),
                label: const Text('Enviar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Historial local con estado de envío y reintento manual.
class _HistorialCard extends ConsumerStatefulWidget {
  const _HistorialCard();

  @override
  ConsumerState<_HistorialCard> createState() => _HistorialCardState();
}

class _HistorialCardState extends ConsumerState<_HistorialCard> {
  late Future<List<FeedbackEncuesta>> _futuro;
  bool _reintentando = false;

  @override
  void initState() {
    super.initState();
    _futuro = ref.read(feedbackServiceProvider).historial();
    // Al abrir la pantalla, intenta subir lo que quedó pendiente.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final n =
          await ref.read(feedbackServiceProvider).enviarPendientes();
      if (n > 0 && mounted) _refrescar();
    });
  }

  void _refrescar() {
    ref.invalidate(feedbackPendientesProvider);
    setState(() {
      _futuro = ref.read(feedbackServiceProvider).historial();
    });
  }

  Future<void> _reintentar() async {
    setState(() => _reintentando = true);
    final n = await ref
        .read(feedbackServiceProvider)
        .enviarPendientes(forzar: true);
    if (!mounted) return;
    setState(() => _reintentando = false);
    _refrescar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n > 0
            ? '$n comentario(s) enviado(s)'
            : 'Sin conexión o sin sesión: quedan en espera')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.history, color: Colors.blueGrey),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Mis comentarios',
                    style: theme.textTheme.titleMedium),
              ),
              IconButton(
                tooltip: 'Reintentar envío',
                icon: _reintentando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined, size: 20),
                onPressed: _reintentando ? null : _reintentar,
              ),
            ]),
            FutureBuilder<List<FeedbackEncuesta>>(
              future: _futuro,
              builder: (_, snap) {
                final items = snap.data ?? const <FeedbackEncuesta>[];
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Aún no has enviado comentarios.',
                        style: TextStyle(
                            fontSize: 12, color: theme.hintColor)),
                  );
                }
                return Column(
                  children: items.map((f) {
                    final enviada = f.enviadaAt != null;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          enviada
                              ? Icons.cloud_done
                              : Icons.schedule_outlined,
                          size: 20,
                          color: enviada ? Colors.green : Colors.orange),
                      title: Text(
                        f.comentario?.isNotEmpty == true
                            ? f.comentario!
                            : '(${f.calificacion ?? '—'} estrellas)',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${f.createdAt.toString().substring(0, 16)} · '
                        '${enviada ? 'enviado' : 'pendiente de envío'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
