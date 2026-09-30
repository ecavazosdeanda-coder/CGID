import 'package:flutter/material.dart';

import 'appearance.dart';

import 'dart:convert';

import 'media_store.dart';

import 'content.dart';
import 'glass.dart';

class SlideView extends StatelessWidget {
  final SlideData slide;
  final bool blackout, showTitle, transparentBackground;
  final int theme;
  const SlideView({
    super.key,
    required this.slide,
    this.blackout = false,
    this.showTitle = true,
    this.transparentBackground = false,
    this.theme = 0,
  });
  Color _getBackgroundColor(int t) {
    switch (t) {
      case 1:
        return Colors.black;
      case 2:
        return const Color(0xfffff8eb);
      case 3:
        return const Color(0xff0b291b); // Verde Esmeralda
      case 4:
        return const Color(0xff2b0c14); // Borgoña / Vino
      case 5:
        return const Color(0xff06101e); // Azul Noche Profundo
      default:
        return const Color(0xff102e48); // Azul CGID
    }
  }

  Color _getTextColor(int t) {
    switch (t) {
      case 2:
        return const Color(0xff132536);
      case 5:
        return const Color(0xffe2e8f0);
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: VisualEffectsScope.animationsEnabled(context)
        ? const Duration(milliseconds: 300)
        : Duration.zero,
    transitionBuilder: (child, animation) =>
        FadeTransition(opacity: animation, child: child),
    child: ColoredBox(
      key: ValueKey(
        '${slide.title}|${slide.label}|${slide.text}|${slide.mediaId}|$blackout|$theme|$showTitle|$transparentBackground',
      ),
      color: transparentBackground
          ? Colors.transparent
          : blackout ||
                theme == 1 ||
                slide.mediaId != null ||
                slide.imageData != null
          ? Colors.black
          : _getBackgroundColor(theme),
      child: blackout
          ? const SizedBox.expand()
          : slide.imageData != null
          ? Image.memory(
              base64Decode(slide.imageData!),
              fit: BoxFit.contain,
              gaplessPlayback: true,
            )
          : slide.mediaId != null
          ? FutureBuilder(
              future: MediaStore.get(slide.mediaId!),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'No se pudo cargar la página',
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Image.memory(
                  snapshot.data!,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                );
              },
            )
          : LayoutBuilder(
              builder: (context, box) {
                final color = _getTextColor(theme);
                return Padding(
                  padding: EdgeInsets.all(box.maxHeight * .07),
                  child: Column(
                    children: [
                      if (showTitle)
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color.withValues(alpha: .75),
                            fontSize: box.maxHeight * .033,
                          ),
                        ),
                      if (slide.text == 'Esperando contenido' ||
                          slide.text == 'Bienvenidos')
                        Padding(
                          padding: EdgeInsets.only(top: box.maxHeight * 0.05),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: globalChurchLogoAsset.startsWith('base64:')
                                ? Image.memory(
                                    base64Decode(
                                      globalChurchLogoAsset.substring(7),
                                    ),
                                    height: box.maxHeight * 0.25,
                                    errorBuilder: (c, e, s) => const SizedBox(),
                                  )
                                : Image.asset(
                                    globalChurchLogoAsset,
                                    height: box.maxHeight * 0.25,
                                    errorBuilder: (c, e, s) => const SizedBox(),
                                  ),
                          ),
                        ),
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              slide.text,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: color,
                                fontSize: box.maxHeight * .095,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        slide.label,
                        style: TextStyle(
                          color: color.withValues(alpha: .6),
                          fontSize: box.maxHeight * .025,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    ),
  );
}
