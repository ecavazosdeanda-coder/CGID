import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workspace/providers/plan_provider.dart';
import '../../workspace/providers/tab_provider.dart';
import '../../tenant/providers/tenant_provider.dart';
import '../models/user_profile_model.dart';
import '../providers/user_profile_provider.dart';
import 'pastor_assignment_dialog.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../projection/providers/projection_provider.dart';
import '../../projection/presentation/stream_overlay_dialog.dart';

import 'notices_editor_screen.dart';
import 'service_builder_screen.dart';
import 'special_hymn_uploader_screen.dart';
import '../../literature/presentation/document_editor_dialog.dart';

import 'package:file_picker/file_picker.dart';

import '../../tenant/presentation/church_selector_dialog.dart';
import '../../tenant/models/church_model.dart';
import '../../low_bandwidth_audio/presentation/audio_stream_player_modal.dart';
import '../../hymnal/presentation/lectern_reader_screen.dart';
import '../../../content.dart';
import '../../../cult_picker_native.dart'
    if (dart.library.js_interop) '../../../cult_picker_web.dart'
    as cult_picker;

class AdminDashboardScreen extends ConsumerStatefulWidget {
  final Future<void> Function(Entry entry)? onPresent;
  final VoidCallback? onCustomizeChurch;

  const AdminDashboardScreen({
    super.key,
    this.onPresent,
    this.onCustomizeChurch,
  });

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  int _savedPlansCount = 0;
  String _currentChurch = 'No configurada';
  bool _isUploading = false;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    final plansJson = prefs.getString('plans') ?? '{}';
    final plansMap = jsonDecode(plansJson) as Map<String, dynamic>;

    final churchName =
        prefs.getString('tenant_church_name') ?? 'No configurada';

    if (mounted) {
      setState(() {
        _savedPlansCount = plansMap.length;
        _currentChurch = churchName;
      });
    }
  }

  Future<void> _exportDatabase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final db = <String, dynamic>{};
      for (final key in keys) {
        db[key] = prefs.get(key);
      }

      final jsonBytes = utf8.encode(jsonEncode(db));
      final date = DateTime.now().toIso8601String().split('T').first;

      final saved = await cult_picker.saveCultFile(
        'cgdi_backup_$date.json',
        jsonBytes,
        'application/json',
      );

      if (mounted && saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Base de datos exportada correctamente.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
      }
    }
  }

  Future<void> _importDatabase() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (file != null) {
        final bytes = await file.readAsBytes();
        final jsonString = utf8.decode(bytes);
        final db = jsonDecode(jsonString) as Map<String, dynamic>;

        final prefs = await SharedPreferences.getInstance();
        for (final entry in db.entries) {
          final key = entry.key;
          final value = entry.value;
          if (value is String) {
            await prefs.setString(key, value);
          } else if (value is int) {
            await prefs.setInt(key, value);
          } else if (value is double) {
            await prefs.setDouble(key, value);
          } else if (value is bool) {
            await prefs.setBool(key, value);
          } else if (value is List) {
            await prefs.setStringList(
              key,
              value.map((e) => e.toString()).toList(),
            );
          }
        }

        await _loadStats();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Base de datos importada exitosamente. Reinicia la aplicación.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al importar: $e')));
      }
    }
  }

  Future<void> _clearDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar base de datos'),
        content: const Text(
          '¿Estás seguro de que deseas borrar todas las preferencias y cultos guardados? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Borrar Todo',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Base de datos reiniciada a fábrica.')),
        );
      }
    }
  }

  Color _getRoleColor(UserProfile? profile) {
    if (profile == null) return Colors.grey;
    if (profile.isAdmin) return Colors.indigo;
    if (profile.isPastor) return Colors.teal;
    if (profile.isCollaborator) return Colors.blueGrey;
    if (profile.isProyeccionista) return Colors.deepPurple;
    if (profile.isMusico) return Colors.amber.shade800;
    return Colors.blueGrey;
  }

  IconData _getRoleIcon(UserProfile? profile) {
    if (profile == null) return Icons.person;
    if (profile.isAdmin) return Icons.admin_panel_settings;
    if (profile.isPastor) return Icons.person_pin;
    if (profile.isCollaborator) return Icons.assignment_ind;
    if (profile.isProyeccionista) return Icons.connected_tv;
    if (profile.isMusico) return Icons.music_note;
    return Icons.badge;
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final profile = profileAsync.value;

    // Si es pastor, proyeccionista o músico con iglesia asignada, asegurar sincronización del tenant local
    if (profile != null && !profile.isAdmin && profile.churchId != null) {
      if (_currentChurch != profile.churchName) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('selected_church_id', profile.churchId!);
          if (profile.churchName != null) {
            await prefs.setString('tenant_church_name', profile.churchName!);
          }
          if (mounted) {
            setState(() {
              _currentChurch = profile.churchName ?? 'Iglesia Asignada';
            });
          }
        });
      }
    }

    final roleColor = _getRoleColor(profile);
    final roleIcon = _getRoleIcon(profile);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Administración del Sistema',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Cerrar sesión',
              onPressed: () async {
                try {
                  await FirebaseAuth.instance.signOut();
                } catch (e) {
                  // ignore
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Banner de Rol y Perfil de Usuario
        if (profile != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: roleColor.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: roleColor.withAlpha(70)),
            ),
            child: Row(
              children: [
                Icon(roleIcon, color: roleColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            profile.roleDisplayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(
                              profile.role.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: roleColor,
                              ),
                            ),
                            backgroundColor: roleColor.withAlpha(25),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.isAdmin
                            ? 'Permisos de Conferencia General para supervisar, diseñar, asignar miembros y sincronizar cualquier iglesia.'
                            : (profile.churchId != null
                                  ? 'Asignado a: ${profile.churchName}'
                                  : '⚠️ Sin iglesia asignada. Solicita a la Conferencia General que te asigne tu congregación.'),
                        style: TextStyle(
                          fontSize: 13,
                          color: (!profile.isAdmin && profile.churchId == null)
                              ? Colors.orange[900]
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                if (profile.canManageTeam)
                  FilledButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => const PastorAssignmentDialog(),
                      );
                    },
                    icon: const Icon(Icons.people_alt, size: 18),
                    label: Text(
                      profile.isAdmin
                          ? 'Gestionar Equipo'
                          : 'Equipo de la Iglesia',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // SECCIÓN ESPECÍFICA: CABINA DE PROYECCIÓN DEL TEMPLO
        if (profile?.canAccessProjection == true) ...[
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.deepPurple.shade200, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withAlpha(30),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.connected_tv,
                          color: Colors.deepPurple,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cabina de Proyección del Templo',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              (profile != null &&
                                      !profile.isAdmin &&
                                      profile.churchId != null)
                                  ? 'Santuario: ${profile.churchName ?? "Iglesia Asignada"}'
                                  : 'Santuario: $_currentChurch',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Descarga en 1 clic el orden litúrgico preparado por el pastor y proyecta las diapositivas en las pantallas del templo.',
                    style: TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  StatefulBuilder(
                    builder: (context, setLocalState) {
                      final tenant = ref.watch(tenantProvider).value;
                      final targetChurchId =
                          (profile != null &&
                              !profile.isAdmin &&
                              profile.churchId != null)
                          ? profile.churchId
                          : tenant?.id;
                      final canDownload =
                          targetChurchId != null && targetChurchId.isNotEmpty;

                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            icon: _isDownloading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.cloud_download),
                            label: const Text('Descargar Culto de Hoy'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                            ),
                            onPressed: _isDownloading || !canDownload
                                ? null
                                : () async {
                                    setLocalState(() => _isDownloading = true);
                                    try {
                                      await ref
                                          .read(planProvider.notifier)
                                          .fetchFromCloud(targetChurchId);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                backgroundColor: Colors.green,
                                                content: Text(
                                                  '¡Plan litúrgico descargado exitosamente para la cabina!',
                                                ),
                                              ),
                                            );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            backgroundColor: Colors.redAccent,
                                            content: Text(
                                              'Error al descargar: $e',
                                            ),
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (context.mounted) {
                                        setLocalState(
                                          () => _isDownloading = false,
                                        );
                                      }
                                    }
                                  },
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(
                              Icons.airplay,
                              color: Colors.deepPurple,
                            ),
                            label: const Text('Abrir Pantalla de Proyección'),
                            onPressed: () {
                              ref.read(tabProvider.notifier).setTab(5);
                            },
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.developer_board),
                            label: const Text('Monitor de Escenario / Atril'),
                            onPressed: () {
                              ref.read(tabProvider.notifier).setTab(4);
                            },
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(
                              Icons.sensors,
                              color: Color(0xFF6366F1),
                            ),
                            label: const Text('Salida OBS / Transmisión'),
                            onPressed: () {
                              final notifier = ref.read(
                                projectionProvider.notifier,
                              );
                              StreamOverlayDialog.show(
                                context,
                                notifier.outputState,
                              );
                            },
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.format_list_bulleted),
                            label: const Text('Ver Cultos Guardados'),
                            onPressed: () {
                              ref.read(tabProvider.notifier).setTab(6);
                            },
                          ),
                          if (profile?.canEditPlans == true)
                            OutlinedButton.icon(
                              icon: const Icon(
                                Icons.edit_calendar,
                                color: Colors.deepPurple,
                              ),
                              label: const Text('Editar Plan Litúrgico'),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ServiceBuilderScreen(
                                      onPresent: widget.onPresent,
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // SECCIÓN ESPECÍFICA: REPERTORIO Y ATRIL MUSICAL
        if (profile?.canAccessMusic == true) ...[
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.amber.shade400, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.queue_music,
                          color: Colors.amber.shade900,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Repertorio y Atril Musical',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              (profile != null &&
                                      !profile.isAdmin &&
                                      profile.churchId != null)
                                  ? 'Congregación: ${profile.churchName ?? "Iglesia Asignada"}'
                                  : 'Congregación: $_currentChurch',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Sincroniza los cantos preparados por el pastor y abre directamente las partituras y acordes para la alabanza.',
                    style: TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  StatefulBuilder(
                    builder: (context, setLocalState) {
                      final tenant = ref.watch(tenantProvider).value;
                      final targetChurchId =
                          (profile != null &&
                              !profile.isAdmin &&
                              profile.churchId != null)
                          ? profile.churchId
                          : tenant?.id;
                      final canDownload =
                          targetChurchId != null && targetChurchId.isNotEmpty;

                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            icon: _isDownloading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.cloud_download),
                            label: const Text('Descargar Repertorio de Culto'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.amber.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                            ),
                            onPressed: _isDownloading || !canDownload
                                ? null
                                : () async {
                                    setLocalState(() => _isDownloading = true);
                                    try {
                                      await ref
                                          .read(planProvider.notifier)
                                          .fetchFromCloud(targetChurchId);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                backgroundColor: Colors.green,
                                                content: Text(
                                                  '¡Repertorio y cantos descargados exitosamente!',
                                                ),
                                              ),
                                            );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            backgroundColor: Colors.redAccent,
                                            content: Text(
                                              'Error al descargar: $e',
                                            ),
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (context.mounted) {
                                        setLocalState(
                                          () => _isDownloading = false,
                                        );
                                      }
                                    }
                                  },
                          ),
                          FilledButton.icon(
                            icon: const Icon(
                              Icons.music_note,
                              color: Colors.white,
                            ),
                            label: const Text('Abrir Atril en Vivo (Culto)'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.teal.shade800,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              final currentPlan = ref.read(planProvider).plan;
                              final hymnsInPlan = currentPlan
                                  .where((e) => e.id.startsWith('h'))
                                  .toList();
                              if (hymnsInPlan.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'No hay cantos en el programa actual. Descarga o agrega cantos primero.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LecternReaderScreen(
                                    entry: hymnsInPlan.first,
                                    repertoireList: hymnsInPlan,
                                    initialRepertoireIndex: 0,
                                  ),
                                ),
                              );
                            },
                          ),
                          ElevatedButton.icon(
                            icon: Icon(
                              Icons.library_music,
                              color: Colors.amber.shade900,
                            ),
                            label: const Text('Partituras Digitales'),
                            onPressed: () {
                              ref.read(tabProvider.notifier).setTab(4);
                            },
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.menu_book),
                            label: const Text('Himnario con Acordes'),
                            onPressed: () {
                              ref.read(tabProvider.notifier).setTab(1);
                            },
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.list_alt),
                            label: const Text('Ver Orden del Culto'),
                            onPressed: () {
                              ref.read(tabProvider.notifier).setTab(6);
                            },
                          ),
                          if (profile?.canEditPlans == true)
                            OutlinedButton.icon(
                              icon: Icon(
                                Icons.playlist_add,
                                color: Colors.amber.shade900,
                              ),
                              label: const Text('Ajustar Selección de Cantos'),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ServiceBuilderScreen(
                                      onPresent: widget.onPresent,
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // GESTIÓN DE EQUIPO MINISTERIAL (Admin y Pastores)
        if (profile != null && profile.canManageTeam) ...[
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people_alt, color: Colors.indigo),
                      const SizedBox(width: 8),
                      Text(
                        profile.isAdmin
                            ? 'Gestión de Roles y Pastores'
                            : 'Equipo Ministerial de la Iglesia',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile.isAdmin
                        ? 'Registra pastores, proyeccionistas y músicos de cualquier iglesia, asigna contraseñas y configura distritos.'
                        : 'Crea y gestiona las cuentas de tus proyeccionistas de cabina y músicos de alabanza para tu congregación (${profile.churchName ?? "Iglesia Local"}).',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.person_add),
                        label: Text(
                          profile.isAdmin
                              ? 'Registrar Miembro'
                              : 'Crear Cuenta (Proyeccionista / Músico)',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.indigo,
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => const PastorAssignmentDialog(),
                          );
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.manage_accounts),
                        label: Text(
                          profile.isAdmin
                              ? 'Administrar Roles'
                              : 'Ver Equipo y Claves',
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => const PastorAssignmentDialog(),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // HERRAMIENTAS PASTORALES (Diseño de Cultos y Avisos)
        if (profile?.canEditPlans == true) ...[
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.assignment, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        'Herramientas Pastorales',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Planifica los cultos de la iglesia y redacta los avisos de la semana.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.list_alt),
                        label: const Text('Armar Plan de Culto'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ServiceBuilderScreen(
                                onPresent: widget.onPresent,
                              ),
                            ),
                          );
                        },
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.campaign),
                        label: const Text('Redactar Avisos Semanales'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NoticesEditorScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // GESTIÓN DE HIMNOS ESPECIALES
        if (profile?.canEditPlans == true || profile?.isAdmin == true) ...[
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.queue_music, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      const Text(
                        'Gestión de Himnos Especiales',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sube y administra himnos locales o especiales (ej. Aniversarios) que no están en el himnario oficial. Puedes incluir letra, partitura y audio.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Subir Himno Especial'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.amber.shade800,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SpecialHymnUploaderScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // GESTIÓN DE LITERATURA OFICIAL (Exclusivo Administrador Master)
        if (profile?.isAdmin == true) ...[
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.library_books, color: Colors.purple),
                      SizedBox(width: 8),
                      Text(
                        'Gestión de Literatura Oficial',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 8),
                      Chip(
                        label: Text(
                          'Administrador Master',
                          style: TextStyle(fontSize: 11),
                        ),
                        backgroundColor: Color(0xFFF3E5F5),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sube nuevos documentos, estudios doctrinales, revistas y folletos oficiales para que todos los miembros y templos puedan consultarlos en PDF.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.post_add),
                        label: const Text('Subir Nueva Literatura'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.purple.shade700,
                        ),
                        onPressed: () {
                          DocumentEditorDialog.show(context);
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.auto_stories),
                        label: const Text('Explorar y Editar Catálogo'),
                        onPressed: () {
                          ref.read(tabProvider.notifier).setTab(7);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // SINCRONIZACIÓN EN LA NUBE (Para Administradores y Pastores con permisos de subida)
        if (profile?.canSyncPlansToCloud == true) ...[
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cloud_sync, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'Sincronización en la Nube (Cloud Sync)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sube tu plan de culto diseñado a la nube para que el proyeccionista y los músicos lo reciban en el templo.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  StatefulBuilder(
                    builder: (context, setLocalState) {
                      final tenant = ref.watch(tenantProvider).value;
                      final targetChurchId = profile?.isAdmin == true
                          ? tenant?.id
                          : profile?.churchId;
                      final canSync =
                          targetChurchId != null && targetChurchId.isNotEmpty;

                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          ElevatedButton.icon(
                            icon: _isUploading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload),
                            label: const Text('Subir a la nube'),
                            onPressed:
                                _isUploading || _isDownloading || !canSync
                                ? null
                                : () async {
                                    setLocalState(() => _isUploading = true);
                                    try {
                                      await ref
                                          .read(planProvider.notifier)
                                          .syncToCloud(targetChurchId);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                backgroundColor: Colors.green,
                                                content: Text(
                                                  'Plan sincronizado exitosamente en la nube.',
                                                ),
                                              ),
                                            );
                                      }
                                    } catch (e) {
                                      if (e.toString().contains('CONFLICT')) {
                                        if (context.mounted) {
                                          final force = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Conflicto de Edición'),
                                              content: const Text('Alguien más modificó el plan en la nube recientemente. Si subes ahora, sobrescribirás sus cambios.\n\n¿Deseas sobrescribir con tu versión local?'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                                FilledButton(
                                                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                                  onPressed: () => Navigator.pop(ctx, true),
                                                  child: const Text('Sobrescribir'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (force == true && context.mounted) {
                                            setLocalState(() => _isUploading = true);
                                            try {
                                              await ref.read(planProvider.notifier).syncToCloud(targetChurchId, forceOverwrite: true);
                                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text('Sobrescrito forzosamente.')));
                                            } catch (e2) {
                                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.redAccent, content: Text('Error al sobrescribir: $e2')));
                                            }
                                          }
                                        }
                                      } else if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            backgroundColor: Colors.redAccent,
                                            content: Text('Error al subir: $e'),
                                            duration: const Duration(
                                              seconds: 6,
                                            ),
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (context.mounted) {
                                        setLocalState(
                                          () => _isUploading = false,
                                        );
                                      }
                                    }
                                  },
                          ),
                          ElevatedButton.icon(
                            icon: _isDownloading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_download),
                            label: const Text('Descargar de la nube'),
                            onPressed:
                                _isUploading || _isDownloading || !canSync
                                ? null
                                : () async {
                                    setLocalState(() => _isDownloading = true);
                                    try {
                                      await ref
                                          .read(planProvider.notifier)
                                          .fetchFromCloud(targetChurchId);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                backgroundColor: Colors.green,
                                                content: Text(
                                                  'Plan descargado exitosamente de la nube.',
                                                ),
                                              ),
                                            );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            backgroundColor: Colors.redAccent,
                                            content: Text(
                                              'Error al descargar: $e',
                                            ),
                                            duration: const Duration(
                                              seconds: 6,
                                            ),
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (context.mounted) {
                                        setLocalState(
                                          () => _isDownloading = false,
                                        );
                                      }
                                    }
                                  },
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // CONGREGACIÓN LOCAL O ASIGNADA
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      profile?.isAdmin == true
                          ? Icons.church
                          : Icons.lock_outline,
                      color: profile?.isAdmin == true
                          ? Colors.blueAccent
                          : Colors.teal,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      profile?.isAdmin == true
                          ? 'Congregación Local'
                          : 'Congregación Asignada',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (profile != null && !profile.isAdmin) ...[
                      const SizedBox(width: 8),
                      const Chip(
                        label: Text(
                          'Asignación Ministerial Fija',
                          style: TextStyle(fontSize: 11),
                        ),
                        backgroundColor: Color(0xFFE0F2F1),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  profile != null && !profile.isAdmin
                      ? (profile.churchId != null
                            ? 'Esta cuenta ministerial solo tiene permisos asignados sobre: ${profile.churchName}'
                            : '⚠️ Sin iglesia asignada por la Conferencia General. Contacta al Administrador.')
                      : 'Configuración actual: $_currentChurch',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                if (profile?.canSwitchChurch == true) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.settings),
                    label: const Text('Configurar Distrito e Iglesia'),
                    onPressed: () async {
                      final church = await showDialog(
                        context: context,
                        builder: (ctx) => const ChurchSelectorDialog(),
                      );
                      if (church != null && church is ChurchModel) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(
                          'tenant_church_name',
                          church.name,
                        );
                        await prefs.setString('selected_church_id', church.id);
                      }
                      _loadStats();
                    },
                  ),
                ] else if (profile != null &&
                    !profile.isAdmin &&
                    profile.churchId == null) ...[
                  const Text(
                    'Pide a un Administrador General que asigne tu iglesia para poder sincronizar cultos.',
                    style: TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ],
                if (widget.onCustomizeChurch != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.palette_outlined),
                    label: const Text('Personalizar nombre y logotipo'),
                    onPressed: widget.onCustomizeChurch,
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.radio, color: Colors.teal),
                  label: const Text('Configurar / Probar Transmisión de Audio'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.teal.shade800,
                  ),
                  onPressed: () {
                    final tenant = ref.read(tenantProvider).value;
                    if (tenant != null) {
                      AudioStreamPlayerModal.show(context, tenant);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Selecciona una iglesia primero.'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // BASE DE DATOS LOCAL
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.storage, color: Colors.orange),
                    SizedBox(width: 8),
                    Text(
                      'Base de Datos Local',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Cultos guardados: $_savedPlansCount',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Crear Respaldo'),
                      onPressed: _exportDatabase,
                    ),
                    if (profile?.canRestoreDatabase == true)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.upload),
                        label: const Text('Restaurar Respaldo'),
                        onPressed: _importDatabase,
                      ),
                    if (profile?.canResetDatabase == true)
                      OutlinedButton.icon(
                        icon: const Icon(
                          Icons.delete_forever,
                          color: Colors.red,
                        ),
                        label: const Text(
                          'Borrar Todos los Datos',
                          style: TextStyle(color: Colors.red),
                        ),
                        onPressed: _clearDatabase,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
