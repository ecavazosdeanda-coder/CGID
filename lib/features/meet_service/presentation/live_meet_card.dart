import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../../tenant/models/church_model.dart';
import '../../tenant/presentation/church_selector_dialog.dart';

class LiveMeetCard extends StatefulWidget {
  const LiveMeetCard({super.key});

  @override
  State<LiveMeetCard> createState() => _LiveMeetCardState();
}

class _LiveMeetCardState extends State<LiveMeetCard> {
  ChurchModel? _currentChurch;
  ServiceMeeting? _activeMeeting;

  @override
  void initState() {
    super.initState();
    _loadChurch();
  }

  Future<void> _loadChurch() async {
    final prefs = await SharedPreferences.getInstance();
    final churchId = prefs.getString('selected_church_id');
    if (churchId != null) {
      try {
        final jsonString = await rootBundle.loadString('assets/data/regions_and_churches.json');
        final data = jsonDecode(jsonString);
        final List<dynamic> churchesJson = data['churches'];
        final churchData = churchesJson.firstWhere((e) => e['id'] == churchId, orElse: () => null);
        if (churchData != null && mounted) {
          setState(() {
            _currentChurch = ChurchModel.fromJson(churchData);
            _determineActiveMeeting();
          });
        }
      } catch (e) {
        // ignore
      }
    }
  }

  void _determineActiveMeeting() {
    if (_currentChurch == null) return;
    
    final now = DateTime.now();
    final currentWeekday = now.weekday; // 1: Monday, 7: Sunday
    final currentTime = TimeOfDay.fromDateTime(now);

    for (final meeting in _currentChurch!.weeklyServices) {
      if (meeting.weekday == currentWeekday) {
        final startMinutes = meeting.startTime.hour * 60 + meeting.startTime.minute;
        final endMinutes = meeting.endTime.hour * 60 + meeting.endTime.minute;
        final currentMinutes = currentTime.hour * 60 + currentTime.minute;
        
        // Let's assume a meeting is active if current time is within 30 mins before start to the end
        if (currentMinutes >= (startMinutes - 30) && currentMinutes <= endMinutes) {
          setState(() {
            _activeMeeting = meeting;
          });
          return;
        }
      }
    }
    setState(() {
      _activeMeeting = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentChurch == null) {
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
              setState(() {
                _currentChurch = selected;
                _determineActiveMeeting();
              });
            }
          },
        ),
      );
    }

    return Card(
      color: _activeMeeting != null 
          ? const Color(0xff183e43).withValues(alpha: 0.1) 
          : Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _activeMeeting != null 
              ? const Color(0xff183e43) 
              : Colors.transparent,
          width: 2,
        )
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
                    _currentChurch!.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final selected = await ChurchSelectorDialog.show(context);
                    if (selected != null) {
                      setState(() {
                        _currentChurch = selected;
                        _determineActiveMeeting();
                      });
                    }
                  },
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Cambiar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_activeMeeting != null) ...[
              const Row(
                children: [
                  Icon(Icons.sensors, color: Colors.red, size: 18),
                  SizedBox(width: 6),
                  Text('Culto en Vivo o Próximo', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _activeMeeting!.title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff183e43),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () async {
                  final url = _activeMeeting!.customMeetUrl ?? _currentChurch!.defaultMeetUrl;
                  if (url.isNotEmpty) {
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  }
                },
                icon: const Icon(Icons.video_call),
                label: const Text('Unirse a Google Meet'),
              ),
            ] else ...[
              const Text('No hay cultos activos en este momento.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final url = _currentChurch!.defaultMeetUrl;
                  if (url.isNotEmpty) {
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  }
                },
                icon: const Icon(Icons.video_call),
                label: const Text('Abrir Sala de Meet de la Iglesia'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
