import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart' as drift;
import '../../state/data_state.dart';
import 'agrupacion_patologias.dart';

/// Abre el selector de grupo para una patología del catálogo y confirma el
/// movimiento con un snackbar. No hace nada si el usuario cancela o elige el
/// grupo en el que ya está.
Future<void> showReclasificarPatologiaDialog({
  required BuildContext context,
  required drift.Patologia patologia,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final mensaje = await showDialog<String>(
    context: context,
    builder: (_) => _DialogoReclasificar(patologia: patologia),
  );
  if (mensaje == null) return;
  messenger.showSnackBar(SnackBar(
    content: Text(mensaje),
    behavior: SnackBarBehavior.floating,
  ));
}

class _DialogoReclasificar extends ConsumerWidget {
  const _DialogoReclasificar({required this.patologia});
  final drift.Patologia patologia;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final actual = grupoEfectivo(patologia);
    final esManual = reclasificadaManualmente(patologia);
    final auto = grupoPorCodigo(grupoAutomatico(patologia));

    return AlertDialog(
      title: Text('Reclasificar «${patologia.nombreComun}»'),
      contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'El catálogo la clasifica automáticamente como '
                  '${auto.etiqueta.toLowerCase()} por su tipo taxonómico. '
                  'Elige otro grupo si no corresponde: la app respetará tu '
                  'elección aunque actualices el catálogo.',
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
              ),
              const SizedBox(height: 8),
              for (final g in gruposPatologias)
                ListTile(
                  leading: Icon(g.icono,
                      size: 20,
                      color: g.codigo == actual
                          ? theme.colorScheme.primary
                          : theme.iconTheme.color),
                  title: Text(g.titulo,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: g.codigo == actual
                              ? FontWeight.bold
                              : FontWeight.normal)),
                  trailing: g.codigo == actual
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                  onTap: () => _aplicar(context, ref,
                      tipoManual: g.codigo, destino: g, actual: actual),
                ),
              if (esManual) ...[
                const Divider(height: 8),
                ListTile(
                  leading: const Icon(Icons.restart_alt, size: 20),
                  title: const Text('Restaurar agrupación automática',
                      style: TextStyle(fontSize: 14)),
                  subtitle: Text('Volvería a ${auto.titulo}',
                      style: const TextStyle(fontSize: 12)),
                  onTap: () => _aplicar(context, ref,
                      tipoManual: null, destino: auto, actual: actual),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Future<void> _aplicar(
    BuildContext context,
    WidgetRef ref, {
    required String? tipoManual,
    required GrupoPatologia destino,
    required String actual,
  }) async {
    // Elegir el grupo donde ya está no debe marcarla como reclasificada.
    if (tipoManual != null && tipoManual == actual) {
      Navigator.pop(context);
      return;
    }
    await ref.read(dataMutationsProvider).reclasificarPatologia(
          patologiaId: patologia.id,
          tipoManual: tipoManual,
        );
    if (!context.mounted) return;
    Navigator.pop(
      context,
      tipoManual == null
          ? '«${patologia.nombreComun}» volvió a su grupo automático: '
              '${destino.etiqueta}'
          : '«${patologia.nombreComun}» se movió a ${destino.etiqueta}',
    );
  }
}
