import 'package:flutter/services.dart';

/// Formats numeric input with Indian numbering system (lakhs and crores).
///
/// Example: 1234567 becomes 12,34,567
class IndianCurrencyInputFormatter extends TextInputFormatter {
  const IndianCurrencyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final formatted = formatIndianDigits(digitsOnly);
    final digitsBeforeCursor = _countDigitsBeforeCursor(newValue);
    final cursor = _cursorOffsetForDigits(formatted, digitsBeforeCursor);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty,
    );
  }

  int _countDigitsBeforeCursor(TextEditingValue v) {
    final cursor = v.selection.baseOffset;
    final safe =
        cursor < 0 ? 0 : (cursor > v.text.length ? v.text.length : cursor);
    final before = v.text.substring(0, safe);
    return before.replaceAll(RegExp(r'\D'), '').length;
  }

  int _cursorOffsetForDigits(String formatted, int digitsCount) {
    if (digitsCount <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < formatted.length; i += 1) {
      final ch = formatted.codeUnitAt(i);
      final isDigit = ch >= 48 && ch <= 57;
      if (isDigit) {
        seen += 1;
        if (seen >= digitsCount) {
          return i + 1;
        }
      }
    }
    return formatted.length;
  }

  /// Formats digits with Indian grouping (2-2-3 pattern from the right).
  static String formatIndianDigits(String digits) {
    var d = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (d.isEmpty) return '';
    if (d.length <= 3) return d;

    final last3 = d.substring(d.length - 3);
    var rest = d.substring(0, d.length - 3);

    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) {
      parts.insert(0, rest);
    }

    return '${parts.join(',')},$last3';
  }
}

/// Formats a raw price string with Indian numbering system.
///
/// Handles both whole numbers and decimals.
String formatIndianPrice(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  // Keep only digits and at most one decimal point.
  final cleaned = trimmed.replaceAll(',', '');
  final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(cleaned);
  if (match == null) {
    final digitsOnly = cleaned.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) return trimmed;
    return IndianCurrencyInputFormatter.formatIndianDigits(digitsOnly);
  }

  final whole = match.group(1) ?? '';
  final fraction = match.group(2);
  final formattedWhole = IndianCurrencyInputFormatter.formatIndianDigits(whole);
  if (fraction == null || fraction.isEmpty) {
    return formattedWhole;
  }
  return '$formattedWhole.$fraction';
}
