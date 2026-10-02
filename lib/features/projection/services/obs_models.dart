class ObsState {
  final bool isConnected;
  final bool isConnecting;
  final String? errorMessage;
  final bool isStreaming;
  final bool isRecording;
  final String streamTimecode;
  final String recordTimecode;
  final String currentScene;
  final List<String> scenes;
  final double fps;
  final double cpuUsage;

  const ObsState({
    this.isConnected = false,
    this.isConnecting = false,
    this.errorMessage,
    this.isStreaming = false,
    this.isRecording = false,
    this.streamTimecode = '00:00:00',
    this.recordTimecode = '00:00:00',
    this.currentScene = '',
    this.scenes = const [],
    this.fps = 0.0,
    this.cpuUsage = 0.0,
  });

  ObsState copyWith({
    bool? isConnected,
    bool? isConnecting,
    String? errorMessage,
    bool? isStreaming,
    bool? isRecording,
    String? streamTimecode,
    String? recordTimecode,
    String? currentScene,
    List<String>? scenes,
    double? fps,
    double? cpuUsage,
  }) {
    return ObsState(
      isConnected: isConnected ?? this.isConnected,
      isConnecting: isConnecting ?? this.isConnecting,
      errorMessage: errorMessage,
      isStreaming: isStreaming ?? this.isStreaming,
      isRecording: isRecording ?? this.isRecording,
      streamTimecode: streamTimecode ?? this.streamTimecode,
      recordTimecode: recordTimecode ?? this.recordTimecode,
      currentScene: currentScene ?? this.currentScene,
      scenes: scenes ?? this.scenes,
      fps: fps ?? this.fps,
      cpuUsage: cpuUsage ?? this.cpuUsage,
    );
  }
}
