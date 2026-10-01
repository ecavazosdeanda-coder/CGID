import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'content.dart';
import 'playback.dart';
import 'glass.dart';

class LyricCue {
  final int startMs, endMs, sectionIndex, lineIndex;
  const LyricCue(this.startMs, this.endMs, this.sectionIndex, this.lineIndex);
  Map<String, int> toJson() => {
    'startMs': startMs,
    'endMs': endMs,
    'sectionIndex': sectionIndex,
    'lineIndex': lineIndex,
  };
  factory LyricCue.fromJson(Map<String, dynamic> j) => LyricCue(
    j['startMs'] as int,
    j['endMs'] as int,
    j['sectionIndex'] as int,
    j['lineIndex'] as int,
  );
}

LyricCue? cueAt(List<LyricCue> cues, int timeMs) {
  for (final cue in cues) {
    if (timeMs >= cue.startMs && timeMs < cue.endMs) return cue;
  }
  return null;
}

bool validCues(List<LyricCue> cues, Entry entry) {
  var previousEnd = 0;
  for (final cue in cues) {
    if (cue.startMs < previousEnd ||
        cue.endMs <= cue.startMs ||
        cue.sectionIndex < 0 ||
        cue.sectionIndex >= entry.sections.length ||
        cue.lineIndex < 0 ||
        cue.lineIndex >=
            entry.sections[cue.sectionIndex].text.split('\n').length) {
      return false;
    }
    previousEnd = cue.endMs;
  }
  return true;
}

class LyricFollow extends StatefulWidget {
  final Entry entry;
  final PlaybackController playback;
  const LyricFollow({super.key, required this.entry, required this.playback});
  @override
  State<LyricFollow> createState() => _LyricFollowState();
}

class _LyricFollowState extends State<LyricFollow> {
  List<LyricCue> cues = [];
  String? storageKey, message;
  bool hasTimingTrack = false;
  bool editing = false, following = true;
  int? pendingStart, pendingSection, pendingLine;
  List<LyricCue> saved = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final metadata = jsonDecode(
        await rootBundle.loadString('assets/audio/timings_v2.json'),
      );
      final track = metadata['tracks'][widget.entry.id];
      if (track == null) {
        if (mounted) setState(() => hasTimingTrack = false);
        return;
      }
      final key =
          'lyric-cues-v1:${widget.entry.id}:${track['sha256']}:${jsonEncode(widget.entry.sections.map((s) => s.toJson()).toList())}';

      if (mounted) {
        setState(() {
          storageKey = key;
          hasTimingTrack = true;
        });
      }

      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getString(key);
      final raw = local == null ? track['cues'] : jsonDecode(local);
      final loaded = [
        for (final c in raw) LyricCue.fromJson(Map<String, dynamic>.from(c)),
      ];
      if (!validCues(loaded, widget.entry)) {
        throw const FormatException(
          'Tiempos inválidos o incompatibles con la letra actual.',
        );
      }
      if (mounted) {
        setState(() {
          cues = loaded;
        });
      }
    } catch (error) {
      debugPrint('Lyric timing load failed: $error');
      if (mounted) {
        setState(
          () => message = 'No se pudieron cargar los tiempos de esta letra.',
        );
      }
    }
  }

  void mark(int? section, int? line) {
    final p = widget.playback;
    final closingCompleted =
        section == null &&
        pendingStart != null &&
        p.completedHymnId == widget.entry.id;
    if (!closingCompleted &&
        (p.activeId != widget.entry.id || (!p.playing && section != null))) {
      return;
    }
    final now = p.position.inMilliseconds;
    if (pendingStart != null) {
      if (now <= pendingStart!) return;
      cues.add(LyricCue(pendingStart!, now, pendingSection!, pendingLine!));
    } else if (cues.isNotEmpty && now < cues.last.endMs) {
      setState(
        () => message =
            'Deshaz las últimas marcas antes de marcar un tiempo anterior.',
      );
      return;
    }
    setState(() {
      pendingStart = section == null ? null : now;
      pendingSection = section;
      pendingLine = line;
      message = null;
    });
  }

  Future<void> save() async {
    if (storageKey == null) return;
    if (pendingStart != null) {
      setState(
        () => message = 'Pulsa «Fin de línea / instrumental» al terminar la última línea antes de guardar.',
      );
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setString(
        storageKey!,
        jsonEncode(cues.map((c) => c.toJson()).toList()),
      );
      if (!ok) throw StateError('No guardado');
      if (mounted) {
        setState(() {
          editing = false;
          message = 'Tiempos guardados en este dispositivo.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'No se pudo guardar. Conserva el editor abierto e inténtalo de nuevo.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.playback,
    builder: (context, _) {
      final p = widget.playback;
      // The playback catalog may still be loading when this widget is first
      // shown. A timing record is only created for an associated audio track,
      // so it is the stable source of truth for enabling the editor.
      final audioAvailable = hasTimingTrack;
      final current = following && p.activeId == widget.entry.id
          ? cueAt(cues, p.position.inMilliseconds)
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassSurface(
            radius: 16,
            padding: const EdgeInsets.all(10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!editing)
                  OutlinedButton.icon(
                    onPressed: !audioAvailable || storageKey == null
                        ? null
                        : () => setState(() {
                            saved = List.of(cues);
                            editing = true;
                          }),
                    icon: const Icon(Icons.timer_outlined),
                    label: const Text('Sincronizar letra'),
                  ),
                if (!editing && cues.isNotEmpty)
                  FilterChip(
                    label: const Text('Seguir letra'),
                    selected: following,
                    onSelected: (v) => setState(() => following = v),
                  ),
                if (editing) ...[
                  TextButton(
                    onPressed: () => setState(() {
                      cues = [];
                      pendingStart = null;
                      message = 'Nueva secuencia. Reinicia el audio para marcar desde el principio.';
                    }),
                    child: const Text('Nueva secuencia'),
                  ),
                  TextButton(
                    onPressed: () => mark(null, null),
                    child: const Text('Fin de línea / instrumental'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      if (pendingStart != null) {
                        pendingStart = null;
                      } else if (cues.isNotEmpty) {
                        cues.removeLast();
                      }
                    }),
                    child: const Text('Deshacer marca'),
                  ),
                  FilledButton(
                    onPressed: save,
                    child: const Text('Guardar tiempos'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      cues = saved;
                      pendingStart = null;
                      editing = false;
                      message = null;
                    }),
                    child: const Text('Cancelar'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (editing)
            Text(
              'Reproduce el audio y pulsa cada línea cuando empiece. Puedes volver a pulsar un coro para repetirlo. ${cues.length} marcas cerradas.',
            ),
          if (!editing && !hasTimingTrack)
            const Text(
              'Sincronización preparada. Este himno todavía no tiene un audio asociado.',
            )
          else if (!editing && cues.isEmpty)
            const Text(
              'Letra sin sincronizar. Reproduce el audio y usa «Sincronizar letra» para marcar cada línea.',
            ),
          if (message != null) Text(message!),
          if (!editing && current != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.entry.sections[current.sectionIndex].text.split(
                    '\n',
                  )[current.lineIndex],
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
          for (var si = 0; si < widget.entry.sections.length; si++) ...[
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              child: Text(
                widget.entry.sections[si].label,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (
              var li = 0;
              li < widget.entry.sections[si].text.split('\n').length;
              li++
            )
              Builder(
                builder: (_) {
                  final highlighted = editing
                      ? pendingStart != null &&
                            pendingSection == si &&
                            pendingLine == li
                      : current?.sectionIndex == si && current?.lineIndex == li;
                  final text = widget.entry.sections[si].text.split('\n')[li];
                  return Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: highlighted
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    child: editing
                        ? InkWell(
                            onTap: () => mark(si, li),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                text,
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                          )
                        : SelectableText(
                            text,
                            style: const TextStyle(fontSize: 20, height: 1.7),
                          ),
                  );
                },
              ),
          ],
        ],
      );
    },
  );
}
