import 'package:flutter/material.dart';

class DelimitedBulletList extends StatelessWidget {
  const DelimitedBulletList({
    super.key,
    required this.text,
    this.delimiter = '~~',
    this.textStyle,
    this.bulletColor,
    this.bulletGap = 6,
    this.itemSpacing = 8,
  });

  final String text;
  final String delimiter;
  final TextStyle? textStyle;
  final Color? bulletColor;
  final double bulletGap;
  final double itemSpacing;

  List<String> _splitItems() {
    return text
        .split(delimiter)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final items = _splitItems();
    if (items.isEmpty) return const SizedBox.shrink();

    final effectiveStyle = textStyle ?? DefaultTextStyle.of(context).style;
    if (items.length == 1) {
      return Text(items.first, style: effectiveStyle);
    }

    final bulletStyle = effectiveStyle.copyWith(
      color: bulletColor ?? effectiveStyle.color,
      height: 1.2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•', style: bulletStyle),
              SizedBox(width: bulletGap),
              Expanded(
                child: Text(
                  items[i],
                  style: effectiveStyle,
                ),
              ),
            ],
          ),
          if (i != items.length - 1) SizedBox(height: itemSpacing),
        ],
      ],
    );
  }
}
