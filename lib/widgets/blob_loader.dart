import 'dart:ui';
import 'package:flutter/material.dart';

/// A native Flutter implementation of the UIverse "Blob Loader" by vikramsinghnegi.
///
/// Features:
/// - Two rounded squares revolving around four corners (top-left, top-right,
///   bottom-right, bottom-left) in a 2-second continuous loop.
/// - 180° (1-second) phase shift between the two boxes.
/// - Visual gooey liquid "blob" effect using Skia alpha contrast and gaussian blur filters.
/// - Fully proportional scaling based on reference dimensions (112px container,
///   44.8px boxes, 11.2px padding, 5.6px blur).
/// - Respects [MediaQuery.maybeDisableAnimationsOf(context)] for reduced motion accessibility.
/// - Minimalist appearance with no circular spinner or surrounding rings.
class BlobLoader extends StatefulWidget {
  /// The outer dimension (width and height) of the loader container.
  /// All internal box sizes, blur, padding, and travel distances scale proportionally.
  final double size;

  /// Custom color for the two boxes. If null, defaults to `#474BFF`.
  final Color? color;

  /// Total duration for a full 4-corner cyclical revolution. Defaults to 2 seconds.
  final Duration duration;

  /// Accessibility semantic label.
  final String? semanticLabel;

  const BlobLoader({
    super.key,
    this.size = 80.0,
    this.color,
    this.duration = const Duration(milliseconds: 2000),
    this.semanticLabel = 'Memuat dokumen...',
  });

  /// Exposes the 4-corner trajectory calculation for testing and geometry verification.
  static Offset calculatePosition(double t, double travel) =>
      _BlobLoaderState.calculatePosition(t, travel);

  @override
  State<BlobLoader> createState() => _BlobLoaderState();
}

class _BlobLoaderState extends State<BlobLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Alpha contrast matrix for gooey metaball effect:
  // Multiplies alpha by 18 and subtracts 7*255 (1785), creating a sharp threshold
  // across blurred overlapping boundaries regardless of background color.
  static const List<double> _gooeyMatrix = <double>[
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    18,
    -1785,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _controller.repeat();
  }

  @override
  void didUpdateWidget(BlobLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
      if (_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Calculates the (x, y) offset for a box at normalized time [t] in [0, 1).
  /// [travel] is the distance between top-left and bottom-right corner positions.
  static Offset calculatePosition(double t, double travel) {
    final double progress = (t % 1.0 + 1.0) % 1.0;

    if (progress < 0.25) {
      // 0% -> 25%: (0, 0) -> (travel, 0)
      final double s = progress / 0.25;
      final double curved = Curves.easeInOut.transform(s);
      return Offset(travel * curved, 0.0);
    } else if (progress < 0.50) {
      // 25% -> 50%: (travel, 0) -> (travel, travel)
      final double s = (progress - 0.25) / 0.25;
      final double curved = Curves.easeInOut.transform(s);
      return Offset(travel, travel * curved);
    } else if (progress < 0.75) {
      // 50% -> 75%: (travel, travel) -> (0, travel)
      final double s = (progress - 0.50) / 0.25;
      final double curved = Curves.easeInOut.transform(s);
      return Offset(travel * (1.0 - curved), travel);
    } else {
      // 75% -> 100%: (0, travel) -> (0, 0)
      final double s = (progress - 0.75) / 0.25;
      final double curved = Curves.easeInOut.transform(s);
      return Offset(0.0, travel * (1.0 - curved));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // Proportional dimensions based on CSS UIverse:
    // Container: 112px, Box: 44.8px (40%), Padding: 11.2px (10%), Blur: 5.6px (5%)
    final double boxSize = widget.size * (44.8 / 112.0);
    final double padding = widget.size * (11.2 / 112.0);
    final double travel = widget.size * (44.8 / 112.0);
    final double blurSigma = widget.size * (5.6 / 112.0);
    final double borderRadius = boxSize * 0.18;

    final Color effectiveColor = widget.color ?? const Color(0xFF474BFF);

    Widget buildBox(Offset offset, Key key) {
      return Positioned(
        key: key,
        left: padding + offset.dx,
        top: padding + offset.dy,
        child: Container(
          width: boxSize,
          height: boxSize,
          decoration: BoxDecoration(
            color: effectiveColor,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
      );
    }

    Widget content;
    if (disableAnimations) {
      content = SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          children: [
            buildBox(Offset.zero, const Key('blob_box_1')),
            buildBox(Offset(travel, travel), const Key('blob_box_2')),
          ],
        ),
      );
    } else {
      content = AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final double t1 = _controller.value;
          // Box 2 has a -1s delay in a 2s cycle (0.5 phase offset)
          final double t2 = (t1 + 0.5) % 1.0;

          final Offset pos1 = calculatePosition(t1, travel);
          final Offset pos2 = calculatePosition(t2, travel);

          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              children: [
                buildBox(pos1, const Key('blob_box_1')),
                buildBox(pos2, const Key('blob_box_2')),
              ],
            ),
          );
        },
      );
    }

    return Semantics(
      label: widget.semanticLabel,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(_gooeyMatrix),
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
          child: content,
        ),
      ),
    );
  }
}
