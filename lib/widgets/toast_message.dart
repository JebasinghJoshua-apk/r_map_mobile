import 'package:flutter/material.dart';

/// App-wide toast/snackbar styling helper.
///
/// Uses a compact floating pill similar to the map zoom badge.
class ToastMessage {
  ToastMessage._();

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    double bottomMargin = 24,
    double fontSize = 14,
    int maxLines = 3,
  }) {
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.clearSnackBars();

    final screenWidth = MediaQuery.maybeSizeOf(context)?.width ?? 400;
    final textScaler = MediaQuery.textScalerOf(context);
    final maxWidth = screenWidth - 24;

    const horizontalPadding = 12.0;
    const verticalPadding = 8.0;

    final textStyle = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w600,
      fontSize: fontSize,
    );

    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final painter = TextPainter(
      text: TextSpan(text: message, style: textStyle),
      maxLines: maxLines < 1 ? 1 : maxLines,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth - (horizontalPadding * 2) - 6);

    // Approximate width: wrapped text + padding + a little safety.
    final desiredWidth = painter.width + (horizontalPadding * 2) + 6;
    final pillWidth = desiredWidth.clamp(80.0, maxWidth).toDouble();
    final horizontalMargin =
        ((screenWidth - pillWidth) / 2).clamp(12.0, 200.0).toDouble();

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.horizontal,
        backgroundColor: Colors.black54,
        elevation: 0,
        margin: EdgeInsets.fromLTRB(
            horizontalMargin, 0, horizontalMargin, bottomMargin),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: duration,
        padding: const EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        content: Text(
          message,
          overflow: TextOverflow.ellipsis,
          maxLines: maxLines < 1 ? 1 : maxLines,
          softWrap: true,
          textAlign: TextAlign.center,
          style: textStyle,
        ),
      ),
    );
  }
}
