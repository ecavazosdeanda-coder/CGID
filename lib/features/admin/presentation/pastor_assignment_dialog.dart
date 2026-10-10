import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tenant/models/church_model.dart';
import '../models/user_profile_model.dart';
import '../providers/user_profile_provider.dart';

class PastorAssignmentDialog extends ConsumerStatefulWidget {
  const PastorAssignmentDialog({super.key});

  @override
  ConsumerState<PastorAssignmentDialog> createState() =>
      _PastorAssignmentDialogState();
}

class _PastorAssignmentDialogState
    extends ConsumerState<PastorAssignmentDialog> {
  List<ChurchModel> _churches = [];
  bool _loadingChurches = true;

  @override
  void initState() {
    super.initState();
    _loadChurchesCatalog();
  }

  Future<void> _loadChurchesCatalog() async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/data/regions_and_churches.json',
      );
      final data = jsonDecode(jsonString);
      final List<dynamic> churchesJson = data['churches'];
      if (mounted) {
        setState(() {
          _churches = churchesJson.map((e) => ChurchModel.fromJson(e)).toList();
          _loadingChurches = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingChurches = false);
      }
    }
  }

  void _showAddNewPastorDialog() {
    final currentProfile = ref.read(userProfileProvider).value;
    final isPastor = currentProfile?.isPastor == true;

    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    ChurchModel? selectedChurch;
    if (isPastor && currentProfile?.churchId != null) {
      try {
        selectedChurch = _churches.firstWhere(
          (c) => c.id == currentProfile!.churchId,
        );
      } catch (_) {
        selectedChurch = _churches.isNotEmpty ? _churches.first : null;
      }
    } else {
      selectedChurch = _churches.isNotEmpty ? _churches.first : null;
    }

    String selectedRole = isPastor ? 'proyeccionista' : 'pastor';
    bool obscurePassword = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.person_add, color: Colors.indigo),
                  const SizedBox(width: 8),
                  Text(
                    isPastor
                        ? 'Registrar colaborador o equipo'
                        : 'Registrar Miembro Ministerial',
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText:
                              'Correo electrónico institucional / personal',
                          hintText: 'ejemplo@cgdi.org',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Rol Ministerial',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        items: isPastor
                            ? const [
                                DropdownMenuItem(
                                  value: 'colaborador',
                                  child: Text(
                                    'Colaborador Litúrgico (prepara órdenes de culto)',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'proyeccionista',
                                  child: Text(
                                    'Multimedia / Proyección (Cabina de Templo)',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'musico',
                                  child: Text(
                                    'Músico / Alabanza (Atril y Partituras)',
                                  ),
                                ),
                              ]
                            : const [
                                DropdownMenuItem(
                                  value: 'pastor',
                                  child: Text(
                                    'Pastor Local (Diseño de Cultos y Avisos)',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'colaborador',
                                  child: Text(
                                    'Colaborador Litúrgico (presidente o predicador)',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'proyeccionista',
                                  child: Text(
                                    'Multimedia / Proyección (Cabina de Templo)',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'musico',
                                  child: Text(
                                    'Músico / Alabanza (Atril y Partituras)',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'admin',
                                  child: Text(
                                    'Administrador General (Conferencia)',
                                  ),
                                ),
                              ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedRole = val);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      if (isPastor)
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Iglesia de la Congregación',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.church),
                            helperText: 'El usuario quedará registrado para tu congregación local.',
                          ),
                          child: Text(
                            currentProfile?.churchName ?? 'Mi Iglesia',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        )
                      else
                        DropdownButtonFormField<ChurchModel>(
                          initialValue: selectedChurch,
                          decoration: const InputDecoration(
                            labelText: 'Iglesia Asignada',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.church),
                          ),
                          isExpanded: true,
                          items: _churches.map((church) {
                            return DropdownMenuItem(
                              value: church,
                              child: Text(
                                church.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setDialogState(() => selectedChurch = val);
                          },
                        ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Contraseña de acceso (Opcional)',
                          hintText: 'Mínimo 6 caracteres',
                          helperText: 'Si la defines aquí, el usuario podrá ingresar de inmediato.',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () => setDialogState(
                              () => obscurePassword = !obscurePassword,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final email = emailController.text.trim();
                    final password = passwordController.text.trim();
                    final churchId = isPastor
                        ? (currentProfile?.churchId ?? '')
                        : (selectedChurch?.id ?? '');
                    final churchName = isPastor
                        ? (currentProfile?.churchName ?? 'Iglesia Local')
                        : (selectedChurch?.name ?? '');

                    if (email.isEmpty || churchId.isEmpty) return;
                    if (password.isNotEmpty && password.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'La contraseña debe tener mínimo 6 caracteres.',
                          ),
                        ),
                      );
                      return;
                    }

                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(ctx);
                    try {
                      await ref
                          .read(userManagementServiceProvider)
                          .registerNewPastor(
                            email: email,
                            churchId: churchId,
                            churchName: churchName,
                            password: password.isNotEmpty ? password : null,
                            role: selectedRole,
                          );
                      ref.invalidate(allUsersProvider);
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.green,
                            content: Text(
                              password.isNotEmpty
                                  ? 'Asignación guardada para $email. Si la cuenta es nueva, revisa el correo de verificación y spam; si ya existía, puede usar Reenviar verificación.'
                                  : 'Invitación creada para $email en $churchName. Ya puede activar su cuenta desde Primer Acceso.',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Error al registrar usuario: $e'),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showChangeRoleDialog(UserProfile user) {
    final currentProfile = ref.read(userProfileProvider).value;
    final isPastor = currentProfile?.isPastor == true;
    String selectedRole = user.role;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Cambiar Rol: ${user.email}'),
              content: RadioGroup<String>(
                groupValue: selectedRole,
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() => selectedRole = v);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isPastor) ...[
                      const RadioListTile<String>(
                        title: Text('Administrador General'),
                        subtitle: Text(
                          'Permisos completos de supervisión y gestión',
                        ),
                        value: 'admin',
                      ),
                      const RadioListTile<String>(
                        title: Text('Pastor Local'),
                        subtitle: Text(
                          'Diseño de cultos, avisos y liturgia de su iglesia',
                        ),
                        value: 'pastor',
                      ),
                    ],
                    const RadioListTile<String>(
                      title: Text('Colaborador Litúrgico'),
                      subtitle: Text(
                        'Prepara órdenes; su función cambia en cada culto',
                      ),
                      value: 'colaborador',
                    ),
                    const RadioListTile<String>(
                      title: Text('Multimedia / Proyección'),
                      subtitle: Text(
                        'Recepción de cultos en cabina y proyección en templo',
                      ),
                      value: 'proyeccionista',
                    ),
                    const RadioListTile<String>(
                      title: Text('Músico / Alabanza'),
                      subtitle: Text(
                        'Consulta de cantos programados y atril musical',
                      ),
                      value: 'musico',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(ctx);
                    try {
                      await ref
                          .read(userManagementServiceProvider)
                          .updateUserRole(user.uid, selectedRole);
                      ref.invalidate(allUsersProvider);
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.green,
                            content: Text(
                              'Rol de ${user.email} actualizado exitosamente.',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Error al cambiar rol: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Guardar Rol'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteUserDialog(UserProfile user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Miembro'),
        content: Text(
          '¿Estás seguro de que deseas eliminar la cuenta de ${user.email}? Ya no tendrá acceso al sistema.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              try {
                await ref
                    .read(userManagementServiceProvider)
                    .deleteUser(user.uid);
                ref.invalidate(allUsersProvider);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.redAccent,
                      content: Text('Usuario ${user.email} eliminado.'),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Error al eliminar: $e')),
                  );
                }
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _showManagePasswordDialog(UserProfile user) {
    final newPasswordController = TextEditingController();
    bool isSaving = false;
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.password, color: Colors.indigo),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Gestionar Contraseña: ${user.email}',
                      style: const TextStyle(fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Puedes definir una nueva contraseña directamente o enviarle un enlace oficial a su correo.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: newPasswordController,
                      decoration: const InputDecoration(
                        labelText: 'Nueva Contraseña',
                        hintText: 'Mínimo 6 caracteres',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.mark_email_read_outlined),
                        label: const Text(
                          'O enviar enlace de restablecimiento a su correo',
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                Navigator.pop(ctx);
                                try {
                                  await ref
                                      .read(userManagementServiceProvider)
                                      .sendPasswordResetToPastor(user.email);
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        backgroundColor: Colors.green,
                                        content: Text(
                                          'Enlace de restablecimiento enviado a ${user.email}.',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Error al enviar enlace: $e',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final newPass = newPasswordController.text.trim();
                          if (newPass.length < 6) {
                            setDialogState(
                              () => errorText = 'La contraseña debe tener al menos 6 caracteres.',
                            );
                            return;
                          }
                          setDialogState(() {
                            isSaving = true;
                            errorText = null;
                          });

                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(ctx);
                          try {
                            await ref
                                .read(userManagementServiceProvider)
                                .setPasswordForPastor(
                                  email: user.email,
                                  newPassword: newPass,
                                );
                            if (mounted) {
                              nav.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  backgroundColor: Colors.green,
                                  content: Text(
                                    'Cuenta creada para ${user.email}. Firebase aceptó el envío de la verificación; revisa el correo y spam.',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() {
                              isSaving = false;
                              errorText = '$e';
                            });
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Guardar Contraseña'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAssignChurchPicker(UserProfile user) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Asignar Iglesia a ${user.email}'),
          content: SizedBox(
            width: 400,
            height: 350,
            child: _churches.isEmpty
                ? const Center(child: Text('No hay iglesias en el catálogo.'))
                : ListView.builder(
                    itemCount: _churches.length,
                    itemBuilder: (context, index) {
                      final church = _churches[index];
                      final isSelected = church.id == user.churchId;
                      return ListTile(
                        leading: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.church_outlined,
                          color: isSelected ? Colors.green : null,
                        ),
                        title: Text(church.name),
                        subtitle: Text('${church.city}, ${church.state}'),
                        selected: isSelected,
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.pop(ctx);
                          try {
                            await ref
                                .read(userManagementServiceProvider)
                                .assignChurchToPastor(
                                  uid: user.uid,
                                  churchId: church.id,
                                  churchName: church.name,
                                );
                            ref.invalidate(allUsersProvider);
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  backgroundColor: Colors.green,
                                  content: Text(
                                    'Iglesia asignada a ${user.email} con éxito.',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Error al asignar iglesia: $e'),
                                ),
                              );
                            }
                          }
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.indigo;
      case 'pastor':
        return Colors.teal;
      case 'colaborador':
        return Colors.blueGrey;
      case 'proyeccionista':
        return Colors.blue;
      case 'musico':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'admin':
        return Icons.shield;
      case 'pastor':
        return Icons.person;
      case 'colaborador':
        return Icons.assignment_ind;
      case 'proyeccionista':
        return Icons.tv;
      case 'musico':
        return Icons.music_note;
      default:
        return Icons.account_circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentProfile = ref.watch(userProfileProvider).value;
    final isPastor = currentProfile?.isPastor == true;
    final usersAsync = ref.watch(allUsersProvider);

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                isPastor ? Icons.groups : Icons.admin_panel_settings,
                color: Colors.indigo,
              ),
              const SizedBox(width: 8),
              Text(
                isPastor
                    ? 'Equipo de ${currentProfile?.churchName ?? "la Iglesia"}'
                    : 'Gestión de Roles y Pastores',
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Actualizar lista',
                onPressed: () => ref.invalidate(allUsersProvider),
              ),
              FilledButton.icon(
                onPressed: _loadingChurches ? null : _showAddNewPastorDialog,
                icon: const Icon(Icons.person_add, size: 18),
                label: Text(
                  isPastor
                      ? 'Registrar colaborador / equipo'
                      : 'Agregar Miembro',
                ),
                style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        height: 490,
        child: _loadingChurches
            ? const Center(child: CircularProgressIndicator())
            : usersAsync.when(
                data: (users) {
                  final displayedUsers = isPastor
                      ? users
                            .where(
                              (u) => u.churchId == currentProfile?.churchId,
                            )
                            .toList()
                      : users;

                  if (displayedUsers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.people_outline,
                            size: 56,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isPastor
                                ? 'Aún no hay colaboradores, proyeccionistas ni músicos en tu congregación.'
                                : 'Aún no hay miembros registrados.',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isPastor
                                ? 'Registra a quienes preparan el culto, trabajan en cabina o participan en alabanza.'
                                : 'Haz clic en "Agregar Miembro" para registrar al equipo ministerial.',
                            style: const TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _showAddNewPastorDialog,
                            icon: const Icon(Icons.person_add),
                            label: Text(
                              isPastor
                                  ? 'Registrar colaborador / equipo'
                                  : 'Registrar Primer Miembro',
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: displayedUsers.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final user = displayedUsers[index];
                      final hasChurch =
                          user.churchId != null && user.churchId!.isNotEmpty;
                      final roleColor = _getRoleColor(user.role);
                      final roleIcon = _getRoleIcon(user.role);
                      final canModifyThisUser =
                          !isPastor ||
                          user.role == 'colaborador' ||
                          user.role == 'proyeccionista' ||
                          user.role == 'musico';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: roleColor,
                          child: Icon(roleIcon, color: Colors.white),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                user.email,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Chip(
                              label: Text(
                                user.roleDisplayName,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              backgroundColor: roleColor.withAlpha(35),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            hasChurch
                                ? 'Iglesia Asignada: ${user.churchName} (${user.churchId})'
                                : '⚠️ Sin iglesia asignada',
                            style: TextStyle(
                              color: hasChurch
                                  ? Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                  : (Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.orange.shade200
                                        : Colors.orange.shade800),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            if (action == 'assign_church') {
                              _showAssignChurchPicker(user);
                            } else if (action == 'manage_password') {
                              _showManagePasswordDialog(user);
                            } else if (action == 'change_role') {
                              _showChangeRoleDialog(user);
                            } else if (action == 'delete_user') {
                              _showDeleteUserDialog(user);
                            }
                          },
                          itemBuilder: (context) => [
                            if (!isPastor)
                              const PopupMenuItem(
                                value: 'assign_church',
                                child: Row(
                                  children: [
                                    Icon(Icons.church, size: 18),
                                    SizedBox(width: 8),
                                    Text('Asignar Iglesia'),
                                  ],
                                ),
                              ),
                            if (canModifyThisUser)
                              const PopupMenuItem(
                                value: 'change_role',
                                child: Row(
                                  children: [
                                    Icon(Icons.badge, size: 18),
                                    SizedBox(width: 8),
                                    Text('Cambiar Rol Ministerial'),
                                  ],
                                ),
                              ),
                            if (canModifyThisUser ||
                                user.uid == currentProfile?.uid)
                              const PopupMenuItem(
                                value: 'manage_password',
                                child: Row(
                                  children: [
                                    Icon(Icons.password, size: 18),
                                    SizedBox(width: 8),
                                    Text('Gestionar Contraseña'),
                                  ],
                                ),
                              ),
                            if (canModifyThisUser &&
                                user.uid != currentProfile?.uid)
                              const PopupMenuItem(
                                value: 'delete_user',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Eliminar Usuario',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Cargando miembros...'),
                    ],
                  ),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Error cargando usuarios: $e',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => ref.invalidate(allUsersProvider),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
