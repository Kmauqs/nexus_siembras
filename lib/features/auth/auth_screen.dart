// Pantalla de autenticación Supabase: login y registro con email + password.
//
// Modo dual:
//   - Login: usuario ya registrado ingresa
//   - Registro: crea cuenta nueva (dispara email de confirmación si está
//     habilitado en Supabase → Auth → Email templates)
//
// Botón "Continuar sin cuenta" permite seguir usando la app 100% local,
// preservando el escenario del pequeño productor sin internet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/widgets/app_shell.dart';
import '../../services/sync_service.dart';
import '../../state/app_state.dart';
import '../../state/auth_state.dart';
import '../../state/data_state.dart';
import 'package:intl/intl.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _esRegistro = false;
  bool _mostrarPassword = false;
  bool _cargando = false;
  String? _mensaje;
  bool _mensajeExito = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _mensaje = null;
    });
    try {
      final client = Supabase.instance.client;
      if (_esRegistro) {
        final res = await client.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (res.user != null && res.session == null) {
          // Cuenta creada pero requiere verificación por email
          setState(() {
            _mensaje =
                'Cuenta creada. Revisa tu correo para confirmar antes de iniciar sesión.';
            _mensajeExito = true;
            _esRegistro = false;
          });
        }
      } else {
        await client.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        // La redirección la maneja el listener de authSessionProvider.
        if (mounted) context.go('/');
      }
    } on AuthException catch (e) {
      setState(() {
        _mensaje = _traducirError(e.message);
        _mensajeExito = false;
      });
    } catch (e) {
      setState(() {
        _mensaje = 'Error inesperado: $e';
        _mensajeExito = false;
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_email.text.trim().isEmpty) {
      setState(() {
        _mensaje = 'Ingresa tu email primero.';
        _mensajeExito = false;
      });
      return;
    }
    setState(() => _cargando = true);
    try {
      await Supabase.instance.client.auth
          .resetPasswordForEmail(_email.text.trim());
      setState(() {
        _mensaje =
            'Te enviamos un correo con un enlace para restablecer tu contraseña.';
        _mensajeExito = true;
      });
    } on AuthException catch (e) {
      setState(() {
        _mensaje = _traducirError(e.message);
        _mensajeExito = false;
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _traducirError(String mensaje) {
    final m = mensaje.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (m.contains('user already registered')) {
      return 'Ya existe una cuenta con ese correo. Inicia sesión.';
    }
    if (m.contains('email not confirmed')) {
      return 'Confirma tu correo antes de iniciar sesión.';
    }
    if (m.contains('password should be')) {
      return 'La contraseña es demasiado corta (mínimo 8 caracteres).';
    }
    if (m.contains('rate limit')) {
      return 'Demasiados intentos. Espera un momento e inténtalo de nuevo.';
    }
    return mensaje;
  }

  @override
  Widget build(BuildContext context) {
    final supabaseListo = ref.watch(supabaseInitProvider);
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);

    // Si ya está logueado, mostrar el perfil en vez del formulario.
    if (user != null) {
      return _ProfileView(user: user);
    }

    return AppShell(
      title: _esRegistro ? 'Crear cuenta' : 'Iniciar sesión',
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                Icon(Icons.eco, size: 60, color: theme.colorScheme.primary),
                const SizedBox(height: 8),
                Text('NEXUS Siembras',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Sincroniza tu predio entre dispositivos',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
                const SizedBox(height: 24),

                if (!supabaseListo)
                  Card(
                    color: Colors.orange.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        const Icon(Icons.warning_amber, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                'La sincronización en la nube no está configurada. '
                                'Completa .env con SUPABASE_URL y SUPABASE_ANON_KEY '
                                'y reinicia la app.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade900))),
                      ]),
                    ),
                  ),
                if (!supabaseListo) const SizedBox(height: 16),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Correo electrónico',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return 'Ingresa tu email';
                              if (!t.contains('@') || !t.contains('.')) {
                                return 'Email no válido';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: !_mostrarPassword,
                            autofillHints: _esRegistro
                                ? const [AutofillHints.newPassword]
                                : const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_mostrarPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: () => setState(
                                    () => _mostrarPassword = !_mostrarPassword),
                              ),
                              border: const OutlineInputBorder(),
                              helperText: _esRegistro
                                  ? 'Mínimo 6 caracteres'
                                  : null,
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Ingresa una contraseña';
                              }
                              // Auditoría S7: mínimo 8. Configurar también
                              // en Supabase (Auth → Settings): longitud
                              // mínima 8 + Leaked password protection.
                              if (_esRegistro && v.length < 8) {
                                return 'Mínimo 8 caracteres';
                              }
                              return null;
                            },
                          ),
                          if (_mensaje != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _mensajeExito
                                    ? Colors.green.shade50
                                    : Colors.red.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: _mensajeExito
                                        ? Colors.green
                                        : Colors.red,
                                    width: 0.5),
                              ),
                              child: Row(children: [
                                Icon(
                                    _mensajeExito
                                        ? Icons.check_circle
                                        : Icons.error_outline,
                                    color: _mensajeExito
                                        ? Colors.green
                                        : Colors.red,
                                    size: 18),
                                const SizedBox(width: 6),
                                Expanded(
                                    child: Text(_mensaje!,
                                        style: const TextStyle(fontSize: 13))),
                              ]),
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: (_cargando || !supabaseListo)
                                ? null
                                : _submit,
                            icon: _cargando
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : Icon(_esRegistro
                                    ? Icons.person_add
                                    : Icons.login),
                            label: Text(_esRegistro
                                ? 'Crear cuenta'
                                : 'Iniciar sesión'),
                          ),
                          const SizedBox(height: 4),
                          if (!_esRegistro)
                            TextButton(
                              onPressed:
                                  (_cargando || !supabaseListo) ? null : _resetPassword,
                              child: const Text('¿Olvidaste tu contraseña?'),
                            ),
                          const Divider(),
                          TextButton(
                            onPressed: _cargando
                                ? null
                                : () => setState(() {
                                      _esRegistro = !_esRegistro;
                                      _mensaje = null;
                                    }),
                            child: Text(_esRegistro
                                ? 'Ya tengo cuenta · Iniciar sesión'
                                : 'No tengo cuenta · Crear una'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.offline_bolt),
                  label: const Text('Continuar sin cuenta (modo local)'),
                ),
                const SizedBox(height: 8),
                Text(
                    'En modo local tus datos se guardan solo en este dispositivo.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vista de perfil mostrada cuando ya hay sesión activa.
class _ProfileView extends ConsumerStatefulWidget {
  const _ProfileView({required this.user});
  final User user;

  @override
  ConsumerState<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<_ProfileView> {
  bool _cerrando = false;
  bool _sincronizando = false;
  SyncResult? _ultimoSync;
  DateTime? _ultimoSyncAt;

  Future<void> _sincronizar() async {
    setState(() => _sincronizando = true);
    try {
      final res = await ref.read(syncServiceProvider).sincronizar();
      if (!mounted) return;
      setState(() {
        _ultimoSync = res;
        _ultimoSyncAt = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.exito
            ? '✓ Sincronizado: ${res.pushed} subidos · ${res.pulled} '
                'actualizados desde la nube'
                '${res.errores > 0 ? ' · ⚠ ${res.errores} fila(s) con error (ver logs en Reportes)' : ''}'
            : '⚠ Error: ${res.error}'),
        backgroundColor: res.exito ? Colors.green : Colors.red,
        duration: const Duration(seconds: 5),
      ));
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  /// Fuerza un ciclo completo de push+pull ignorando los timestamps
  /// incrementales. Sube todo lo pendiente (aunque el sync incremental
  /// no lo detecte) y baja todo lo remoto. Útil cuando un colaborador
  /// recupera acceso a un predio y faltan actividades históricas, o si
  /// un bug antiguo dejó registros locales sin propagar.
  /// Preserva los mappings — no duplica nada en la nube.
  Future<void> _resincronizarTodo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resincronizar todo'),
        content: const Text(
            'Vuelve a sincronizar TODO ignorando los timestamps '
            'incrementales:\n\n'
            '• Sube todas las filas locales, incluso las que el sync '
            'incremental cree "ya subidas".\n'
            '• Baja todas las filas remotas visibles.\n\n'
            'Útil cuando falta información histórica en un dispositivo '
            '(p. ej. tras recuperar acceso a un predio compartido) o '
            'después de una actualización de la app.\n\n'
            'No borra datos ni duplica nada en la nube. Puede tardar '
            'varios segundos.\n\n'
            '¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Resincronizar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _sincronizando = true);
    try {
      final res =
          await ref.read(syncServiceProvider).sincronizarDesdeCero();
      if (!mounted) return;
      setState(() {
        _ultimoSync = res;
        _ultimoSyncAt = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.exito
            ? '✓ Resincronizado: ${res.pushed} subidos · ${res.pulled} bajados'
            : '⚠ Error: ${res.error}'),
        backgroundColor: res.exito ? Colors.green : Colors.red,
        duration: const Duration(seconds: 5),
      ));
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  /// Reset total: cierra sesión y BORRA TODOS LOS DATOS LOCALES.
  /// La app arranca desde cero (onboarding). Útil cuando el estado local
  /// quedó inconsistente y se quiere re-descargar todo desde el server.
  Future<void> _resetTotal() async {
    final ok1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset total del dispositivo'),
        content: const Text(
            'Esta acción:\n\n'
            '1. Cierra tu sesión en la nube.\n'
            '2. Borra TODOS los datos locales (predios, cultivos, '
            'inventario, mappings de sync, config).\n'
            '3. La app vuelve al onboarding inicial.\n\n'
            'Los datos en la nube NO se tocan. Al volver a iniciar sesión '
            'podrás re-descargar todo desde el servidor.\n\n'
            '¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Sí, reset total')),
        ],
      ),
    );
    if (ok1 != true) return;
    final ok2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Estás seguro?'),
        content: const Text(
            'Última confirmación. Todos los datos locales serán eliminados '
            'y no podrás recuperarlos desde este dispositivo (aunque sigan '
            'en la nube si los sincronizaste antes).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('BORRAR TODO')),
        ],
      ),
    );
    if (ok2 != true) return;

    setState(() => _cerrando = true);
    // Capturar el db ref ANTES de signOut — si el widget se desmonta por
    // el cambio de sesión, este ref sigue vivo para completar el delete.
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // 1. Borrar TODO en la BD Drift PRIMERO (antes de signOut porque
      //    signOut() desmonta este widget y corta la ejecución asincrónica).
      await db.transaction(() async {
        await db.delete(db.tareasCompletadas).go();
        await db.delete(db.eventosCultivo).go();
        await db.delete(db.cosechasRegistradas).go();
        await db.delete(db.actividadesCustom).go();
        await db.delete(db.cultivoPatologias).go();
        await db.delete(db.cultivos).go();
        await db.delete(db.compras).go();
        await db.delete(db.inventarios).go();
        await db.delete(db.analisisSuelo).go();
        await db.delete(db.condicionesPredio).go();
        await db.delete(db.lotes).go();
        await db.delete(db.predioColaboradores).go();
        await db.delete(db.patologiasReportadas).go();
        await db.delete(db.predios).go();
        await db.delete(db.proveedores).go();
        await db.delete(db.syncMappings).go();
        await db.delete(db.syncTables).go();
        await db.delete(db.configs).go();
      });
      // 2. Mostrar snackbar ANTES del signOut (por si el widget se desmonta)
      messenger.showSnackBar(const SnackBar(
        content: Text(
            '✓ Datos locales borrados. Cerrando sesión…\n'
            'Reinicia la app para volver al onboarding.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 10),
      ));
      // 3. Sign out — este paso puede desmontar el widget, por eso va al final.
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _cerrando = false);
    }
  }

  Future<void> _cerrarSesion() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
            'Tus datos locales NO se borran. Podrás seguir usando la app '
            'en modo local hasta que inicies sesión de nuevo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _cerrando = true);
    try {
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sesión cerrada')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _cerrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = widget.user;
    final creado = u.createdAt;
    final creadoFmt = _fmtIsoDate(creado);
    return AppShell(
      title: 'Cuenta',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: theme.colorScheme.primary,
              child: Text(
                  (u.email?.substring(0, 1) ?? '?').toUpperCase(),
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          Center(
              child: Text(u.email ?? '(sin correo)',
                  style: theme.textTheme.titleMedium)),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Datos de la cuenta',
                      style: theme.textTheme.titleMedium),
                  const Divider(),
                  _row('Correo', u.email ?? '—'),
                  _row('ID', u.id),
                  _row('Creada', creadoFmt),
                  if (u.lastSignInAt != null)
                    _row('Último acceso', _fmtIsoDate(u.lastSignInAt!)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.sync, color: Colors.blue),
                    const SizedBox(width: 6),
                    Text('Sincronización',
                        style: theme.textTheme.titleMedium),
                  ]),
                  const Divider(),
                  if (_ultimoSyncAt != null) ...[
                    _row('Última sync',
                        DateFormat('yyyy-MM-dd HH:mm:ss')
                            .format(_ultimoSyncAt!.toLocal())),
                    if (_ultimoSync != null && _ultimoSync!.exito) ...[
                      _row('Subidos', '${_ultimoSync!.pushed} registros'),
                      _row('Bajados', '${_ultimoSync!.pulled} registros'),
                      _row('Duración',
                          '${_ultimoSync!.duration.inMilliseconds} ms'),
                    ],
                    if (_ultimoSync?.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Error: ${_ultimoSync!.error}',
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12)),
                      ),
                  ] else
                    const Text(
                        'Sube tus cambios locales a la nube y trae los '
                        'cambios remotos al dispositivo.',
                        style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.icon(
                      onPressed: _sincronizando ? null : _sincronizar,
                      icon: _sincronizando
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.cloud_sync, size: 18),
                      label: Text(_sincronizando
                          ? 'Sincronizando…'
                          : 'Sincronizar ahora'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _sincronizando ? null : _resincronizarTodo,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Resincronizar todo'),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                      'Estrategia: last-write-wins por updated_at. '
                      'Tabla predios/proveedores/lotes/cultivos/inventario/'
                      'compras/análisis/eventos/tareas. '
                      '"Resincronizar todo" ignora los timestamps '
                      'incrementales para recuperar registros históricos '
                      'faltantes (p. ej. tras recuperar acceso a un predio).',
                      style: TextStyle(
                          fontSize: 11, color: theme.hintColor)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: _cerrando ? null : _cerrarSesion,
            icon: _cerrando
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.logout),
            label: Text(_cerrando ? 'Cerrando…' : 'Cerrar sesión'),
          ),
          const SizedBox(height: 20),
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.red, size: 20),
                    const SizedBox(width: 6),
                    Text('Zona de peligro',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: Colors.red)),
                  ]),
                  const SizedBox(height: 6),
                  const Text(
                      'Reset total: borra todos los datos locales del '
                      'dispositivo (predios, cultivos, inventario, sync). '
                      'Los datos en la nube no se tocan. Útil cuando el '
                      'estado local quedó inconsistente.',
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style:
                        FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _cerrando ? null : _resetTotal,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Cerrar sesión y borrar datos locales'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 110,
                child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(
                child: Text(v, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  String _fmtIsoDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return DateFormat('yyyy-MM-dd HH:mm').format(d);
    } catch (_) {
      return iso;
    }
  }
}
