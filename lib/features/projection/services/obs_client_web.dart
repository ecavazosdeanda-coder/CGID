import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'obs_models.dart';

class ObsClient {
  web.WebSocket? _ws;
  Timer? _pollTimer;
  final ValueNotifier<ObsState> stateNotifier = ValueNotifier<ObsState>(
    const ObsState(),
  );

  ObsState get state => stateNotifier.value;
  int _requestId = 0;

  Future<void> connect({
    String host = '127.0.0.1',
    int port = 4455,
    String? password,
  }) async {
    disconnect();
    stateNotifier.value = state.copyWith(isConnecting: true, errorMessage: null);

    try {
      final ws = web.WebSocket('ws://$host:$port');
      _ws = ws;

      ws.onmessage = ((web.MessageEvent event) {
        final raw = (event.data as JSString).toDart;
        _handleMessage(raw, password);
      }).toJS;

      ws.onerror = ((web.Event event) {
        stateNotifier.value = state.copyWith(
          isConnected: false,
          isConnecting: false,
          errorMessage: 'Error conectando a OBS en ws://$host:$port',
        );
      }).toJS;

      ws.onclose = ((web.CloseEvent event) {
        disconnect();
      }).toJS;
    } catch (e) {
      stateNotifier.value = state.copyWith(
        isConnected: false,
        isConnecting: false,
        errorMessage: 'Fallo al iniciar conexión OBS: $e',
      );
    }
  }

  void disconnect() {
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    stateNotifier.value = state.copyWith(
      isConnected: false,
      isConnecting: false,
    );
  }

  void _send(Map<String, dynamic> msg) {
    if (_ws != null && _ws!.readyState == web.WebSocket.OPEN) {
      try {
        _ws!.send(jsonEncode(msg).toJS);
      } catch (_) {}
    }
  }

  void _handleMessage(String raw, String? password) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final op = json['op'] as int?;
      final d = json['d'] as Map<String, dynamic>? ?? {};

      if (op == 0) {
        _handleHello(d, password);
      } else if (op == 2) {
        stateNotifier.value = state.copyWith(
          isConnected: true,
          isConnecting: false,
          errorMessage: null,
        );
        _refreshState();
        _startPolling();
      } else if (op == 5) {
        _handleEvent(json['d'] as Map<String, dynamic>? ?? {});
      } else if (op == 7) {
        _handleResponse(d);
      }
    } catch (e) {
      debugPrint('OBS Web Msg error: $e');
    }
  }

  void _handleHello(Map<String, dynamic> d, String? password) {
    final authData = d['authentication'] as Map<String, dynamic>?;
    String? authResponse;

    if (authData != null && password != null && password.isNotEmpty) {
      final challenge = authData['challenge'] as String;
      final salt = authData['salt'] as String;

      final secret = base64.encode(
        sha256.convert(utf8.encode('$password$salt')).bytes,
      );
      authResponse = base64.encode(
        sha256.convert(utf8.encode('$secret$challenge')).bytes,
      );
    }

    final identifyPayload = <String, dynamic>{
      'rpcVersion': 1,
      'eventSubscriptions': 33,
    };
    if (authResponse != null) {
      identifyPayload['authentication'] = authResponse;
    }

    _send({
      'op': 1, // Identify
      'd': identifyPayload,
    });
  }

  void _handleEvent(Map<String, dynamic> event) {
    final eventType = event['eventType'] as String?;
    final eventData = event['eventData'] as Map<String, dynamic>? ?? {};

    if (eventType == 'StreamStateChanged') {
      final active = eventData['outputActive'] == true;
      stateNotifier.value = state.copyWith(isStreaming: active);
    } else if (eventType == 'RecordStateChanged') {
      final active = eventData['outputActive'] == true;
      stateNotifier.value = state.copyWith(isRecording: active);
    } else if (eventType == 'CurrentProgramSceneChanged') {
      final scene = eventData['sceneName'] as String?;
      if (scene != null) {
        stateNotifier.value = state.copyWith(currentScene: scene);
      }
    }
  }

  void _handleResponse(Map<String, dynamic> d) {
    final reqType = d['requestType'] as String?;
    final respData = d['responseData'] as Map<String, dynamic>? ?? {};

    if (reqType == 'GetStreamStatus') {
      stateNotifier.value = state.copyWith(
        isStreaming: respData['outputActive'] == true,
        streamTimecode: respData['outputTimecode'] as String? ?? '00:00:00',
      );
    } else if (reqType == 'GetRecordStatus') {
      stateNotifier.value = state.copyWith(
        isRecording: respData['outputActive'] == true,
        recordTimecode: respData['outputTimecode'] as String? ?? '00:00:00',
      );
    } else if (reqType == 'GetSceneList') {
      final scenesList = respData['scenes'] as List? ?? [];
      final names = scenesList
          .map((s) => (s as Map)['sceneName'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      stateNotifier.value = state.copyWith(
        scenes: names,
        currentScene: respData['currentProgramSceneName'] as String? ?? state.currentScene,
      );
    }
  }

  void _refreshState() {
    _sendRequest('GetStreamStatus');
    _sendRequest('GetRecordStatus');
    _sendRequest('GetSceneList');
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (state.isConnected) {
        if (state.isStreaming) _sendRequest('GetStreamStatus');
        if (state.isRecording) _sendRequest('GetRecordStatus');
      }
    });
  }

  void _sendRequest(String requestType, [Map<String, dynamic>? requestData]) {
    _requestId++;
    final dPayload = <String, dynamic>{
      'requestType': requestType,
      'requestId': 'cgdi-$_requestId',
    };
    if (requestData != null) {
      dPayload['requestData'] = requestData;
    }

    _send({
      'op': 6,
      'd': dPayload,
    });
  }

  Future<void> toggleStream() async {
    _sendRequest('ToggleStream');
    await Future.delayed(const Duration(milliseconds: 300));
    _sendRequest('GetStreamStatus');
  }

  Future<void> toggleRecord() async {
    _sendRequest('ToggleRecord');
    await Future.delayed(const Duration(milliseconds: 300));
    _sendRequest('GetRecordStatus');
  }

  Future<void> setCurrentScene(String sceneName) async {
    _sendRequest('SetCurrentProgramScene', {'sceneName': sceneName});
  }
}
