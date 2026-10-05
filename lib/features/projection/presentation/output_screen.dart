import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/projection_provider.dart';
import 'projection_output_view.dart';

class OutputScreen extends ConsumerWidget {
  const OutputScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(projectionProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: ProjectionOutputView(state: state),
    );
  }
}
