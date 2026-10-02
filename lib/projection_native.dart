import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';

bool get supportsOutput => Platform.isWindows;

Future<File> _getFile(String type) async {
  final dir = await getTemporaryDirectory();
  return File('${dir.path}/cgid_${type}_state.json');
}

Map<String, dynamic>? initialOutput;
String _currentMode = 'main';
Process? _outputProcess;
Process? _stageProcess;
Process? _overlayProcess;
Future<void> _pendingWrite = Future.value();
Future<void> _pendingProcessChange = Future.value();
String? _lastPayload;

Future<void> _writePayload(String payload, Iterable<String> targets) async {
  Object? firstError;
  for (final target in targets) {
    try {
      final file = await _getFile(target);
      await file.writeAsString(payload, flush: true);
    } catch (error) {
      firstError ??= error;
    }
  }
  if (firstError != null) {
    throw FileSystemException('No se pudo actualizar el estado de proyección.');
  }
}

Future<void> _queuePayload(String payload, Iterable<String> targets) {
  final operation = _pendingWrite.then(
    (_) => _writePayload(payload, targets),
    onError: (Object _, StackTrace _) => _writePayload(payload, targets),
  );
  _pendingWrite = operation.then<void>(
    (_) {},
    onError: (Object _, StackTrace _) {},
  );
  return operation;
}

Future<void> _replaceProcess({
  required String mode,
  required List<String> arguments,
}) async {
  Future<void> replace() async {
    Process? previous;
    if (mode == 'stage') {
      previous = _stageProcess;
    } else if (mode == 'overlay') {
      previous = _overlayProcess;
    } else {
      previous = _outputProcess;
    }

    if (previous != null) {
      try {
        previous.kill();
        await previous.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }

    final process = await Process.start(Platform.resolvedExecutable, arguments);
    if (mode == 'stage') {
      _stageProcess = process;
    } else if (mode == 'overlay') {
      _overlayProcess = process;
    } else {
      _outputProcess = process;
    }
    unawaited(
      process.exitCode.then((_) {
        if (mode == 'stage' && identical(_stageProcess, process)) {
          _stageProcess = null;
        } else if (mode == 'overlay' && identical(_overlayProcess, process)) {
          _overlayProcess = null;
        } else if (mode == 'projection' && identical(_outputProcess, process)) {
          _outputProcess = null;
        }
      }),
    );
  }

  final operation = _pendingProcessChange.then(
    (_) => replace(),
    onError: (Object _, StackTrace _) => replace(),
  );
  _pendingProcessChange = operation.then<void>(
    (_) {},
    onError: (Object _, StackTrace _) {},
  );
  await operation;
}

Future<String> initializeProjection(List<String> args) async {
  if (!supportsOutput) return 'main';
  await windowManager.ensureInitialized();

  if (args.contains('--projection')) {
    _currentMode = 'projection';
    final file = await _getFile('projection');
    if (await file.exists()) {
      try {
        initialOutput = jsonDecode(await file.readAsString());
      } catch (_) {}
    }
    await windowManager.setTitle('CGID · Proyección — F11 pantalla completa');
    return 'projection';
  }

  if (args.contains('--stage')) {
    _currentMode = 'stage';
    final file = await _getFile('stage');
    if (await file.exists()) {
      try {
        initialOutput = jsonDecode(await file.readAsString());
      } catch (_) {}
    }
    await windowManager.setTitle('CGID · Monitor de Escenario — F11 completa');
    return 'stage';
  }

  if (args.contains('--overlay')) {
    _currentMode = 'overlay';
    final file = await _getFile('overlay');
    if (await file.exists()) {
      try {
        initialOutput = jsonDecode(await file.readAsString());
      } catch (_) {}
    }
    await windowManager.setTitle('CGID · Salida OBS / Transmisión');
    return 'overlay';
  }

  if (args.contains('--dock')) {
    _currentMode = 'dock';
    final file = await _getFile('projection');
    if (await file.exists()) {
      try {
        initialOutput = jsonDecode(await file.readAsString());
      } catch (_) {}
    }
    await windowManager.setTitle('CGID · Panel OBS');
    return 'dock';
  }

  await windowManager.setTitle('CGID · Biblioteca y proyección');
  return 'main';
}

void Function() listenOutput(void Function(Map<String, dynamic>) callback) {
  var disposed = false;
  Timer? pollingTimer;
  var latest = initialOutput;
  if (latest != null) callback(latest);

  if (_currentMode != 'main') {
    unawaited(() async {
      final file = await _getFile(_currentMode);
      if (disposed) return;
      DateTime? lastModified;
      var reading = false;

      pollingTimer = Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) async {
        if (disposed || reading) return;
        reading = true;
        try {
          if (await file.exists()) {
            final mod = await file.lastModified();
            if (lastModified == null || mod.isAfter(lastModified!)) {
              final content = await file.readAsString();
              final map = jsonDecode(content);
              if (map is Map<String, dynamic>) {
                lastModified = mod;
                if (!disposed) callback(Map<String, dynamic>.from(map));
              }
            }
          }
        } catch (_) {
          // A writer may still be replacing the file. Keep the previous
          // timestamp so the next polling cycle retries the same version.
        } finally {
          reading = false;
        }
      });
    }());
  }

  return () {
    disposed = true;
    pollingTimer?.cancel();
  };
}

Future<void> openOutput(Map<String, dynamic> state) async {
  if (!supportsOutput) throw UnsupportedError('Windows only');
  final payload = jsonEncode(state);
  await _queuePayload(payload, const ['projection']);
  _lastPayload = payload;
  await _replaceProcess(mode: 'projection', arguments: const ['--projection']);
}

Future<void> openStage(Map<String, dynamic> state) async {
  if (!supportsOutput) return;
  final payload = jsonEncode(state);
  await _queuePayload(payload, const ['stage']);
  _lastPayload = payload;
  await _replaceProcess(mode: 'stage', arguments: const ['--stage']);
}

Future<void> openOverlay(
  Map<String, dynamic> state, {
  String bg = 'transparent',
  String mode = 'lowerthird',
}) async {
  if (!supportsOutput) return;
  final payload = jsonEncode(state);
  await _queuePayload(payload, const ['overlay']);
  _lastPayload = payload;
  await _replaceProcess(
    mode: 'overlay',
    arguments: ['--overlay', '--bg=$bg', '--mode=$mode'],
  );
}

Future<void> sendOutput(Map<String, dynamic> state) async {
  if (!supportsOutput) return;
  final payload = jsonEncode(state);
  if (payload == _lastPayload) return;

  await _queuePayload(payload, const ['projection', 'stage', 'overlay']);
  _lastPayload = payload;
}

Future<void> fullScreen(bool enabled) async {
  if (supportsOutput) await windowManager.setFullScreen(enabled);
}
