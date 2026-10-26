import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:r_map_mobile/services/app_settings_service.dart';

void main() {
  test('map zoom flag reads the global enabled value', () async {
    final service = AppSettingsService(client: MockClient((request) async {
      expect(request.url.path, '/mobile/app-settings/map-display');
      return http.Response('{"showAdminMobileMapZoomLevel":true}', 200);
    }));
    expect(await service.getShowAdminMobileMapZoomLevel(), isTrue);
  });

  for (final body in ['{}', '{"showAdminMobileMapZoomLevel":false}', 'invalid']) {
    test('map zoom flag defaults off for $body', () async {
      final service = AppSettingsService(
        client: MockClient((request) async => http.Response(body, 200)),
      );
      expect(await service.getShowAdminMobileMapZoomLevel(), isFalse);
    });
  }

  test('map zoom flag defaults off when backend is unavailable', () async {
    final service = AppSettingsService(
      client: MockClient((request) async => http.Response('', 503)),
    );
    expect(await service.getShowAdminMobileMapZoomLevel(), isFalse);
  });
}