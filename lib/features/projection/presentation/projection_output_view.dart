import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:marquee/marquee.dart';
import '../../../appearance.dart';
import '../../../slide_view.dart';
import '../../../motion_background_view.dart';
import '../../../content.dart';
import '../../../countdown.dart';
import '../../../glass.dart';
class ProjectionOutputView extends StatelessWidget {
  final Map<String, dynamic> state;

  const ProjectionOutputView({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final blackout = state['blackout'] == true;
    final videoPath = state['videoBackgroundPath'] as String?;
    final hasVideo = !blackout && videoPath != null && videoPath.isNotEmpty;
    final marqueeText = state['marqueeText'] as String?;
    final showMarquee =
        !blackout && marqueeText != null && marqueeText.trim().isNotEmpty;
    final slideState = state['slide'];
    final slide = slideState is Map
        ? SlideData.fromJson(Map<String, dynamic>.from(slideState))
        : SlideData(globalChurchName, '', 'Esperando contenido');

    return CountdownOverlay(
      endsAt: state['countdownEndsAt'] as int?,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasVideo) MotionBackgroundView(videoPath: videoPath),
          SlideView(
            slide: slide,
            blackout: blackout,
            theme: state['theme'] as int? ?? 0,
            showTitle: state['showTitle'] != false,
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
