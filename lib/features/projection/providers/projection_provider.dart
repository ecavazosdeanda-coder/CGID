import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../content.dart';
import '../../../media_store.dart';
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
  final int aspect;
  final int? countdownEndsAt;
  final String marqueeText;
  final String? videoBackgroundPath;

  const ProjectionState({
    this.presented,
    this.slides = const [],
    this.slideIndex = 0,
    this.blackout = false,
    this.slideTheme = 0,
    this.showTitle = true,
    this.aspect = 0,
    this.countdownEndsAt,
    this.marqueeText = '',
    this.videoBackgroundPath,
  });

  ProjectionState copyWith({
    Entry? presented,
    List<SlideData>? slides,
    int? slideIndex,
    bool? blackout,
    int? slideTheme,
    bool? showTitle,
    int? aspect,
    int? countdownEndsAt,
    bool clearCountdown = false,
    String? marqueeText,
    String? videoBackgroundPath,
    bool clearVideo = false,
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
    );
  }
}

final projectionProvider =
    NotifierProvider<ProjectionNotifier, ProjectionState>(
      () => ProjectionNotifier(),
    );

class ProjectionNotifier extends Notifier<ProjectionState> {
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

  Map<String, dynamic> get outputState {
    final nextSlide =
        (state.slides.isNotEmpty && state.slideIndex + 1 < state.slides.length)
        ? state.slides[state.slideIndex + 1]
        : null;
    return {
      'slide': {
        ...currentSlide.toJson(),
        if (currentSlide.mediaId != null &&
            MediaStore.cache.containsKey(currentSlide.mediaId))
          'imageData': base64Encode(MediaStore.cache[currentSlide.mediaId]!),
      },
      if (nextSlide != null) 'nextSlide': nextSlide.toJson(),
      'blackout': state.blackout,
      'theme': state.slideTheme,
      'showTitle': state.showTitle,
      'aspect': state.aspect,
      'countdownEndsAt': state.countdownEndsAt,
      'marqueeText': state.marqueeText,
      'videoBackgroundPath': state.videoBackgroundPath,
    };
  }

  Future<void> syncOutput() async {
    try {
      await projection.sendOutput(outputState);
    } catch (_) {}
  }

  void present(Entry entry) {
    final slides = makeSlides(entry);
    state = state.copyWith(
      presented: entry,
      slides: slides,
      slideIndex: 0,
      blackout: false,
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

  void toggleBlackout() {
    state = state.copyWith(blackout: !state.blackout);
    syncOutput();
  }

  void setBlackout(bool blackout) {
    state = state.copyWith(blackout: blackout);
    syncOutput();
  }

  void updateTheme(int theme) {
    state = state.copyWith(slideTheme: theme);
    syncOutput();
  }

  void toggleTitle() {
    state = state.copyWith(showTitle: !state.showTitle);
    syncOutput();
  }

  void setVideoBackground(String? path) {
    state = state.copyWith(videoBackgroundPath: path, clearVideo: path == null);
    syncOutput();
  }

  void setMarqueeText(String text) {
    state = state.copyWith(marqueeText: text);
    syncOutput();
  }

  void startCountdown(Duration duration) {
    final endsAt = DateTime.now().add(duration).millisecondsSinceEpoch;
    state = state.copyWith(countdownEndsAt: endsAt);
    syncOutput();
  }

  void clearCountdown() {
    state = state.copyWith(clearCountdown: true);
    syncOutput();
  }
}
