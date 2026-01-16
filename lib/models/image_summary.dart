class ImageSummary {
  const ImageSummary({
    required this.fileUrl,
    this.id,
    this.altText,
    this.description,
    this.isPrimary = false,
    this.displayOrder = 0,
  });

  final String? id;
  final String fileUrl;
  final String? altText;
  final String? description;
  final bool isPrimary;
  final int displayOrder;

  static ImageSummary fromJson(Map<String, dynamic> json) {
    return ImageSummary(
      id: json['id']?.toString(),
      fileUrl: (json['fileUrl'] as String?) ?? '',
      altText: json['altText'] as String?,
      description: json['description'] as String?,
      isPrimary: (json['isPrimary'] as bool?) ?? false,
      displayOrder: _asInt(json['displayOrder']) ?? 0,
    );
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
