import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RemoteServer {
  final void Function(int delta) onMove;
  final void Function() onToggleBlack;
  final void Function()? onNextSection;
  final void Function()? onPrevSection;
  final void Function(int index)? onJumpToPlan;
  final void Function(int b, int c, int vStart, int vEnd)? onProjectVerse;
  final Map<String, dynamic> Function()? getState;
  final int port;
  final bool configureFirewall;
  final Duration connectionTimeout;
  HttpServer? _server;
  Future<List<String>>? _starting;

  final Map<String, Timer> _activeClients = {};
  final _connectionController = StreamController<String?>.broadcast();

  RemoteServer({
    required this.onMove,
    required this.onToggleBlack,
    this.onNextSection,
    this.onPrevSection,
    this.onJumpToPlan,
    this.onProjectVerse,
    this.getState,
    this.port = 8765,
    this.configureFirewall = true,
    this.connectionTimeout = const Duration(seconds: 5),
  });

  Stream<String?> get onConnectionChanged => _connectionController.stream;
  int? get boundPort => _server?.port;

  void disconnectDevice() {
    final wasConnected = _activeClients.isNotEmpty;
    for (final timer in _activeClients.values) {
      timer.cancel();
    }
    _activeClients.clear();
    if (wasConnected) _connectionController.add(null);
  }

  Future<List<String>> start() {
    final activeStart = _starting;
    if (activeStart != null) return activeStart;
    final operation = _start();
    _starting = operation;
    operation.whenComplete(() {
      if (identical(_starting, operation)) _starting = null;
    });
    return operation;
  }

  Future<List<String>> _start() async {
    try {
      if (_server == null) {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        _server!.listen((request) => unawaited(_handleRequest(request)));
        if (Platform.isWindows && configureFirewall && port == 8765) {
          try {
            await Process.run('netsh', [
              'advfirewall',
              'firewall',
              'add',
              'rule',
              'name=CGID Remote Control',
              'protocol=TCP',
              'dir=in',
              'localport=8765',
              'action=allow',
            ]);
          } catch (_) {}
        }
      }
      final actualPort = _server!.port;
      List<String> urls = [];
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            urls.add('http://${addr.address}:$actualPort');
          }
        }
      }
      if (urls.isEmpty) urls.add('http://localhost:$actualPort');
      return urls;
    } catch (e) {
      return [];
    }
  }

  Future<void> stop() async {
    final activeStart = _starting;
    if (activeStart != null) await activeStart;
    disconnectDevice();
    await _server?.close(force: true);
    _server = null;
  }

  void _addCors(HttpResponse response) {
    response.headers
      ..add('Access-Control-Allow-Origin', '*')
      ..add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..add('Access-Control-Allow-Headers', 'Content-Type');
  }

  void _updateConnectionStatus() {
    if (_activeClients.isEmpty) {
      _connectionController.add(null);
    } else if (_activeClients.length == 1) {
      _connectionController.add(_activeClients.keys.first);
    } else {
      _connectionController.add('${_activeClients.length} dispositivos');
    }
  }

  bool _claimConnection(String clientIp) {
    _activeClients[clientIp]?.cancel();
    _activeClients[clientIp] = Timer(connectionTimeout, () {
      _activeClients.remove(clientIp);
      _updateConnectionStatus();
    });
    _updateConnectionStatus();
    return true;
  }

  Future<void> _writeJson(
    HttpResponse response,
    int statusCode,
    Map<String, dynamic> payload,
  ) async {
    response
      ..headers.contentType = ContentType.json
      ..statusCode = statusCode
      ..write(jsonEncode(payload));
    await response.close();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _addCors(request.response);

    final clientIp =
        request.connectionInfo?.remoteAddress.address ?? 'Desconocido';

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    if (request.method == 'GET' && request.uri.path == '/') {
      request.response.headers.contentType = ContentType.html;
      request.response.write(_webUi());
      await request.response.close();
      return;
    }

    if (request.method == 'GET' &&
        (request.uri.path == '/ping' || request.uri.path == '/state')) {
      if (!_claimConnection(clientIp)) {
        await _writeJson(request.response, HttpStatus.forbidden, {
          'status': 'busy',
        });
        return;
      }

      final state = getState?.call() ?? {};
      await _writeJson(request.response, HttpStatus.ok, {
        'status': 'pong',
        ...state,
      });
      return;
    }

    if (request.method == 'POST') {
      if (!_claimConnection(clientIp)) {
        await _writeJson(request.response, HttpStatus.forbidden, {
          'status': 'busy',
        });
        return;
      }

      final path = request.uri.path;
      var handled = true;

      try {
        if (path == '/next') {
          onMove(1);
        } else if (path == '/prev') {
          onMove(-1);
        } else if (path == '/black') {
          onToggleBlack();
        } else if (path == '/next_section') {
          onNextSection?.call();
        } else if (path == '/prev_section') {
          onPrevSection?.call();
        } else if (path.startsWith('/jump/')) {
          final idx = int.tryParse(path.substring('/jump/'.length));
          if (idx == null || idx < 0) {
            await _writeJson(request.response, HttpStatus.badRequest, {
              'status': 'invalid_index',
            });
            return;
          }
          onJumpToPlan?.call(idx);
        } else if (path == '/project_verse') {
          final body = await utf8.decoder.bind(request).join();
          final decoded = jsonDecode(body);
          if (decoded is! Map<String, dynamic> ||
              decoded['b'] is! int ||
              decoded['c'] is! int ||
              decoded['vStart'] is! int ||
              decoded['vEnd'] is! int ||
              (decoded['b'] as int) < 0 ||
              (decoded['c'] as int) < 0 ||
              (decoded['vStart'] as int) < 1 ||
              (decoded['vEnd'] as int) < (decoded['vStart'] as int)) {
            await _writeJson(request.response, HttpStatus.badRequest, {
              'status': 'invalid_verse',
            });
            return;
          }
          onProjectVerse?.call(
            decoded['b'] as int,
            decoded['c'] as int,
            decoded['vStart'] as int,
            decoded['vEnd'] as int,
          );
        } else {
          handled = false;
        }
      } on FormatException {
        await _writeJson(request.response, HttpStatus.badRequest, {
          'status': 'invalid_json',
        });
        return;
      } catch (_) {
        await _writeJson(request.response, HttpStatus.internalServerError, {
          'status': 'error',
        });
        return;
      }

      if (!handled) {
        await _writeJson(request.response, HttpStatus.notFound, {
          'status': 'not_found',
        });
        return;
      }
      final state = getState?.call() ?? {};
      await _writeJson(request.response, HttpStatus.ok, {
        'status': 'ok',
        ...state,
      });
      return;
    }

    await _writeJson(request.response, HttpStatus.notFound, {
      'status': 'not_found',
    });
  }

  String _webUi() => '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=0">
  <title>Teleprompter Remoto CGID</title>
  <style>
    * { box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 14px; background: #0b141a; color: #fff; text-align: center; }
    header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; }
    .title { font-size: 14px; font-weight: bold; color: #78a594; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 70%; text-align: left; }
    .badge { font-size: 12px; padding: 4px 8px; border-radius: 6px; background: #1f2c34; color: #94a3b8; }
    .tele-card { background: #182229; border: 1px solid #233138; border-radius: 14px; padding: 16px; margin-bottom: 12px; text-align: left; }
    .tele-card.current { border-left: 4px solid #10b981; }
    .tele-card.next { border-left: 4px solid #64748b; opacity: 0.85; }
    .tele-meta { font-size: 11px; text-transform: uppercase; font-weight: 700; letter-spacing: 1px; color: #10b981; margin-bottom: 6px; }
    .tele-card.next .tele-meta { color: #94a3b8; }
    .tele-text { font-size: 18px; line-height: 1.45; font-weight: 600; white-space: pre-wrap; word-break: break-word; }
    .tele-card.next .tele-text { font-size: 14px; color: #cbd5e1; }
    .black-banner { display: none; background: #ef4444; color: white; padding: 8px; border-radius: 8px; margin-bottom: 12px; font-weight: bold; font-size: 13px; text-align: center; }
    .controls { display: grid; grid-template-columns: 1fr 2fr 1fr; gap: 8px; margin-top: 10px; }
    .btn { padding: 18px 8px; font-size: 16px; border: none; border-radius: 12px; background: #202c33; color: #fff; cursor: pointer; text-transform: uppercase; font-weight: 700; -webkit-tap-highlight-color: transparent; }
    .btn:active { transform: scale(0.98); opacity: 0.85; }
    .btn-next { background: #0284c7; font-size: 20px; }
    .btn-black { background: #7f1d1d; }
  </style>
</head>
<body>
  <div id="black-alert" class="black-banner">PANTALLA NEGRA ACTIVA EN PROYECCIÓN</div>
  <header>
    <div id="hymn-title" class="title">CGID Proyección</div>
    <div id="slide-num" class="badge">0 / 0</div>
  </header>
  <div class="tele-card current">
    <div id="cur-meta" class="tele-meta">En pantalla ahora</div>
    <div id="cur-text" class="tele-text">Esperando contenido proyectado…</div>
  </div>
  <div class="tele-card next">
    <div id="next-meta" class="tele-meta">Siguiente diapositiva</div>
    <div id="next-text" class="tele-text">Fin del canto / sección</div>
  </div>
  <div class="controls">
    <button class="btn" ontouchstart="" onclick="send('/prev')">◀ Ant</button>
    <button class="btn btn-next" ontouchstart="" onclick="send('/next')">Siguiente ▶</button>
    <button class="btn btn-black" ontouchstart="" onclick="send('/black')">■ Negro</button>
  </div>
  <script>
    function updateUI(data) {
      if (!data) return;
      if (data.currentTitle) document.getElementById('hymn-title').textContent = data.currentTitle;
      document.getElementById('slide-num').textContent = (data.slideIndex || 0) + ' / ' + (data.totalSlides || 0);
      document.getElementById('cur-meta').textContent = (data.currentLabel ? data.currentLabel.toUpperCase() : 'EN PANTALLA');
      document.getElementById('cur-text').textContent = data.currentText || '—';
      document.getElementById('next-meta').textContent = 'SIGUIENTE' + (data.nextLabel ? ' (' + data.nextLabel.toUpperCase() + ')' : '');
      document.getElementById('next-text').textContent = data.nextText || 'Fin del canto / sin más diapositivas';
      document.getElementById('black-alert').style.display = data.blackout ? 'block' : 'none';
    }
    let commandQueue = Promise.resolve();
    function send(path) {
      commandQueue = commandQueue
        .then(() => fetch(window.location.origin + path, { method: 'POST' }))
        .then(r => r.json().then(data => ({ ok: r.ok, data })))
        .then(result => {
          if (!result.ok) throw new Error(result.data.status || 'command_error');
          updateUI(result.data);
        })
        .catch(console.error);
    }
    function ping() {
      fetch(window.location.origin + '/ping')
        .then(r => r.json()).then(updateUI).catch(()=>{});
    }
    ping();
    setInterval(ping, 1500);
  </script>
</body>
</html>
''';
}
