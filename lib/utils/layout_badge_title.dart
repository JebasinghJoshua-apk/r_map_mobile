import 'package:flutter/painting.dart';

TextPainter layoutClusterNamePainter(
  String name,
  TextStyle? style, {
  required double maxWidth,
}) {
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    maxLines: 1,
    text: TextSpan(text: name.trim(), style: style),
  )..layout();
  if (painter.width <= maxWidth) return painter;

  final characters = name.trim().replaceFirst(RegExp(r'…$'), '').runes.toList();
  // Fit the actual string, not an ellipsized box that may retain unused width.
  do {
    if (characters.isNotEmpty) characters.removeLast();
    painter.text = TextSpan(
      text: '${String.fromCharCodes(characters).trimRight()}…',
      style: style,
    );
    painter.layout();
  } while (painter.width > maxWidth && characters.isNotEmpty);
  return painter;
}

String layoutBadgeTitleForZoom(
  String name,
  double zoom, {
  String? clusterAlias,
}) {
  String toEnglishLabel(String value) => RegExp(
        r"[A-Za-z0-9]+(?:['.-][A-Za-z0-9]+)*",
      ).allMatches(value).map((match) => match.group(0)!).join(' ');

  final fullName = toEnglishLabel(name).isNotEmpty
      ? toEnglishLabel(name)
      : toEnglishLabel(clusterAlias ?? '').isNotEmpty
          ? toEnglishLabel(clusterAlias ?? '')
          : 'Layout';
  final shortenedName = fullName
      .replaceFirst(
        RegExp(
          r'[\s\-.]+(?:X{0,3}(?:IX|IV|V?I{0,3})|\d+)\s*$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  final words = shortenedName
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();

  if (zoom > 15.8) return fullName;
  return words.length > 2
      ? '${words.take(2).join(' ')}…'
      : words.join(' ').isNotEmpty
          ? words.join(' ')
          : fullName;
}

double layoutBadgeTitleFontSizeForZoom(double zoom) => zoom >= 17.0 ? 13 : 11;

String layoutClusterTitleForZoom(String title, double zoom) {
  if (RegExp(r'^\d+ Layouts$').hasMatch(title.trim())) return title.trim();
  final match = RegExp(r'^(.*)\s+\((\d+)\)$').firstMatch(title.trim());
  if (match == null) return layoutBadgeTitleForZoom(title, zoom);
  if (zoom > 15.8) return title;

  final name = match.group(1)!;
  final count = match.group(2)!;
  final shortenedName = layoutBadgeTitleForZoom(name, zoom);
  final clusterName = shortenedName.endsWith('…')
      ? shortenedName
      : '${shortenedName.split(RegExp(r'\s+')).first}…';
  return '$clusterName ($count)';
}
