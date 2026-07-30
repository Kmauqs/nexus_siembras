import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/data_state.dart';

/// Muestra el email del usuario Supabase asociado a un UUID (`created_by_user_id`).
class AutorLabel extends ConsumerWidget {
  const AutorLabel({super.key, required this.userId, this.prefix = '👤 '});

  final String userId;
  final String prefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emailAsync = ref.watch(emailPorUserIdProvider(userId));
    final texto = emailAsync.maybeWhen(
      data: (email) => email ?? _resumen(userId),
      orElse: () => _resumen(userId),
    );
    return Text(
      '$prefix$texto',
      style: TextStyle(
        fontSize: 11,
        color: Theme.of(context).hintColor,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  String _resumen(String uuid) =>
      uuid.length < 12 ? uuid : '${uuid.substring(0, 8)}…';
}
