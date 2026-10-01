import 'dart:async';

import 'package:flutter/material.dart';

class CountdownOverlay extends StatefulWidget {
  final int? endsAt;
  final Widget child;

  const CountdownOverlay({super.key, this.endsAt, required this.child});

  @override
  State<CountdownOverlay> createState() => _CountdownOverlayState();
}

class _CountdownOverlayState extends State<CountdownOverlay> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _update();
    _configureTimer();
  }

  @override
  void didUpdateWidget(covariant CountdownOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.endsAt != oldWidget.endsAt) {
      _update();
      _configureTimer();
    }
  }

  void _configureTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.endsAt == null ||
        widget.endsAt! <= DateTime.now().millisecondsSinceEpoch) {
      return;
    }
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _update(),
    );
  }

  void _update() {
    if (widget.endsAt == null) {
      if (_remaining != Duration.zero) {
        setState(() => _remaining = Duration.zero);
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = widget.endsAt! - now;
    if (diff <= 0) {
      _timer?.cancel();
      _timer = null;
    }
    final newRemaining = diff > 0
        ? Duration(milliseconds: diff)
        : Duration.zero;
    if (_remaining.inSeconds != newRemaining.inSeconds) {
      setState(() => _remaining = newRemaining);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.endsAt == null || _remaining == Duration.zero) {
      return widget.child;
    }
    final minutes = _remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (_remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Container(
          color: Colors.black,
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: Padding(
                padding: EdgeInsets.all(constraints.maxHeight * .08),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$minutes:$seconds',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 250,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
