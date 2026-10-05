import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:marquee/marquee.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../appearance.dart';
import '../../../content.dart';
import '../../../projection_native.dart'
    if (dart.library.js_interop) '../../../projection_web.dart'
    as projection;
import '../providers/projection_provider.dart';

enum OverlayMode { lowerthird, strip, clean, fullscreen }

enum OverlayPosition { bottom, top }

enum OverlayBackground { transparent, green, blue, dark, black }

enum OverlayTextSize { normal, large, compact }

class StreamOverlayScreen extends ConsumerStatefulWidget {
  final OverlayMode? initialMode;
  final OverlayBackground? initialBackground;

  const StreamOverlayScreen({
    super.key,
    this.initialMode,
    this.initialBackground,
  });

  @override
  ConsumerState<StreamOverlayScreen> createState() => _StreamOverlayScreenState();
}

class _StreamOverlayScreenState extends ConsumerState<StreamOverlayScreen> {
  late OverlayMode _mode;
  late OverlayBackground _background;
  OverlayPosition _position = OverlayPosition.bottom;
  OverlayTextSize _textSize = OverlayTextSize.normal;
  bool _showLiveBadge = false;

  bool _showControls = false;
  Timer? _hideControlsTimer;
  bool _isHoveringControls = false;

  @override
  void initState() {
    super.initState();
    _parseUrlParameters();
    _resetControlsTimer();
  }

  void _parseUrlParameters() {
    final params = Uri.base.queryParameters;

    // Background
    final bgParam = params['bg']?.toLowerCase();
    if (bgParam == 'green') {
      _background = OverlayBackground.green;
    } else if (bgParam == 'blue') {
      _background = OverlayBackground.blue;
    } else if (bgParam == 'dark') {
      _background = OverlayBackground.dark;
    } else if (bgParam == 'black') {
      _background = OverlayBackground.black;
    } else {
      _background = widget.initialBackground ?? OverlayBackground.transparent;
    }

    // Mode
    final modeParam = params['mode']?.toLowerCase();
    if (modeParam == 'strip') {
      _mode = OverlayMode.strip;
    } else if (modeParam == 'clean' || modeParam == 'text') {
      _mode = OverlayMode.clean;
    } else if (modeParam == 'fullscreen' || modeParam == 'full') {
      _mode = OverlayMode.fullscreen;
    } else {
      _mode = widget.initialMode ?? OverlayMode.lowerthird;
    }

    // Position
    final posParam = (params['pos'] ?? params['position'])?.toLowerCase();
    if (posParam == 'top') {
      _position = OverlayPosition.top;
    } else {
      _position = OverlayPosition.bottom;
    }

    // Live Badge
    final liveParam = params['live']?.toLowerCase();
    if (liveParam == '1' || liveParam == 'true') {
      _showLiveBadge = true;
    }

    // Size
    final sizeParam = params['size']?.toLowerCase();
    if (sizeParam == 'large') {
      _textSize = OverlayTextSize.large;
    } else if (sizeParam == 'compact') {
      _textSize = OverlayTextSize.compact;
    } else {
      _textSize = OverlayTextSize.normal;
    }
  }

  void _resetControlsTimer() {
    _hideControlsTimer?.cancel();
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isHoveringControls) {
        setState(() => _showControls = false);
      }
    });
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  Color get _resolvedBackgroundColor {
    switch (_background) {
      case OverlayBackground.transparent:
        return Colors.transparent;
      case OverlayBackground.green:
        return const Color(0xFF00FF00); // Standard Green Screen Chroma
      case OverlayBackground.blue:
        return const Color(0xFF0000FF); // Standard Blue Screen Chroma
      case OverlayBackground.dark:
        return const Color(0xFF0A0F1D);
      case OverlayBackground.black:
        return Colors.black;
    }
  }

  double get _fontSize {
    switch (_textSize) {
      case OverlayTextSize.compact:
        return _mode == OverlayMode.fullscreen ? 32 : 24;
      case OverlayTextSize.large:
        return _mode == OverlayMode.fullscreen ? 48 : 34;
      case OverlayTextSize.normal:
        return _mode == OverlayMode.fullscreen ? 40 : 28;
    }
  }

  String get _currentObsUrl {
    final baseUri = Uri.base;
    final query = <String, String>{
      'overlay': '1',
      if (_background != OverlayBackground.transparent)
        'bg': _background.name,
      if (_mode != OverlayMode.lowerthird)
        'mode': _mode.name,
      if (_position != OverlayPosition.bottom)
        'pos': _position.name,
      if (_textSize != OverlayTextSize.normal)
        'size': _textSize.name,
      if (_showLiveBadge)
        'live': '1',
    };
    return baseUri.replace(queryParameters: query, fragment: '').toString();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(projectionProvider);
    final blackout = state.blackout;
    final slide = ref.read(projectionProvider.notifier).currentSlide;

    final marqueeText = state.marqueeText;
    final hasMarquee = marqueeText.trim().isNotEmpty && !blackout;

    final hasContent = slide.text.trim().isNotEmpty &&
        slide.text.trim() != 'Esperando contenido' &&
        !blackout;

    return MouseRegion(
      onHover: (_) => _resetControlsTimer(),
      child: Scaffold(
        backgroundColor: _resolvedBackgroundColor,
        body: Stack(
          children: [
            // Live Stream Watermark / Logo (If enabled)
            if (_showLiveBadge)
              Positioned(
                top: 24,
                left: 28,
                child: _buildLiveBadge(),
              ),

            // Main Overlay Content (Animated)
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: hasContent ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOut,
                child: hasContent
                    ? _buildContentLayout(context, slide)
                    : const SizedBox.shrink(),
              ),
            ),

            // Live Stream Ticker / Cintillo de Avisos
            if (hasMarquee)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildMarqueeBar(marqueeText.trim()),
              ),

            // Top-right Discreet Floating Control Bar (Auto-hides on inactivity)
            Positioned(
              top: 16,
              right: 16,
              child: MouseRegion(
                onEnter: (_) {
                  _isHoveringControls = true;
                  _hideControlsTimer?.cancel();
                },
                onExit: (_) {
                  _isHoveringControls = false;
                  _resetControlsTimer();
                },
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: _buildFloatingControls(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFEF4444),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'EN VIVO · CGDI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarqueeBar(String text) {
    return Container(
      height: 44,
      width: double.infinity,
      color: Colors.black.withValues(alpha: 0.88),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Marquee(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        blankSpace: 96,
        velocity: 38,
        startPadding: 32,
        pauseAfterRound: const Duration(milliseconds: 600),
      ),
    );
  }

  Widget _buildContentLayout(BuildContext context, SlideData slide) {
    switch (_mode) {
      case OverlayMode.lowerthird:
        return _buildLowerThird(context, slide);
      case OverlayMode.strip:
        return _buildFullStrip(context, slide);
      case OverlayMode.clean:
        return _buildCleanText(context, slide);
      case OverlayMode.fullscreen:
        return _buildFullscreen(context, slide);
    }
  }

  /// Estilo Lower Third (Tercio Inferior con tarjeta flotante elegante)
  Widget _buildLowerThird(BuildContext context, SlideData slide) {
    final isBible = slide.label.toLowerCase().contains('cap') ||
        slide.label.toLowerCase().contains('vers') ||
        slide.title.toLowerCase().contains('cap') ||
        RegExp(r'\d+:\d+').hasMatch(slide.title);

    final isTop = _position == OverlayPosition.top;

    return Align(
      alignment: isTop ? Alignment.topCenter : Alignment.bottomCenter,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        margin: EdgeInsets.only(
          left: 48,
          right: 48,
          top: isTop ? 42 : 0,
          bottom: isTop ? 0 : 42,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black.withValues(alpha: 0.88),
              const Color(0xFF0F172A).withValues(alpha: 0.92),
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 28,
              offset: Offset(0, isTop ? -8 : 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Accent color side bar
              Container(
                width: 7,
                color: isBible ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderBadges(slide, isBible),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: Offset(0.0, isTop ? -0.12 : 0.12),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          slide.text.trim(),
                          key: ValueKey(slide.text),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: _fontSize,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.25,
                            height: 1.35,
                            fontFamily: 'CGID',
                            shadows: const [
                              Shadow(
                                offset: Offset(-1.5, -1.5),
                                color: Colors.black,
                                blurRadius: 3,
                              ),
                              Shadow(
                                offset: Offset(1.5, -1.5),
                                color: Colors.black,
                                blurRadius: 3,
                              ),
                              Shadow(
                                offset: Offset(-1.5, 1.5),
                                color: Colors.black,
                                blurRadius: 3,
                              ),
                              Shadow(
                                offset: Offset(1.5, 1.5),
                                color: Colors.black,
                                blurRadius: 3,
                              ),
                              Shadow(
                                offset: Offset(0, 3),
                                color: Colors.black87,
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Estilo Texto Limpio (Solo letras flotantes con contorno y sombra gruesa, sin caja)
  Widget _buildCleanText(BuildContext context, SlideData slide) {
    final isBible = slide.label.toLowerCase().contains('cap') ||
        slide.label.toLowerCase().contains('vers') ||
        slide.title.toLowerCase().contains('cap') ||
        RegExp(r'\d+:\d+').hasMatch(slide.title);

    final isTop = _position == OverlayPosition.top;

    return Align(
      alignment: isTop ? Alignment.topCenter : Alignment.bottomCenter,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        margin: EdgeInsets.only(
          left: 48,
          right: 48,
          top: isTop ? 42 : 0,
          bottom: isTop ? 0 : 42,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildHeaderBadges(slide, isBible),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: Text(
                slide.text.trim(),
                key: ValueKey(slide.text),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _fontSize + 2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  height: 1.35,
                  shadows: const [
                    Shadow(offset: Offset(-2, -2), color: Colors.black, blurRadius: 4),
                    Shadow(offset: Offset(2, -2), color: Colors.black, blurRadius: 4),
                    Shadow(offset: Offset(-2, 2), color: Colors.black, blurRadius: 4),
                    Shadow(offset: Offset(2, 2), color: Colors.black, blurRadius: 4),
                    Shadow(offset: Offset(0, 4), color: Colors.black, blurRadius: 10),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Estilo Cintillo Completo (Abarca todo el ancho de la pantalla)
  Widget _buildFullStrip(BuildContext context, SlideData slide) {
    final isBible = slide.label.toLowerCase().contains('cap') ||
        slide.label.toLowerCase().contains('vers') ||
        slide.title.toLowerCase().contains('cap') ||
        RegExp(r'\d+:\d+').hasMatch(slide.title);

    final isTop = _position == OverlayPosition.top;

    return Align(
      alignment: isTop ? Alignment.topCenter : Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.88),
          border: Border(
            top: isTop
                ? BorderSide.none
                : BorderSide(
                    color: isBible ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8),
                    width: 3.5,
                  ),
            bottom: isTop
                ? BorderSide(
                    color: isBible ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8),
                    width: 3.5,
                  )
                : BorderSide.none,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 20,
              offset: Offset(0, isTop ? 4 : -4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderBadges(slide, isBible),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: Text(
                slide.text.trim(),
                key: ValueKey(slide.text),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.25,
                  height: 1.35,
                  shadows: const [
                    Shadow(offset: Offset(-1.5, -1.5), color: Colors.black, blurRadius: 3),
                    Shadow(offset: Offset(1.5, -1.5), color: Colors.black, blurRadius: 3),
                    Shadow(offset: Offset(-1.5, 1.5), color: Colors.black, blurRadius: 3),
                    Shadow(offset: Offset(1.5, 1.5), color: Colors.black, blurRadius: 3),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Estilo Pantalla Completa Centrada (Ideal para interludios y versículos principales)
  Widget _buildFullscreen(BuildContext context, SlideData slide) {
    final isBible = slide.label.toLowerCase().contains('cap') ||
        slide.label.toLowerCase().contains('vers') ||
        slide.title.toLowerCase().contains('cap') ||
        RegExp(r'\d+:\d+').hasMatch(slide.title);

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        margin: const EdgeInsets.all(48),
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.black.withValues(alpha: 0.85),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeaderBadges(slide, isBible),
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: Text(
                slide.text.trim(),
                key: ValueKey(slide.text),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  height: 1.45,
                  shadows: const [
                    Shadow(offset: Offset(-2, -2), color: Colors.black, blurRadius: 4),
                    Shadow(offset: Offset(2, -2), color: Colors.black, blurRadius: 4),
                    Shadow(offset: Offset(-2, 2), color: Colors.black, blurRadius: 4),
                    Shadow(offset: Offset(2, 2), color: Colors.black, blurRadius: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBadges(SlideData slide, bool isBible) {
    final hasTitle = slide.title.trim().isNotEmpty && slide.title != globalChurchName;
    final hasLabel = slide.label.trim().isNotEmpty;

    if (!hasTitle && !hasLabel) return const SizedBox.shrink();

    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (hasTitle)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isBible
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
                  : const Color(0xFF38BDF8).withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isBible
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
                    : const Color(0xFF38BDF8).withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isBible ? Icons.menu_book : Icons.music_note,
                  size: 15,
                  color: isBible ? const Color(0xFFFCD34D) : const Color(0xFF7DD3FC),
                ),
                const SizedBox(width: 6),
                Text(
                  slide.title.trim(),
                  style: TextStyle(
                    color: isBible ? const Color(0xFFFCD34D) : const Color(0xFF7DD3FC),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        if (hasLabel)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Text(
              slide.label.trim().toUpperCase(),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFloatingControls(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sensors, color: Color(0xFF38BDF8), size: 18),
          const SizedBox(width: 8),
          const Text(
            'Salida OBS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 12),
          // Formato dropdown
          DropdownButton<OverlayMode>(
            value: _mode,
            dropdownColor: const Color(0xFF1E293B),
            underline: const SizedBox.shrink(),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
            style: const TextStyle(color: Colors.white, fontSize: 12),
            onChanged: (val) {
              if (val != null) setState(() => _mode = val);
            },
            items: const [
              DropdownMenuItem(
                value: OverlayMode.lowerthird,
                child: Text('Tercio Inferior'),
              ),
              DropdownMenuItem(
                value: OverlayMode.strip,
                child: Text('Cintillo Ancho'),
              ),
              DropdownMenuItem(
                value: OverlayMode.clean,
                child: Text('Texto Limpio'),
              ),
              DropdownMenuItem(
                value: OverlayMode.fullscreen,
                child: Text('Centrado'),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Posición
          DropdownButton<OverlayPosition>(
            value: _position,
            dropdownColor: const Color(0xFF1E293B),
            underline: const SizedBox.shrink(),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
            style: const TextStyle(color: Colors.white, fontSize: 12),
            onChanged: (val) {
              if (val != null) setState(() => _position = val);
            },
            items: const [
              DropdownMenuItem(
                value: OverlayPosition.bottom,
                child: Text('Abajo'),
              ),
              DropdownMenuItem(
                value: OverlayPosition.top,
                child: Text('Arriba'),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Fondo dropdown
          DropdownButton<OverlayBackground>(
            value: _background,
            dropdownColor: const Color(0xFF1E293B),
            underline: const SizedBox.shrink(),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
            style: const TextStyle(color: Colors.white, fontSize: 12),
            onChanged: (val) {
              if (val != null) setState(() => _background = val);
            },
            items: const [
              DropdownMenuItem(
                value: OverlayBackground.transparent,
                child: Text('Transparente (OBS)'),
              ),
              DropdownMenuItem(
                value: OverlayBackground.green,
                child: Text('Verde Chroma (#00FF00)'),
              ),
              DropdownMenuItem(
                value: OverlayBackground.blue,
                child: Text('Azul Chroma (#0000FF)'),
              ),
              DropdownMenuItem(
                value: OverlayBackground.dark,
                child: Text('Fondo Oscuro'),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Copy URL button
          IconButton(
            tooltip: 'Copiar Enlace para OBS Studio',
            icon: const Icon(Icons.copy, color: Colors.white70, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _currentObsUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Enlace para OBS copiado al portapapeles.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          // Fullscreen toggle
          IconButton(
            tooltip: 'Pantalla completa (F11)',
            icon: const Icon(Icons.fullscreen, color: Colors.white70, size: 20),
            onPressed: () => projection.fullScreen(true),
          ),
        ],
      ),
    );
  }
}
