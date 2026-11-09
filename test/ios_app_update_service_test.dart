import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:r_map_mobile/services/ios_app_update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var now = DateTime.utc(2026, 11, 9);
  var requests = 0;
  var storeVersion = '1.0.58';

  http.Response listing({String? version, String? url}) => http.Response(
        jsonEncode({
          'results': [
            {
              'bundleId': 'in.rmap.app',
              'version': version ?? storeVersion,
              'trackViewUrl':
                  url ?? 'https://apps.apple.com/in/app/id123456789',
            },
          ],
        }),
        200,
      );

  MockClient client() => MockClient((request) async {
        requests++;
        expect(request.url.host, 'itunes.apple.com');
        expect(request.url.queryParameters['bundleId'], 'in.rmap.app');
        expect(request.url.queryParameters['country'], 'in');
        return listing();
      });

  setUp(() {
    now = DateTime.utc(2026, 11, 9);
    requests = 0;
    storeVersion = '1.0.58';
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'R Map',
      packageName: 'in.rmap.app',
      version: '1.0.57',
      buildNumber: '65',
      buildSignature: '',
    );
  });

  test('returns a newer published version and its App Store URL', () async {
    final service = IosAppUpdateService(client: client(), now: () => now);
    final update = await service.checkForUpdate();
    expect(update?.version, '1.0.58');
    expect(update?.storeUrl.host, 'apps.apple.com');
    expect(requests, 1);
  });

  for (final version in ['1.0.57', '1.0.56', '1.0.57.0']) {
    test('does not prompt for equal or older version $version', () async {
      storeVersion = version;
      final service = IosAppUpdateService(client: client());
      expect(await service.checkForUpdate(), isNull);
    });
  }

  test('compares version components numerically', () async {
    storeVersion = '1.0.100';
    expect(
      (await IosAppUpdateService(client: client()).checkForUpdate())?.version,
      '1.0.100',
    );
  });

  test('checks only once per rolling 24 hours, across service restarts',
      () async {
    final httpClient = client();
    await IosAppUpdateService(client: httpClient, now: () => now)
        .checkForUpdate();
    now = now.add(const Duration(hours: 23, minutes: 59));
    expect(
      await IosAppUpdateService(client: httpClient, now: () => now)
          .checkForUpdate(),
      isNull,
    );
    expect(requests, 1);
    now = now.add(const Duration(minutes: 1));
    await IosAppUpdateService(client: httpClient, now: () => now)
        .checkForUpdate();
    expect(requests, 2);
  });

  test('handles device clock moving backwards', () async {
    final service = IosAppUpdateService(client: client(), now: () => now);
    await service.checkForUpdate();
    now = now.subtract(const Duration(days: 1));
    expect(await service.checkForUpdate(), isNotNull);
    expect(requests, 2);
  });

  test('does not start concurrent lookups', () async {
    final response = Completer<http.Response>();
    final service =
        IosAppUpdateService(client: MockClient((_) => response.future));
    final first = service.checkForUpdate();
    expect(await service.checkForUpdate(), isNull);
    response.complete(listing());
    expect(await first, isNotNull);
  });

  for (final body in ['invalid', '{}', '{"results":[]}']) {
    test('invalid or missing listing does not interrupt the app: $body',
        () async {
      final service = IosAppUpdateService(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      expect(await service.checkForUpdate(), isNull);
    });
  }

  test('offline failure is non-blocking and throttled for a day', () async {
    final service = IosAppUpdateService(
      now: () => now,
      client: MockClient((_) async {
        requests++;
        throw http.ClientException('offline');
      }),
    );
    expect(await service.checkForUpdate(), isNull);
    expect(await service.checkForUpdate(), isNull);
    expect(requests, 1);
  });

  test('HTTP failure does not interrupt the app', () async {
    final service = IosAppUpdateService(
      client: MockClient((_) async => http.Response('', 503)),
    );
    expect(await service.checkForUpdate(), isNull);
  });

  testWidgets('lookup times out after five seconds', (tester) async {
    final pendingResponse = Completer<http.Response>();
    final service = IosAppUpdateService(
      client: MockClient((_) {
        requests++;
        return pendingResponse.future;
      }),
    );
    final check = service.checkForUpdate();
    await tester.pump();
    expect(requests, 1);
    await tester.pump(const Duration(seconds: 4));
    var completed = false;
    unawaited(check.then((_) => completed = true));
    await tester.pump();
    expect(completed, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(await check, isNull);
    pendingResponse.complete(listing());
    await tester.pump();
  });

  test('rejects invalid versions and non-App Store destinations', () async {
    final badListings = [
      listing(version: 'invalid'),
      listing(url: 'https://example.com/app'),
      listing(url: 'http://apps.apple.com/app'),
      http.Response('{"results":[{"bundleId":"other.app"}]}', 200),
    ];
    for (final response in badListings) {
      SharedPreferences.setMockInitialValues({});
      expect(
        await IosAppUpdateService(
          client: MockClient((_) async => response),
        ).checkForUpdate(),
        isNull,
      );
    }
  });

  Future<void> showPrompt(
      WidgetTester tester, IosAppUpdateService service) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => service.checkAndPrompt(context),
            child: const Text('Check'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();
  }

  testWidgets('Later persists dismissal and a future version can prompt',
      (tester) async {
    final service = IosAppUpdateService(client: client(), now: () => now);
    await showPrompt(tester, service);
    expect(find.text('Update available'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    now = now.add(const Duration(days: 1));
    final nextSession = IosAppUpdateService(client: client(), now: () => now);
    expect(await nextSession.checkForUpdate(), isNull);
    now = now.add(const Duration(days: 1));
    storeVersion = '1.0.59';
    expect((await nextSession.checkForUpdate())?.version, '1.0.59');
  });

  testWidgets('Update opens the App Store externally', (tester) async {
    Uri? opened;
    final service = IosAppUpdateService(
      client: client(),
      openStore: (url) async {
        opened = url;
        return true;
      },
    );
    await showPrompt(tester, service);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(opened.toString(), 'https://apps.apple.com/in/app/id123456789');
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('dismissing the dialog remembers the offered version',
      (tester) async {
    final service = IosAppUpdateService(client: client(), now: () => now);
    await showPrompt(tester, service);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    now = now.add(const Duration(days: 1));
    expect(await service.checkForUpdate(), isNull);
  });

  testWidgets('backgrounded app does not show the prompt', (tester) async {
    final response = Completer<http.Response>();
    final service = IosAppUpdateService(
      client: MockClient((_) => response.future),
    );
    await showPrompt(tester, service);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    response.complete(listing());
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('failed App Store launch shows an actionable message',
      (tester) async {
    final service = IosAppUpdateService(
      client: client(),
      openStore: (_) async => false,
    );
    await showPrompt(tester, service);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to open the App Store. Please try again later.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
  });
}
