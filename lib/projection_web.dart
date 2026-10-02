import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get supportsOutput => true;
final _channel = web.BroadcastChannel('cgid_projection');
Map<String, dynamic>? _latest;
Future<String> initializeProjection([List<String> args = const []]) async {
  if (Uri.base.queryParameters['projection'] == '1') return 'projection';
  if (Uri.base.queryParameters['stage'] == '1') return 'stage';
  if (Uri.base.queryParameters['overlay'] == '1' ||
      Uri.base.queryParameters['mode'] == 'overlay' ||
      Uri.base.fragment.contains('overlay') ||
      Uri.base.fragment.contains('lowerthird') ||
      Uri.base.path.contains('overlay')) {
    return 'overlay';
  }
  if (Uri.base.queryParameters['dock'] == '1' ||
      Uri.base.fragment.contains('dock') ||
      Uri.base.path.contains('dock')) {
    return 'dock';
  }
  return 'main';
}

void Function() listenOutput(void Function(Map<String, dynamic>) callback) {
  _channel.onmessage = ((web.MessageEvent event) {
    final data = jsonDecode((event.data as JSString).toDart);
    if (data['request'] != true) callback(Map<String, dynamic>.from(data));
  }).toJS;
  _channel.postMessage(jsonEncode({'request': true}).toJS);
  return () {};
}

Future<void> openOutput(Map<String, dynamic> state) async {
  _latest = state;
  _channel.onmessage = ((web.MessageEvent event) {
    if (jsonDecode((event.data as JSString).toDart)['request'] == true &&
        _latest != null) {
      _channel.postMessage(jsonEncode(_latest).toJS);
    }
  }).toJS;
  final uri = Uri.base.replace(
    queryParameters: {'projection': '1'},
    fragment: '',
  );
  if (web.window.open(
        uri.toString(),
        'cgid_projection',
        'popup,width=1280,height=720',
      ) ==
      null) {
    throw StateError(
      'Permite las ventanas emergentes para abrir el proyector.',
    );
  }
}

Future<void> openStage(Map<String, dynamic> state) async {
  _latest = state;
  _channel.onmessage = ((web.MessageEvent event) {
    if (jsonDecode((event.data as JSString).toDart)['request'] == true &&
        _latest != null) {
      _channel.postMessage(jsonEncode(_latest).toJS);
    }
  }).toJS;
  final uri = Uri.base.replace(queryParameters: {'stage': '1'}, fragment: '');
  if (web.window.open(
        uri.toString(),
        'cgid_stage',
        'popup,width=1280,height=720',
      ) ==
      null) {
    throw StateError('Permite las ventanas emergentes para abrir el monitor.');
  }
}

Future<void> openOverlay(
  Map<String, dynamic> state, {
  String bg = 'transparent',
  String mode = 'lowerthird',
}) async {
  _latest = state;
  _channel.onmessage = ((web.MessageEvent event) {
    if (jsonDecode((event.data as JSString).toDart)['request'] == true &&
        _latest != null) {
      _channel.postMessage(jsonEncode(_latest).toJS);
    }
  }).toJS;
  final uri = Uri.base.replace(
    queryParameters: {
      'overlay': '1',
      if (bg != 'transparent') 'bg': bg,
      if (mode != 'lowerthird') 'mode': mode,
    },
    fragment: '',
  );
  if (web.window.open(
        uri.toString(),
        'cgid_overlay',
        'popup,width=1280,height=720',
      ) ==
      null) {
    throw StateError(
      'Permite las ventanas emergentes para abrir la salida de transmisión.',
    );
  }
}

Future<void> sendOutput(Map<String, dynamic> state) async {
  _latest = state;
  _channel.postMessage(jsonEncode(state).toJS);
}

Future<void> fullScreen(bool enabled) async {
  if (enabled) {
    await web.document.documentElement!.requestFullscreen().toDart;
  } else if (web.document.fullscreenElement != null) {
    await web.document.exitFullscreen().toDart;
  }
}
