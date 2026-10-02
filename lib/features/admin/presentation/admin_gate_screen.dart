import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../content.dart';
import '../../workspace/providers/tab_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/user_profile_provider.dart';
import 'admin_dashboard_screen.dart';

class AdminGateScreen extends ConsumerStatefulWidget {
  final Future<void> Function(Entry entry)? onPresent;
  final VoidCallback? onCustomizeChurch;

  const AdminGateScreen({super.key, this.onPresent, this.onCustomizeChurch});

  @override
  ConsumerState<AdminGateScreen> createState() => _AdminGateScreenState();
}

class _AdminGateScreenState extends ConsumerState<AdminGateScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isActivating = false;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _notice;
  bool _firebaseReady = false;

  @override
  void initState() {
    super.initState();
    _checkFirebase();
  }

  void _checkFirebase() {
    try {
      setState(() {
        _firebaseReady = Firebase.apps.isNotEmpty;
      });
    } catch (e) {
      setState(() {
        _firebaseReady = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    bool resetLoading = false;
    String? resetError;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.lock_reset, color: Colors.indigo),
                  SizedBox(width: 8),
                  Text('Recuperar / Crear Contraseña'),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ingresa tu correo institucional o pastoral. Te enviaremos un enlace oficial de Firebase para que definas o restablezcas tu contraseña.',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: resetEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    if (resetError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        resetError!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: resetLoading
                      ? null
                      : () async {
                          final email = resetEmailController.text.trim();
                          if (email.isEmpty) {
                            setDialogState(
                              () => resetError = 'Por favor ingresa un correo.',
                            );
                            return;
                          }
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(ctx);
                          setDialogState(() {
                            resetLoading = true;
                            resetError = null;
                          });

                          try {
                            await ref
                                .read(authServiceProvider)
                                .sendPasswordResetEmail(email);
                            if (mounted) {
                              nav.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  backgroundColor: Colors.green,
                                  duration: const Duration(seconds: 5),
                                  content: Text(
                                    'Enlace enviado a $email. Revisa tu bandeja de entrada o spam.',
                                  ),
                                ),
                              );
                            }
                          } on FirebaseAuthException catch (e) {
                            setDialogState(() {
                              resetLoading = false;
                              resetError =
                                  e.message ??
                                  'Error al enviar enlace (${e.code}).';
                            });
                          } catch (e) {
                            setDialogState(() {
                              resetLoading = false;
                              resetError = 'Error: $e';
                            });
                          }
                        },
                  child: resetLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Enviar Enlace'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Por favor completa todos los campos.');
      return;
    }

    if (_isActivating) {
      final confirmPassword = _confirmPasswordController.text;
      if (password.length < 6) {
        setState(
          () => _error = 'La contraseña debe tener al menos 6 caracteres.',
        );
        return;
      }
      if (password != confirmPassword) {
        setState(() => _error = 'Las contraseñas no coinciden.');
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });

    try {
      if (_isActivating) {
        await ref
            .read(authServiceProvider)
            .activateAccountWithEmail(email: email, password: password);
        if (mounted) {
          setState(() {
            _isActivating = false;
            _passwordController.clear();
            _confirmPasswordController.clear();
            _notice = 'Te enviamos un enlace de verificación. Ábrelo y después inicia sesión con la contraseña que acabas de crear.';
          });
        }
      } else {
        await ref.read(authServiceProvider).signInWithEmail(email, password);
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'user-not-found':
          case 'wrong-password':
          case 'invalid-credential':
            _error = 'Credenciales incorrectas o usuario no registrado.';
            break;
          case 'email-already-in-use':
            _error = 'Este correo ya tiene una cuenta activa. Inicia sesión o recupera tu contraseña.';
            break;
          case 'weak-password':
            _error = 'La contraseña es muy débil (mínimo 6 caracteres).';
            break;
          case 'invalid-email':
            _error = 'El formato del correo es inválido.';
            break;
          case 'invitation-not-found':
            _error = 'No hay una invitación activa para este correo. Solicítala al administrador.';
            break;
          case 'invalid-invitation':
            _error = 'La invitación está incompleta. Solicita al administrador que la renueve.';
            break;
          case 'email-not-verified':
            _error = 'Debes verificar tu correo. Te enviamos un enlace nuevo; después vuelve a iniciar sesión.';
            break;
          default:
            _error = e.message ?? 'Error de autenticación (${e.code}).';
        }
      });
    } catch (e) {
      setState(() => _error = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_firebaseReady) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 56,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Firebase no configurado',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'La autenticación pastoral requiere que se configure Firebase en el proyecto.\n\nEjecuta "flutterfire configure" en la terminal y luego llama a "Firebase.initializeApp()" en main.dart.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user != null) {
          final profileAsync = ref.watch(userProfileProvider);
          return profileAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _buildUnauthorizedProfile(
              'No fue posible verificar los permisos de esta cuenta.',
            ),
            data: (profile) => profile == null
                ? _buildUnauthorizedProfile(
                    'Esta cuenta no tiene un perfil ministerial autorizado.',
                  )
                : AdminDashboardScreen(
                    onPresent: widget.onPresent,
                    onCustomizeChurch: widget.onCustomizeChurch,
                  ),
          );
        }
        return _buildLoginForm(context);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error de Auth: $e')),
    );
  }

  Widget _buildUnauthorizedProfile(String message) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.gpp_bad_outlined,
                  size: 52,
                  color: Colors.orange,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Acceso no autorizado',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => ref.read(authServiceProvider).signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                elevation: 3,
                shadowColor: Colors.black.withAlpha(25),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Encabezado
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.indigo.withAlpha(20),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings_rounded,
                          color: Colors.indigo,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isActivating ? 'Activar Cuenta' : 'Acceso Ministerial',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isActivating
                            ? 'Crea tu contraseña con tu correo institucional'
                            : 'Ingresa para gestionar tu congregación',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: dark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Selector de modo sutil (pill toggle)
                      Container(
                        height: 40,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: dark ? Colors.white10 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => setState(() {
                                  _isActivating = false;
                                  _error = null;
                                  _notice = null;
                                }),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: !_isActivating
                                        ? (dark
                                              ? Colors.grey.shade800
                                              : Colors.white)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: !_isActivating
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withAlpha(15),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Iniciar Sesión',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: !_isActivating
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => setState(() {
                                  _isActivating = true;
                                  _error = null;
                                  _notice = null;
                                }),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _isActivating
                                        ? (dark
                                              ? Colors.grey.shade800
                                              : Colors.white)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: _isActivating
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withAlpha(15),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Primer Acceso',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: _isActivating
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Campos de Texto
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Correo electrónico',
                          hintText: 'correo@cgdi.org',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.mail_outline, size: 20),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: _isActivating
                              ? 'Nueva Contraseña'
                              : 'Contraseña',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.lock_outline, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      if (_isActivating) ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirm,
                          decoration: InputDecoration(
                            labelText: 'Confirmar Contraseña',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.lock_reset, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                () => _obscureConfirm = !_obscureConfirm,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                      ],
                      if (!_isActivating) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _showForgotPasswordDialog,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                            child: Text(
                              '¿Olvidaste tu contraseña?',
                              style: TextStyle(
                                fontSize: 12,
                                color: dark
                                    ? Colors.indigo.shade200
                                    : Colors.indigo.shade700,
                              ),
                            ),
                          ),
                        ),
                      ],

                      // Mensaje de Error
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withAlpha(60)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_notice != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.green.withAlpha(80),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.mark_email_read_outlined,
                                color: Colors.green,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _notice!,
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Botón Principal
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isActivating
                                      ? 'Activar Cuenta'
                                      : 'Iniciar Sesión',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Enlace limpio para regresar a la biblioteca
              TextButton.icon(
                onPressed: () => ref.read(tabProvider.notifier).setTab(0),
                icon: const Icon(
                  Icons.arrow_back,
                  size: 16,
                  color: Colors.grey,
                ),
                label: const Text(
                  'Volver a la Biblioteca',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
