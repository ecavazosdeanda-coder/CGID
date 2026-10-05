import 'package:flutter_test/flutter_test.dart';
import 'package:cgid/features/remote/services/remote_command_handler.dart';

class MockRemoteReceiver implements RemoteCommandReceiver {
  int nextCount = 0;
  int prevCount = 0;
  int blackCount = 0;
  int nextSectionCount = 0;
  int prevSectionCount = 0;
  int? jumpedIndex;
  ({int book, int chapter, int verseStart, int verseEnd})? projectedVerse;

  @override
  void onNext() => nextCount++;

  @override
  void onPrev() => prevCount++;

  @override
  void onToggleBlack() => blackCount++;

  @override
  void onNextSection() => nextSectionCount++;

  @override
  void onPrevSection() => prevSectionCount++;

  @override
  void onJumpToPlan(int index) => jumpedIndex = index;

  @override
  void onProjectVerse(int book, int chapter, int verseStart, int verseEnd) {
    projectedVerse = (book: book, chapter: chapter, verseStart: verseStart, verseEnd: verseEnd);
  }

  void reset() {
    nextCount = 0;
    prevCount = 0;
    blackCount = 0;
    nextSectionCount = 0;
    prevSectionCount = 0;
    jumpedIndex = null;
    projectedVerse = null;
  }
}

void main() {
  group('RemoteCommandHandler and RemoteCommand unit tests', () {
    late MockRemoteReceiver receiver;
    late RemoteCommandHandler handler;

    setUp(() {
      receiver = MockRemoteReceiver();
      handler = RemoteCommandHandler(receiver);
    });

    test('dispatches standard navigation commands (next, prev, black)', () {
      expect(handler.handle('next'), isTrue);
      expect(receiver.nextCount, 1);

      expect(handler.handle('prev'), isTrue);
      expect(receiver.prevCount, 1);

      expect(handler.handle('previous'), isTrue);
      expect(receiver.prevCount, 2);

      expect(handler.handle('black'), isTrue);
      expect(receiver.blackCount, 1);

      expect(handler.handle('blackout'), isTrue);
      expect(receiver.blackCount, 2);
    });

    test('dispatches section navigation commands', () {
      expect(handler.handle('next_section'), isTrue);
      expect(receiver.nextSectionCount, 1);

      expect(handler.handle('prev_section'), isTrue);
      expect(receiver.prevSectionCount, 1);
    });

    test('parses and handles jump command with payload index', () {
      final success = handler.handle('jump', {'index': 4});
      expect(success, isTrue);
      expect(receiver.jumpedIndex, 4);

      // String index in payload
      final successStr = handler.handle('jump', {'index': '7'});
      expect(successStr, isTrue);
      expect(receiver.jumpedIndex, 7);
    });

    test('parses shorthand jump_X command strings', () {
      final success = handler.handle('jump_3');
      expect(success, isTrue);
      expect(receiver.jumpedIndex, 3);
    });

    test('parses and handles project_verse with biblical coordinates', () {
      final payload = {
        'b': 19,
        'c': 23,
        'vStart': 1,
        'vEnd': 6,
      };
      final success = handler.handle('project_verse', payload);
      expect(success, isTrue);
      expect(receiver.projectedVerse, isNotNull);
      expect(receiver.projectedVerse?.book, 19);
      expect(receiver.projectedVerse?.chapter, 23);
      expect(receiver.projectedVerse?.verseStart, 1);
      expect(receiver.projectedVerse?.verseEnd, 6);
    });

    test('gracefully rejects incomplete project_verse coordinates', () {
      final incompletePayload = {
        'b': 19,
        'c': 23,
        // missing vStart and vEnd
      };
      final success = handler.handle('project_verse', incompletePayload);
      expect(success, isFalse);
      expect(receiver.projectedVerse, isNull);
    });

    test('gracefully rejects unknown action without throwing', () {
      final success = handler.handle('non_existent_action_123');
      expect(success, isFalse);
    });
  });
}
