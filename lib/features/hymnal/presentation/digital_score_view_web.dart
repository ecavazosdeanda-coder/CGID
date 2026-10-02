import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

var _viewCounter = 0;

Widget buildDigitalScoreView(String source, {required bool dark}) {
  final viewType = 'cgid-score-${_viewCounter++}';
  final viewerUri = Uri(
    path: 'score_viewer.html',
    queryParameters: {'score': source, if (dark) 'dark': '1'},
  );
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final frame = web.HTMLIFrameElement()
      ..src = viewerUri.toString()
      ..title = 'Partitura digital MusicXML'
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%';
    frame.setAttribute('loading', 'eager');
    return frame;
  });
  return HtmlElementView(viewType: viewType);
}
