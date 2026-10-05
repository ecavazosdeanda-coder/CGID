
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../content.dart';
import '../../remote/services/cloud_remote_bridge.dart';
import '../../../projection_native.dart'
    if (dart.library.js_interop) '../../../projection_web.dart'
    as projection;

class ProjectionState {
  final Entry? presented;
  final List<SlideData> slides;
  final int slideIndex;
  final bool blackout;
  final int slideTheme;
  final bool showTitle;
  final double aspect;
  final int? countdownEndsAt;
  final String marqueeText;
  final String? videoBackgroundPath;
  final int maxLines;
  final bool repeatChorus;

  const ProjectionState({
    this.presented,
    this.slides = const [],
    this.slideIndex = 0,
    this.blackout = false,
    this.slideTheme = 0,
    this.showTitle = true,
    this.aspect = 16 / 9,
    this.countdownEndsAt,
    this.marqueeText = '',
    this.videoBackgroundPath,
    this.maxLines = 4,
    this.repeatChorus = true,
  });

  ProjectionState copyWith({
    Entry? presented,
    List<SlideData>? slides,
    int? slideIndex,
    bool? blackout,
    int? slideTheme,
    bool? showTitle,
    double? aspect,
    int? countdownEndsAt,
    bool clearCountdown = false,
    String? marqueeText,
    String? videoBackgroundPath,
    bool clearVideo = false,
    int? maxLines,
    bool? repeatChorus,
  }) {
    return ProjectionState(
      presented: presented ?? this.presented,
      slides: slides ?? this.slides,
      slideIndex: slideIndex ?? this.slideIndex,
      blackout: blackout ?? this.blackout,
      slideTheme: slideTheme ?? this.slideTheme,
      showTitle: showTitle ?? this.showTitle,
      aspect: aspect ?? this.aspect,
      countdownEndsAt: clearCountdown
          ? null
          : (countdownEndsAt ?? this.countdownEndsAt),
      marqueeText: marqueeText ?? this.marqueeText,
      videoBackgroundPath: clearVideo
          ? null
          : (videoBackgroundPath ?? this.videoBackgroundPath),
      maxLines: maxLines ?? this.maxLines,
      repeatChorus: repeatChorus ?? this.repeatChorus,
    );
  }

  Map<String, dynamic> toJson() => {
        if (presented != null) 'presented': presented!.toJson(),
        'slides': slides.map((s) => s.toJson()).toList(),
        'slideIndex': slideIndex,
        'blackout': blackout,
        'slideTheme': slideTheme,
        'showTitle': showTitle,
        'aspect': aspect,
        'countdownEndsAt': countdownEndsAt,
        'marqueeText': marqueeText,
        'videoBackgroundPath': videoBackgroundPath,
        'maxLines': maxLines,
        'repeatChorus': repeatChorus,
      };

  factory ProjectionState.fromJson(Map<String, dynamic> json) {
    return ProjectionState(
      presented: json['presented'] != null
          ? Entry.fromJson(Map<String, dynamic>.from(json['presented']))
          : null,
      slides: (json['slides'] as List?)
              ?.map((s) => SlideData.fromJson(Map<String, dynamic>.from(s)))
              .toList() ??
          [],
      slideIndex: json['slideIndex'] as int? ?? 0,
      blackout: json['blackout'] as bool? ?? false,
      slideTheme: json['slideTheme'] as int? ?? 0,
      showTitle: json['showTitle'] as bool? ?? true,
      aspect: (json['aspect'] as num?)?.toDouble() ?? (16 / 9),
      countdownEndsAt: json['countdownEndsAt'] as int?,
      marqueeText: json['marqueeText'] as String? ?? '',
      videoBackgroundPath: json['videoBackgroundPath'] as String?,
      maxLines: json['maxLines'] as int? ?? 4,
      repeatChorus: json['repeatChorus'] as bool? ?? true,
    );
  }
}

final projectionProvider =
    NotifierProvider<ProjectionNotifier, ProjectionState>(
      () => ProjectionNotifier(),
    );

class ProjectionNotifier extends Notifier<ProjectionState> {
  ProjectionNotifier() {
    final session = Uri.base.queryParameters['session'];
    if (session != null && session.isNotEmpty) {
      CloudRemoteBridge.listenState(session).listen((data) {
        if (data.containsKey('slide')) {
          // Legacy format fallback just in case
          state = ProjectionState.fromJson(data);
        } else {
          state = ProjectionState.fromJson(data);
        }
      });
    } else {
      projection.initializeProjection(const []).then((mode) {
        if (mode != 'main') {
          projection.listenOutput((data) {
            state = ProjectionState.fromJson(data);
          });
        }
      });
    }
  }

  @override
  ProjectionState build() {
    return const ProjectionState();
  }

  SlideData get currentSlide => state.slides.isEmpty
      ? const SlideData(
          'Conferencia General de la Iglesia de Dios',
          '',
          'Bienvenidos',
        )
      : state.slides[state.slideIndex];

  Map<String, dynamic> get outputState => state.toJson();

  Future<void> syncOutput() async {
    try {
      await projection.sendOutput(outputState);
    } catch (_) {}
  }

  void present(Entry entry) {
    _updateSlidesFor(entry);
  }

  void _updateSlidesFor(Entry entry) {
    final slides = makeSlides(
      entry,
      maxLines: state.maxLines,
      columns: state.aspect < 1.5 ? 30 : 38,
      repeatChorus: state.repeatChorus,
    );
    state = state.copyWith(
      presented: entry,
      slides: slides,
      slideIndex: 0,
      blackout: false,
    );
    syncOutput();
  }

  void refreshSlides() {
    if (state.presented != null) {
      _updateSlidesFor(state.presented!);
    }
  }

  void setAspect(double aspect) {
    state = state.copyWith(aspect: aspect);
    refreshSlides();
  }

  void setMaxLines(int lines) {
    state = state.copyWith(maxLines: lines);
    refreshSlides();
  }

  void setRepeatChorus(bool repeatChorus) {
    state = state.copyWith(repeatChorus: repeatChorus);
    refreshSlides();
  }

  void toggleBlack() {
    state = state.copyWith(blackout: !state.blackout);
    syncOutput();
  }

  void setSlideTheme(int theme) {
    state = state.copyWith(slideTheme: theme);
    syncOutput();
  }

  void toggleShowTitle() {
    state = state.copyWith(showTitle: !state.showTitle);
    syncOutput();
  }

  void setCountdown(int? endsAt) {
    state = state.copyWith(
      countdownEndsAt: endsAt,
      clearCountdown: endsAt == null,
    );
    syncOutput();
  }

  void setMarquee(String text) {
    state = state.copyWith(marqueeText: text);
    syncOutput();
  }

  void setVideoBackground(String? path) {
    state = state.copyWith(
      videoBackgroundPath: path,
      clearVideo: path == null,
    );
    syncOutput();
  }

  void clearPresentation() {
    state = const ProjectionState();
    syncOutput();
  }

  void move(int delta) {
    if (state.slides.isEmpty) return;
    final newIndex = (state.slideIndex + delta).clamp(
      0,
      state.slides.length - 1,
    );
    if (newIndex != state.slideIndex) {
      state = state.copyWith(slideIndex: newIndex);
      syncOutput();
    }
  }

  void setSlideIndex(int index) {
    if (index >= 0 && index < state.slides.length) {
      state = state.copyWith(slideIndex: index);
      syncOutput();
    }
  }

}
