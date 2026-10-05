import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

import '../../../slide_view.dart';
import '../../../motion_background_view.dart';
import '../../../countdown.dart';
import '../../../glass.dart';
import '../providers/projection_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProjectionOutputView extends ConsumerWidget {
  final ProjectionState state;

  const ProjectionOutputView({super.key, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blackout = state.blackout;
    final videoPath = state.videoBackgroundPath;
    final hasVideo = !blackout && videoPath != null && videoPath.isNotEmpty;
    final marqueeText = state.marqueeText;
    final showMarquee = !blackout && marqueeText.trim().isNotEmpty;
    final slide = ref.read(projectionProvider.notifier).currentSlide;

    return CountdownOverlay(
      endsAt: state.countdownEndsAt,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasVideo) MotionBackgroundView(videoPath: videoPath),
          SlideView(
            slide: slide,
            blackout: blackout,
            theme: state.slideTheme,
            showTitle: state.showTitle,
            transparentBackground: hasVideo,
          ),
          if (showMarquee)
            Align(
              alignment: Alignment.bottomCenter,
              child: Semantics(
                label: 'Cintillo de proyección',
                liveRegion: true,
                child: Container(
                  height: 64,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  color: Colors.black.withValues(alpha: .78),
                  child: VisualEffectsScope.animationsEnabled(context)
                      ? Marquee(
                          text: marqueeText.trim(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w600,
                          ),
                          blankSpace: 96,
                          velocity: 42,
                          startPadding: 32,
                          pauseAfterRound: const Duration(milliseconds: 800),
                        )
                      : Center(
                          child: Text(
                            marqueeText.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
