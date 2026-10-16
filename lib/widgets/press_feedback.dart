import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A lightweight, editorial micro-interaction widget that scales down
/// subtly when pressed and returns to normal size upon release or cancellation.
///
/// Designed to provide consistent, elegant touch feedback across SCIChat
/// without altering layout bounds, navigation heights, or delaying callbacks.
///
/// Respects [MediaQuery.disableAnimationsOf(context)] for accessibility / reduced motion.
class PressFeedback extends StatefulWidget {
  /// The interactive widget to receive press feedback.
  final Widget child;

  /// Optional tap callback. If provided, [PressFeedback] uses [GestureDetector]
  /// to handle the tap immediately. If null, it acts as a passive pointer [Listener]
  /// so existing inner handlers (like [InkWell] or [IconButton]) work unimpeded.
  final VoidCallback? onTap;

  /// Optional long press callback.
  final VoidCallback? onLongPress;

  /// Scale factor applied when pressed (e.g. 0.98 for cards, 0.95–0.96 for buttons).
  final double scaleFactor;

  /// Optional subtle opacity change when pressed.
  final double? pressedOpacity;

  /// Duration to animate in when pressed down (typically 90–130 ms).
  final Duration pressInDuration;

  /// Duration to animate out when released or canceled (typically 120–170 ms).
  final Duration pressOutDuration;

  /// Animation curve (natural and smooth).
  final Curve curve;

  /// Whether the interactive feedback and tap callbacks are enabled.
  final bool enabled;

  /// Whether to provide subtle haptic feedback on tap.
  final bool enableHaptic;

  /// Hit test behavior for the gesture detector.
  final HitTestBehavior behavior;

  const PressFeedback({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleFactor = 0.98,
    this.pressedOpacity,
    this.pressInDuration = const Duration(milliseconds: 100),
    this.pressOutDuration = const Duration(milliseconds: 140),
    this.curve = Curves.easeOutCubic,
    this.enabled = true,
    this.enableHaptic = false,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool _isPressed = false;
  Offset? _pointerDownPosition;

  void _handleTapDown() {
    if (!widget.enabled) return;
    if (!_isPressed) {
      setState(() => _isPressed = true);
    }
  }

  void _handleTapUp() {
    if (_isPressed) {
      setState(() => _isPressed = false);
    }
  }

  void _handleTapCancel() {
    if (_isPressed) {
      setState(() => _isPressed = false);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    _pointerDownPosition = event.position;
    if (!_isPressed) {
      setState(() => _isPressed = true);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isPressed || _pointerDownPosition == null) return;
    // Cancel press feedback if dragged more than 10 pixels (e.g. scrolling list)
    if ((event.position - _pointerDownPosition!).distance > 10.0) {
      setState(() {
        _isPressed = false;
        _pointerDownPosition = null;
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointerDownPosition = null;
    if (_isPressed) {
      setState(() => _isPressed = false);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointerDownPosition = null;
    if (_isPressed) {
      setState(() => _isPressed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Respect system reduced-motion preference
    final bool disableAnimations = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final double effectiveScale = (widget.enabled && _isPressed && !disableAnimations)
        ? widget.scaleFactor
        : 1.0;

    final Duration effectiveDuration = disableAnimations
        ? Duration.zero
        : (_isPressed ? widget.pressInDuration : widget.pressOutDuration);

    Widget visual = AnimatedScale(
      scale: effectiveScale,
      duration: effectiveDuration,
      curve: widget.curve,
      alignment: Alignment.center,
      child: widget.pressedOpacity != null && !disableAnimations
          ? AnimatedOpacity(
              opacity: (widget.enabled && _isPressed) ? widget.pressedOpacity! : 1.0,
              duration: effectiveDuration,
              curve: widget.curve,
              child: widget.child,
            )
          : widget.child,
    );

    // If an explicit onTap or onLongPress is provided, handle gestures directly
    if (widget.onTap != null || widget.onLongPress != null) {
      return GestureDetector(
        behavior: widget.behavior,
        onTapDown: widget.enabled ? (_) => _handleTapDown() : null,
        onTapUp: widget.enabled ? (_) => _handleTapUp() : null,
        onTapCancel: widget.enabled ? () => _handleTapCancel() : null,
        onTap: widget.enabled && widget.onTap != null
            ? () {
                if (widget.enableHaptic) {
                  HapticFeedback.lightImpact();
                }
                widget.onTap!();
              }
            : null,
        onLongPressStart: widget.enabled && widget.onLongPress != null
            ? (_) => _handleTapDown()
            : null,
        onLongPressEnd: widget.enabled && widget.onLongPress != null
            ? (_) => _handleTapUp()
            : null,
        onLongPressCancel: widget.enabled && widget.onLongPress != null
            ? () => _handleTapCancel()
            : null,
        onLongPress: widget.enabled && widget.onLongPress != null
            ? () {
                if (widget.enableHaptic) {
                  HapticFeedback.mediumImpact();
                }
                widget.onLongPress!();
              }
            : null,
        child: visual,
      );
    }

    // Passive listener for wrapping components that manage their own clicks (e.g. InkWell, IconButton)
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      behavior: HitTestBehavior.translucent,
      child: visual,
    );
  }
}
