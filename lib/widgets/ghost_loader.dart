import 'package:flutter/material.dart';

class GhostLoader extends StatefulWidget {
  final double size;
  const GhostLoader({super.key, this.size = 32.0});

  @override
  State<GhostLoader> createState() => _GhostLoaderState();
}

class _GhostLoaderState extends State<GhostLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final isStateA = _controller.value < 0.5;
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _GhostPainter(isStateA: isStateA),
        );
      },
    );
  }
}

class _GhostPainter extends CustomPainter {
  final bool isStateA;
  _GhostPainter({required this.isStateA});

  // Matrix:
  // 0 = Empty
  // 1 = Body (Indigo #7E84FA)
  // 2 = Flicker 0 (Visible in State A)
  // 3 = Flicker 1 (Visible in State B)
  // 4 = Eye (Blue)
  // 5 = Peach (Pupil/Mouth #FCC78B)
  static const List<List<int>> _grid = [
    [0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0], // Row 0
    [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0], // Row 1
    [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0], // Row 2
    [0, 1, 1, 4, 4, 1, 1, 1, 1, 4, 4, 1, 1, 0], // Row 3
    [0, 1, 4, 4, 4, 4, 1, 1, 4, 4, 4, 4, 1, 0], // Row 4
    [0, 1, 4, 5, 5, 4, 1, 1, 4, 5, 5, 4, 1, 0], // Row 5
    [1, 1, 4, 5, 5, 4, 1, 1, 4, 5, 5, 4, 1, 1], // Row 6
    [1, 1, 1, 4, 4, 1, 1, 1, 1, 4, 4, 1, 1, 1], // Row 7
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], // Row 8
    [1, 1, 5, 5, 1, 1, 5, 5, 1, 1, 5, 5, 1, 1], // Row 9
    [1, 5, 1, 1, 5, 5, 1, 1, 5, 5, 1, 1, 5, 1], // Row 10
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], // Row 11
    [1, 1, 3, 1, 2, 1, 3, 3, 1, 2, 1, 3, 1, 1], // Row 12
    [2, 3, 3, 3, 2, 2, 3, 3, 2, 2, 0, 3, 3, 2], // Row 13
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double pixelSize = size.width / 14.0;
    
    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: isStateA ? 0.3 : 0.1)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, pixelSize * 1.5);
    
    // The shadow is at the bottom, an ellipse rotated in 3D (flat)
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height + pixelSize),
        width: size.width * 0.8,
        height: size.height * 0.2,
      ),
      shadowPaint,
    );

    // Ghost bounce offset
    final double yOffset = isStateA ? 0 : -pixelSize;

    final Paint paint = Paint();
    final Color indigo = const Color(0xFF7E84FA);
    final Color eyeBlue = Colors.blue.shade700;
    final Color peach = const Color(0xFFFCC78B);

    for (int y = 0; y < 14; y++) {
      for (int x = 0; x < 14; x++) {
        final int val = _grid[y][x];
        if (val == 0) continue;

        if (val == 1) {
          paint.color = indigo;
        } else if (val == 2) {
          if (!isStateA) continue;
          paint.color = indigo;
        } else if (val == 3) {
          if (isStateA) continue;
          paint.color = indigo;
        } else if (val == 4) {
          paint.color = eyeBlue;
        } else if (val == 5) {
          paint.color = peach;
        }

        canvas.drawRect(
          Rect.fromLTWH(x * pixelSize, y * pixelSize + yOffset, pixelSize, pixelSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GhostPainter oldDelegate) {
    return oldDelegate.isStateA != isStateA;
  }
}
