import 'package:flutter/material.dart';
import '../theme/scichat_theme.dart';

/// A reusable academic skeleton loading widget for AI Summary bottom sheets.
///
/// Designed to reflect the structure of a scientific paper summary:
/// multiple distinct sections with headings and multi-line body paragraphs.
/// Uses a subtle shimmer sweep and conforms to SCIChat's restrained academic aesthetic.
class SummarySkeleton extends StatefulWidget {
  /// Optional [ScrollController] passed from [DraggableScrollableSheet] to maintain
  /// native drag and scroll gestures during the loading state.
  final ScrollController? controller;

  /// Optional override to disable animation (e.g. for golden tests or accessibility).
  final bool? animate;

  const SummarySkeleton({
    super.key,
    this.controller,
    this.animate,
  });

  @override
  State<SummarySkeleton> createState() => _SummarySkeletonState();
}

class _SummarySkeletonState extends State<SummarySkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = widget.animate == false ||
        MediaQuery.maybeOf(context)?.disableAnimations == true;

    final baseColor = context.colors.surface2;
    // Harmonious highlight color between surface2 and surface3
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlightColor = isDark
        ? Color.lerp(context.colors.surface2, context.colors.surface3, 0.75)!
        : Color.lerp(context.colors.surface2, Colors.white, 0.65)!;

    final content = SingleChildScrollView(
      controller: widget.controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section 1: Overview / What was done
          _SkeletonHeading(widthFactor: 0.38),
          SizedBox(height: 10),
          _SkeletonParagraph(
            widths: [1.0, 0.92, 0.64],
          ),
          SizedBox(height: 24),

          // Section 2: Methodology
          _SkeletonHeading(widthFactor: 0.30),
          SizedBox(height: 10),
          _SkeletonParagraph(
            widths: [1.0, 0.95, 0.48],
          ),
          SizedBox(height: 24),

          // Section 3: Key Findings
          _SkeletonHeading(widthFactor: 0.34),
          SizedBox(height: 10),
          _SkeletonParagraph(
            widths: [0.98, 1.0, 0.72],
          ),
          SizedBox(height: 24),

          // Section 4: Target Audience / Implications
          _SkeletonHeading(widthFactor: 0.44),
          SizedBox(height: 10),
          _SkeletonParagraph(
            widths: [1.0, 0.58],
          ),
        ],
      ),
    );

    // Screen reader accessibility: announce loading state clearly once without
    // reading out every individual placeholder bar.
    return Semantics(
      label: 'Memuat ringkasan AI...',
      container: true,
      excludeSemantics: true,
      child: disableAnimations
          ? _SkeletonScope(
              baseColor: baseColor,
              highlightColor: highlightColor,
              shimmerPercent: 0.0,
              child: content,
            )
          : AnimatedBuilder(
              animation: _animController,
              builder: (context, _) {
                return _SkeletonScope(
                  baseColor: baseColor,
                  highlightColor: highlightColor,
                  shimmerPercent: _animController.value,
                  child: content,
                );
              },
            ),
    );
  }
}

/// InheritedWidget providing theme colors and shimmer animation progress to child skeleton bars.
class _SkeletonScope extends InheritedWidget {
  final Color baseColor;
  final Color highlightColor;
  final double shimmerPercent;

  const _SkeletonScope({
    required this.baseColor,
    required this.highlightColor,
    required this.shimmerPercent,
    required super.child,
  });

  static _SkeletonScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_SkeletonScope>();
  }

  @override
  bool updateShouldNotify(_SkeletonScope oldWidget) {
    return oldWidget.shimmerPercent != shimmerPercent ||
        oldWidget.baseColor != baseColor ||
        oldWidget.highlightColor != highlightColor;
  }
}

/// A section heading placeholder bar with varied width and rounded corners.
class _SkeletonHeading extends StatelessWidget {
  final double widthFactor;

  const _SkeletonHeading({required this.widthFactor});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: const _SkeletonBox(
        height: 16,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    );
  }
}

/// A paragraph placeholder composed of multiple lines with varied widths.
class _SkeletonParagraph extends StatelessWidget {
  final List<double> widths;

  const _SkeletonParagraph({required this.widths});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < widths.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: widths[i],
            child: const _SkeletonBox(
              height: 12,
              borderRadius: BorderRadius.all(Radius.circular(3)),
            ),
          ),
        ],
      ],
    );
  }
}

/// Individual skeleton box rendering with shimmering gradient sweep.
class _SkeletonBox extends StatelessWidget {
  final double height;
  final BorderRadius borderRadius;

  const _SkeletonBox({
    required this.height,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final scope = _SkeletonScope.of(context);
    final baseColor = scope?.baseColor ?? context.colors.surface2;
    final highlightColor = scope?.highlightColor ?? context.colors.surface3;
    final shimmerPercent = scope?.shimmerPercent ?? 0.0;

    // LinearGradient with sliding sweep
    final sweepGradient = LinearGradient(
      begin: const Alignment(-1.5, -0.2),
      end: const Alignment(1.5, 0.2),
      colors: [
        baseColor,
        highlightColor,
        baseColor,
      ],
      stops: const [0.0, 0.5, 1.0],
      transform: _SlidingGradientTransform(slidePercent: shimmerPercent),
    );

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: sweepGradient,
      ),
    );
  }
}

/// Gradient transform to smoothly shift the shimmer highlight across each bar.
class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    // Translate from -bounds.width to +bounds.width * 2
    final translation = bounds.width * (slidePercent * 2.5 - 1.25);
    return Matrix4.translationValues(translation, 0.0, 0.0);
  }
}
