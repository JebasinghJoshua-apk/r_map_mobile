import 'dart:convert';

class RecentPlace {
  final String placeId;
  final String title;
  final String subtitle;

  const RecentPlace({
    required this.placeId,
    required this.title,
    required this.subtitle,
  });

  String get displayLabel => subtitle.isNotEmpty ? '$title $subtitle' : title;

  String toJsonString() => jsonEncode({
        'placeId': placeId,
        'title': title,
        'subtitle': subtitle,
      });

  static RecentPlace? fromJsonString(String value) {
    try {
      final map = jsonDecode(value) as Map<String, dynamic>;
      final placeId = map['placeId'] as String?;
      final title = map['title'] as String?;
      if (placeId == null || title == null) {
        return null;
      }
      return RecentPlace(
        placeId: placeId,
        title: title,
        subtitle: map['subtitle'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
