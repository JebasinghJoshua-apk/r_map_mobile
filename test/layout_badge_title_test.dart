import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart';
import 'package:r_map_mobile/utils/layout_badge_title.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cluster names have tight measured widths instead of reserved boxes', () {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    );
    for (final name in ['Thiruvenkadam…', 'Thirumalai…', 'Yoga…']) {
      final fitted = layoutClusterNamePainter(name, style, maxWidth: 48);
      final text = fitted.text!.toPlainText();
      final measured = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(text: text, style: style),
      )..layout();
      expect(fitted.width, lessThanOrEqualTo(48));
      expect(fitted.width, measured.width);
      expect(text.endsWith('…'), isTrue);
      expect(text, isNot(contains('……')));
      fitted.dispose();
      measured.dispose();
    }
  });

  group('layoutBadgeTitleForZoom', () {
    test('shows up to two words through zoom 15.8', () {
      expect(
        layoutBadgeTitleForZoom('Sai Garden Extension', 12),
        'Sai Garden…',
      );
      expect(
        layoutBadgeTitleForZoom('Sai Garden Extension', 14.6),
        'Sai Garden…',
      );
      expect(
        layoutBadgeTitleForZoom('Sai Garden Extension', 14.61),
        'Sai Garden…',
      );
      expect(
        layoutBadgeTitleForZoom('Sai Garden Extension', 15.8),
        'Sai Garden…',
      );
    });

    test('shows the full name above zoom 15.8', () {
      expect(
        layoutBadgeTitleForZoom('Sai Garden Extension II', 15.81),
        'Sai Garden Extension II',
      );
    });

    test('shortens grouped layout titles at low zoom', () {
      for (final zoom in [10.0, 12.0, 14.0, 15.0, 15.8]) {
        expect(
          layoutClusterTitleForZoom('Thirumalai Nagar (3)', zoom),
          'Thirumalai… (3)',
        );
      }
    });

    test('preserves generic cluster counts at every zoom', () {
      for (final zoom in [10.0, 12.0, 15.0, 16.0]) {
        expect(layoutClusterTitleForZoom('5 Layouts', zoom), '5 Layouts');
      }
    });

    test('preserves counts when shortening longer grouped names', () {
      expect(
        layoutClusterTitleForZoom('Sai Garden Extension (12)', 14),
        'Sai Garden… (12)',
      );
      expect(
        layoutClusterTitleForZoom('Thirumalai Nagar (3)', 15.81),
        'Thirumalai Nagar (3)',
      );
    });

    test('removes phase suffixes from shortened names', () {
      expect(layoutBadgeTitleForZoom('Sai Garden II', 14.7), 'Sai Garden');
      expect(layoutBadgeTitleForZoom('Sai Garden 2', 14.6), 'Sai Garden');
    });

    test('uses the cluster alias when the name has no English label', () {
      expect(
        layoutBadgeTitleForZoom('', 16, clusterAlias: 'Lake View Phase 2'),
        'Lake View Phase 2',
      );
    });

    test('falls back to Layout when neither name nor alias has text', () {
      expect(layoutBadgeTitleForZoom('', 14), 'Layout');
    });
  });

  test('uses the matching title font size for badge zooms', () {
    expect(layoutBadgeTitleFontSizeForZoom(16.99), 11);
    expect(layoutBadgeTitleFontSizeForZoom(17), 13);
  });
}
