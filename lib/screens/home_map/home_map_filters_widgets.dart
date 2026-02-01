part of '../home_map_screen.dart';

class _FilterPopoverArrow extends StatelessWidget {
  const _FilterPopoverArrow({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _FilterPopoverArrowPainter(color),
    );
  }
}

class _FilterPopoverArrowPainter extends CustomPainter {
  _FilterPopoverArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FilterPopoverArrowPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
