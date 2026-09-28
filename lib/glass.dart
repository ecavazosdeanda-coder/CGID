import 'dart:ui';

import 'package:flutter/material.dart';

enum VisualEffectsMode { full, reduced, solid }

final appVisualEffectsMode = ValueNotifier(VisualEffectsMode.full);

class VisualEffectsScope extends InheritedWidget {
  const VisualEffectsScope({
    super.key,
    required this.mode,
    required super.child,
  });

  final VisualEffectsMode mode;

  static VisualEffectsMode of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VisualEffectsScope>()?.mode ??
      VisualEffectsMode.full;

  static bool animationsEnabled(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    return of(context) == VisualEffectsMode.full &&
        !(media?.disableAnimations ?? false) &&
        !(media?.accessibleNavigation ?? false);
  }

  @override
  bool updateShouldNotify(VisualEffectsScope oldWidget) =>
      mode != oldWidget.mode;
}

@immutable
class GlassTheme extends ThemeExtension<GlassTheme> {
  const GlassTheme({
    required this.ambientColors,
    required this.surfaceColors,
    required this.borderColor,
    required this.navigationColors,
    required this.glowColor,
  });

  final List<Color> ambientColors;
  final List<Color> surfaceColors;
  final Color borderColor;
  final List<Color> navigationColors;
  final Color glowColor;

  static const light = GlassTheme(
    ambientColors: [Color(0xffd5e9df), Color(0xffe4eef4), Color(0xfff7f4ed)],
    surfaceColors: [Color(0xe8ffffff), Color(0xc9f1f7f5)],
    borderColor: Color(0xe6ffffff),
    navigationColors: [Color(0xff28545a), Color(0xff143344)],
    glowColor: Color(0x553aa99f),
  );

  static const dark = GlassTheme(
    ambientColors: [Color(0xff214d50), Color(0xff122938), Color(0xff0b1720)],
    surfaceColors: [Color(0xf028434e), Color(0xe0152b38)],
    borderColor: Color(0x29ffffff),
    navigationColors: [Color(0xff254c53), Color(0xff122b3a)],
    glowColor: Color(0x4038c6b8),
  );

  @override
  GlassTheme copyWith({
    List<Color>? ambientColors,
    List<Color>? surfaceColors,
    Color? borderColor,
    List<Color>? navigationColors,
    Color? glowColor,
  }) => GlassTheme(
    ambientColors: ambientColors ?? this.ambientColors,
    surfaceColors: surfaceColors ?? this.surfaceColors,
    borderColor: borderColor ?? this.borderColor,
    navigationColors: navigationColors ?? this.navigationColors,
    glowColor: glowColor ?? this.glowColor,
  );

  @override
  GlassTheme lerp(covariant GlassTheme? other, double t) {
    if (other == null) return this;
    return GlassTheme(
      ambientColors: [
        for (var i = 0; i < ambientColors.length; i++)
          Color.lerp(ambientColors[i], other.ambientColors[i], t)!,
      ],
      surfaceColors: [
        for (var i = 0; i < surfaceColors.length; i++)
          Color.lerp(surfaceColors[i], other.surfaceColors[i], t)!,
      ],
      borderColor: Color.lerp(borderColor, other.borderColor, t)!,
      navigationColors: [
        for (var i = 0; i < navigationColors.length; i++)
          Color.lerp(navigationColors[i], other.navigationColors[i], t)!,
      ],
      glowColor: Color.lerp(glowColor, other.glowColor, t)!,
    );
  }
}

/// Static ambient light: no animation timers or per-row blur layers.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final effects = VisualEffectsScope.of(context);
    final glass =
        Theme.of(context).extension<GlassTheme>() ??
        (dark ? GlassTheme.dark : GlassTheme.light);
    if (effects == VisualEffectsMode.solid) {
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xff0b1720) : const Color(0xffedf3f1),
        gradient: RadialGradient(
          center: const Alignment(-0.8, -0.9),
          radius: 1.7,
          colors: glass.ambientColors,
        ),
      ),
      child: child,
    );
  }
}

/// Use blur only for bounded chrome, never for individual scrolling rows.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 24,
    this.blur = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final effects = VisualEffectsScope.of(context);
    final accessible =
        (MediaQuery.maybeOf(context)?.highContrast ?? false) ||
        effects == VisualEffectsMode.solid;
    final glass =
        Theme.of(context).extension<GlassTheme>() ??
        (dark ? GlassTheme.dark : GlassTheme.light);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: accessible
              ? glass.surfaceColors
                    .map((color) => color.withValues(alpha: 1))
                    .toList()
              : glass.surfaceColors,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: glass.borderColor),
      ),
      child: Padding(padding: padding, child: child),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: blur && !accessible && effects == VisualEffectsMode.full
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: content,
            )
          : content,
    );
  }
}

class AmbientSectionHeader extends StatelessWidget {
  const AmbientSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return GlassSurface(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
          if (trailing == null) return heading;
          if (constraints.maxWidth < 560 || largeText) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [heading, const SizedBox(height: 16), trailing!],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 16),
              trailing!,
            ],
          );
        },
      ),
    );
  }
}

class OperationalBackground extends StatelessWidget {
  const OperationalBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(-0.8, -0.9),
        radius: 1.6,
        colors: [Color(0xff153b45), Color(0xff0d202b), Color(0xff081116)],
      ),
    ),
    child: child,
  );
}

class OperationalSurface extends StatelessWidget {
  const OperationalSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xf02a414b), Color(0xed132630)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0x2effffff)),
    ),
    child: Padding(padding: padding, child: child),
  );
}
