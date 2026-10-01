import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../appearance.dart';
import '../../../slide_view.dart';
import '../../../motion_background_view.dart';
import '../../../projection_native.dart' if (dart.library.js_interop) '../../../projection_web.dart' as projection;
import 'projection_output_view.dart';
class OutputScreen extends StatefulWidget {
  const OutputScreen({super.key});
  @override
  State<OutputScreen> createState() => _OutputScreenState();
}

class _OutputScreenState extends State<OutputScreen> {
  Map<String, dynamic>? state;
  late final void Function() _stopListening;

  @override
  void initState() {
    super.initState();
    _stopListening = projection.listenOutput((data) {
      if (mounted) setState(() => state = data);
    });
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (state == null) return const Scaffold(backgroundColor: Colors.black);
    return Scaffold(
      backgroundColor: Colors.black,
      body: ProjectionOutputView(state: state!),
    );
  }
}
