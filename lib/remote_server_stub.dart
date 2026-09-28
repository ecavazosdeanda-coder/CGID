import 'dart:async';

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

  int? get boundPort => null;

  Future<List<String>> start() async => [];
  Future<void> stop() async {}
  Stream<String?> get onConnectionChanged => const Stream.empty();
  void disconnectDevice() {}
}
