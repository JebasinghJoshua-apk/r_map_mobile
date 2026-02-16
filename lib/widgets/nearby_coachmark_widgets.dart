import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A tooltip-style coachmark that points at the nearby-layouts button.
///
/// Renders a rounded card with a brief message and a close button, plus a
/// triangular arrow pointing to the right (toward the button).
class NearbyCoachmarkTooltip extends StatefulWidget {
  const NearbyCoachmarkTooltip({
    super.key,
    required this.onDismiss,
  });

  /// Called when the user dismisses the coachmark (tap outside / X button).
  final VoidCallback onDismiss;

  @override
  State<NearbyCoachmarkTooltip> createState() => _NearbyCoachmarkTooltipState();
}

class _NearbyCoachmarkTooltipState extends State<NearbyCoachmarkTooltip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeScale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeScale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const arrowSize = 10.0;
    const bgColor = Color(0xFF374151);

    return FadeTransition(
      opacity: _fadeScale,
      child: ScaleTransition(
        scale: _fadeScale,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Card body
            Container(
              constraints: const BoxConstraints(maxWidth: 210),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.list_alt_outlined,
                        size: 16,
                        color: Color(0xFF5EEAD4),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Nearby Layouts',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: widget.onDismiss,
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tap here to browse layouts near your current view.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            // Arrow pointing right (toward button)
            const CustomPaint(
              size: Size(arrowSize, arrowSize * 2),
              painter: _ArrowPainter(color: bgColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => old.color != color;
}

/// Wraps a child widget with a pulsating ring animation.
///
/// The ring expands outward and fades, repeating [repeatCount] times per
/// appearance. Used for the 2-session "soft pulse" after coachmark dismissal.
class NearbyPulseWrapper extends StatefulWidget {
  const NearbyPulseWrapper({
    super.key,
    required this.child,
    required this.active,
    this.repeatCount = 3,
    this.pulseColor = const Color(0xFF14B8A6),
    this.borderRadius = 8.0,
  });

  final Widget child;
  final bool active;
  final int repeatCount;
  final Color pulseColor;
  final double borderRadius;

  @override
  State<NearbyPulseWrapper> createState() => _NearbyPulseWrapperState();
}

class _NearbyPulseWrapperState extends State<NearbyPulseWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _currentRepeat = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _controller.addStatusListener(_onStatus);
    if (widget.active) {
      _currentRepeat = 0;
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(NearbyPulseWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _currentRepeat = 0;
      _controller.forward(from: 0);
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
      _controller.reset();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _currentRepeat++;
      if (_currentRepeat < widget.repeatCount && widget.active) {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final show = widget.active && _currentRepeat < widget.repeatCount;

        return CustomPaint(
          foregroundPainter: show
              ? _PulseRingPainter(
                  progress: progress,
                  color: widget.pulseColor,
                  borderRadius: widget.borderRadius,
                )
              : null,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _PulseRingPainter extends CustomPainter {
  const _PulseRingPainter({
    required this.progress,
    required this.color,
    required this.borderRadius,
  });

  final double progress;
  final Color color;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    // The ring expands from 0 to maxSpread and fades out.
    const maxSpread = 10.0;
    final spread = maxSpread * progress;
    final opacity = (1.0 - progress).clamp(0.0, 0.6);

    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0 * (1.0 - progress), 0.5);

    final rect = Rect.fromLTWH(
      -spread,
      -spread,
      size.width + spread * 2,
      size.height + spread * 2,
    );
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius + spread));
    canvas.drawRRect(rr, paint);
  }

  @override
  bool shouldRepaint(covariant _PulseRingPainter old) =>
      old.progress != progress;
}
