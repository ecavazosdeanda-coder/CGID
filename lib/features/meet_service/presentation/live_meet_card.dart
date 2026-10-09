import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../tenant/presentation/church_selector_dialog.dart';
import '../../tenant/providers/tenant_provider.dart';
import '../../low_bandwidth_audio/presentation/audio_stream_player_modal.dart';
import '../../events/presentation/church_events_screen.dart';
import '../../notifications/services/web_push_service.dart';
import '../services/meet_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LiveMeetCard extends ConsumerStatefulWidget {
  const LiveMeetCard({super.key});

  @override
  ConsumerState<LiveMeetCard> createState() => _LiveMeetCardState();
}

class _LiveMeetCardState extends ConsumerState<LiveMeetCard> {
  Timer? _refreshTimer;
  String? _lastNotifiedMeetingKey;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
      _checkAndNotifyUpcomingMeeting();
    });
  }

  void _checkAndNotifyUpcomingMeeting() async {
    if (!kIsWeb) return;
    try {
      final church = ref.read(tenantProvider).asData?.value;
      if (church == null) return;
      final active = MeetScheduler.getActiveMeeting(church, bufferMinutes: 15);
      if (active != null) {
        final key = '${church.id}_${active.title}_${active.weekday}_${active.startTime.hour}:${active.startTime.minute}';
        if (_lastNotifiedMeetingKey != key) {
          _lastNotifiedMeetingKey = key;
          final meetUrl = active.customMeetUrl?.trim().isNotEmpty == true
              ? active.customMeetUrl!.trim()
              : church.defaultMeetUrl.trim();
          await WebPushNotificationService.showLocalReminder(
            title: 'Culto en Vivo · ${active.title}',
            body: 'El culto en ${church.name} está por comenzar. Haz clic para unirte.',
            meetUrl: meetUrl.isNotEmpty ? meetUrl : null,
          );
        }
      }
    } catch (_) {}
  }


  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _editMeetUrl(String churchId, String currentUrl) async {
    final controller = TextEditingController(text: currentUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configurar Sala de Meet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Puedes pegar aquí el enlace de la videollamada de tu iglesia.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Enlace de Google Meet',
                hintText: 'https://meet.google.com/xxx-yyyy-zzz',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse('https://meet.google.com/new');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.add_box),
              label: const Text('Hacer nueva sala temporal'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      if (result.isEmpty) {
        await prefs.remove('custom_meet_url_$churchId');
      } else {
        await prefs.setString('custom_meet_url_$churchId', result);
      }
      ref.invalidate(tenantProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final churchAsync = ref.watch(tenantProvider);

    return churchAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => const Text('No se pudo cargar la iglesia local.'),
      data: (church) {
        if (church == null) {
          return Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.church),
              title: const Text('Selecciona tu Iglesia Local'),
              subtitle: const Text('Para ver horarios y Google Meet'),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () async {
                final selected = await ChurchSelectorDialog.show(context);
                if (selected != null) {
                  ref.invalidate(tenantProvider);
                }
              },
            ),
          );
        }

        // Calculate active meeting synchronously
        final activeMeeting = MeetScheduler.getActiveMeeting(church);
        final customMeetUrl = activeMeeting?.customMeetUrl?.trim() ?? '';
        final activeMeetUrl = customMeetUrl.isNotEmpty
            ? customMeetUrl
            : church.defaultMeetUrl.trim();

        return Card(
          color: activeMeeting != null
              ? const Color(0xff183e43).withValues(alpha: 0.1)
              : Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: activeMeeting != null
                  ? const Color(0xff183e43)
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        church.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (kIsWeb && WebPushNotificationService.isSupported)
                      IconButton(
                        tooltip: 'Notificaciones y Recordatorios de Culto',
                        icon: const Icon(Icons.notifications_active_outlined, size: 20),
                        onPressed: () async {
                          final granted = await WebPushNotificationService.requestPermission();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  granted
                                      ? '¡Notificaciones activadas! Te avisaremos 15 min antes de cada culto.'
                                      : 'Permiso de notificaciones denegado o no concedido.',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    TextButton.icon(
                      onPressed: () async {
                        final selected = await ChurchSelectorDialog.show(
                          context,
                        );
                        if (selected != null) {
                          ref.invalidate(tenantProvider);
                        }
                      },
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Cambiar'),
                    ),
                  ],
                ),
                if (church.address.trim().isNotEmpty) ...[
                  Text(
                    church.address,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                ],
                if (church.googleMapsUrl.trim().isNotEmpty) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(church.googleMapsUrl.trim());
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    icon: const Icon(Icons.directions),
                    label: const Text('Cómo llegar'),
                  ),
                  const SizedBox(height: 10),
                ],
                if (church.currentNotices.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer
                          .withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Avisos de la iglesia',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        for (final notice in church.currentNotices.take(3))
                          Text('• $notice'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 12),
                if (activeMeeting != null) ...[
                  const Row(
                    children: [
                      Icon(Icons.sensors, color: Colors.red, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Culto en Vivo o Próximo',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    activeMeeting.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xff183e43),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        onPressed: activeMeetUrl.isEmpty
                            ? null
                            : () async {
                                final uri = Uri.parse(activeMeetUrl);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                        icon: const Icon(Icons.video_call),
                        label: const Text('Unirse a Google Meet'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          side: const BorderSide(color: Colors.teal),
                          foregroundColor: Colors.teal.shade800,
                        ),
                        onPressed: () {
                          AudioStreamPlayerModal.show(context, church);
                        },
                        icon: const Icon(Icons.radio, size: 20, color: Colors.teal),
                        label: const Text('Solo Audio (Ahorro Datos)'),
                      ),
                      IconButton(
                        tooltip: 'Configurar enlace de Meet',
                        onPressed: () => _editMeetUrl(church.id, activeMeetUrl),
                        icon: const Icon(Icons.settings, size: 20, color: Colors.grey),
                      ),
                    ],
                  ),
                ] else ...[
                  const Text('No hay cultos activos en este momento.'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: church.defaultMeetUrl.trim().isEmpty
                            ? null
                            : () async {
                                final uri = Uri.parse(church.defaultMeetUrl.trim());
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                        icon: const Icon(Icons.video_call),
                        label: const Text('Abrir Sala de Meet de la Iglesia'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.teal),
                          foregroundColor: Colors.teal.shade800,
                        ),
                        onPressed: () {
                          AudioStreamPlayerModal.show(context, church);
                        },
                        icon: const Icon(Icons.radio, size: 20, color: Colors.teal),
                        label: const Text('Transmisión de Audio'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ChurchEventsScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.event, size: 20),
                        label: const Text('Eventos y Convocatorias'),
                      ),
                      IconButton(
                        tooltip: 'Configurar enlace de Meet',
                        onPressed: () => _editMeetUrl(church.id, church.defaultMeetUrl),
                        icon: const Icon(Icons.settings, size: 20, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
