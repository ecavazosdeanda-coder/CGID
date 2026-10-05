import 'package:flutter/foundation.dart';

/// Tipos de comandos remotos reconocidos por el sistema
enum RemoteAction {
  next,
  prev,
  black,
  nextSection,
  prevSection,
  jump,
  projectVerse,
  unknown;

  static RemoteAction fromString(String action) {
    switch (action.trim().toLowerCase()) {
      case 'next':
        return RemoteAction.next;
      case 'prev':
      case 'previous':
        return RemoteAction.prev;
      case 'black':
      case 'blackout':
        return RemoteAction.black;
      case 'next_section':
      case 'nextsection':
        return RemoteAction.nextSection;
      case 'prev_section':
      case 'prevsection':
      case 'previous_section':
        return RemoteAction.prevSection;
      case 'jump':
        return RemoteAction.jump;
      case 'project_verse':
      case 'projectverse':
        return RemoteAction.projectVerse;
      default:
        return RemoteAction.unknown;
    }
  }
}

/// Comando remoto estructurado con sus argumentos validados
class RemoteCommand {
  final RemoteAction action;
  final Map<String, dynamic>? payload;

  const RemoteCommand({
    required this.action,
    this.payload,
  });

  factory RemoteCommand.parse(String rawAction, [Map<String, dynamic>? payload]) {
    // Si la acción viene formateada como "jump_2", extraer el índice al payload
    if (rawAction.startsWith('jump_')) {
      final indexStr = rawAction.substring(5);
      final idx = int.tryParse(indexStr);
      final effectivePayload = Map<String, dynamic>.from(payload ?? {});
      if (idx != null) {
        effectivePayload['index'] = idx;
      }
      return RemoteCommand(
        action: RemoteAction.jump,
        payload: effectivePayload,
      );
    }

    final action = RemoteAction.fromString(rawAction);
    return RemoteCommand(action: action, payload: payload);
  }

  int? get jumpIndex {
    final raw = payload?['index'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  ({int book, int chapter, int verseStart, int verseEnd})? get verseReference {
    final b = payload?['b'];
    final c = payload?['c'];
    final vStart = payload?['vStart'];
    final vEnd = payload?['vEnd'];

    final book = (b is num) ? b.toInt() : (b is String ? int.tryParse(b) : null);
    final chapter = (c is num) ? c.toInt() : (c is String ? int.tryParse(c) : null);
    final verseS = (vStart is num) ? vStart.toInt() : (vStart is String ? int.tryParse(vStart) : null);
    final verseE = (vEnd is num) ? vEnd.toInt() : (vEnd is String ? int.tryParse(vEnd) : null);

    if (book != null && chapter != null && verseS != null && verseE != null) {
      return (book: book, chapter: chapter, verseStart: verseS, verseEnd: verseE);
    }
    return null;
  }
}

/// Delegado que define las acciones de control en la proyección o presentador
abstract class RemoteCommandReceiver {
  void onNext();
  void onPrev();
  void onToggleBlack();
  void onNextSection();
  void onPrevSection();
  void onJumpToPlan(int index);
  void onProjectVerse(int book, int chapter, int verseStart, int verseEnd);
}

/// Manejador y despachador de comandos remotos
class RemoteCommandHandler {
  final RemoteCommandReceiver receiver;

  const RemoteCommandHandler(this.receiver);

  /// Procesa una acción y su payload despachando hacia el receiver correspondiente
  bool handle(String rawAction, [Map<String, dynamic>? payload]) {
    try {
      final cmd = RemoteCommand.parse(rawAction, payload);
      switch (cmd.action) {
        case RemoteAction.next:
          receiver.onNext();
          return true;
        case RemoteAction.prev:
          receiver.onPrev();
          return true;
        case RemoteAction.black:
          receiver.onToggleBlack();
          return true;
        case RemoteAction.nextSection:
          receiver.onNextSection();
          return true;
        case RemoteAction.prevSection:
          receiver.onPrevSection();
          return true;
        case RemoteAction.jump:
          final idx = cmd.jumpIndex;
          if (idx != null) {
            receiver.onJumpToPlan(idx);
            return true;
          }
          return false;
        case RemoteAction.projectVerse:
          final ref = cmd.verseReference;
          if (ref != null) {
            receiver.onProjectVerse(ref.book, ref.chapter, ref.verseStart, ref.verseEnd);
            return true;
          }
          return false;
        case RemoteAction.unknown:
          debugPrint('Comando remoto desconocido recibido: $rawAction');
          return false;
      }
    } catch (e) {
      debugPrint('Error procesando comando remoto ($rawAction): $e');
      return false;
    }
  }
}
