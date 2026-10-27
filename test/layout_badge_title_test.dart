import 'package:flutter_test/flutter_test.dart';
import 'package:r_map_mobile/utils/layout_badge_title.dart';

void main() {
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
      expect(
        layoutClusterTitleForZoom('Thirumalai Nagar (3)', 15),
        'Thirumalai… (3)',
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
