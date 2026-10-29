import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:r_map_mobile/services/deep_link_service.dart';
import 'package:r_map_mobile/utils/pending_property_selection.dart';
import 'package:r_map_mobile/utils/layout_map_focus.dart';

void main() {
  const channel = MethodChannel('com.rmap.mobile/deeplink');
  const boundary =
      '{"type":"Polygon","coordinates":[[[78,9],[78.01,9],[78.01,9.01],[78,9]]]}';

  testWidgets(
      'a focus-only layout link opens the map without creating a marker',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    PendingPropertySelection.take();
    final service = DeepLinkService(
      navigatorKey: navigatorKey,
      client: MockClient((_) async => http.Response(
          jsonEncode({
            'title': 'Focus-only layout',
            'mapFocusPoint':
                '{"type":"Point","coordinates":[78.1198,9.9252]}',
          }),
          200)),
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'getInitialLink'
          ? 'https://rmap.in/share/Layout/layout-id'
          : null,
    );
    addTearDown(() {
      service.dispose();
      PendingPropertySelection.take();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('Map')),
    ));
    await service.initialize();
    service.markHomeReady();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final feature = PendingPropertySelection.take();
    expect(feature, isNotNull);
    expect(feature!.centerPoint, isNull);
    expect(feature.boundaryGeoJson, isNull);
    expect(parseLayoutMapFocusPoint(feature.metadata['mapFocusPoint']),
        isNotNull);
    expect(find.text('Map'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final coldStart in [true, false]) {
    for (final path in [
      '/s/PlvVhI',
      '/share/Layout/layout-id',
      '/property/Layouts/layout-id/shared-layout',
    ]) {
      testWidgets(
          '${coldStart ? 'cold' : 'warm'} layout link $path selects map panel',
          (tester) async {
        final navigatorKey = GlobalKey<NavigatorState>();
        final requests = <String>[];
        var notifications = 0;
        void onSelection() => notifications++;
        PendingPropertySelection.take();
        PendingPropertySelection.changes.addListener(onSelection);

        final service = DeepLinkService(
          navigatorKey: navigatorKey,
          client: MockClient((request) async {
            requests.add(request.url.path);
            if (request.url.path.startsWith('/api/s/')) {
              return http.Response(
                jsonEncode({
                  'propertyType': 'Layout',
                  'featureId': 'layout-id',
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'title': 'Shared layout',
                'location': 'Palayambatti',
                'priceLabel': 'Price on Request',
                'boundaryGeoJson': boundary,
                if (coldStart) 'centerLatitude': 9,
                if (coldStart) 'centerLongitude': 78,
                'mobileFocusZoomLevel': 18.5,
                'mapFocusPoint':
                    '{"type":"Point","coordinates":[78.1198,9.9252]}',
              }),
              200,
            );
          }),
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async =>
              call.method == 'getInitialLink' ? 'https://rmap.in$path' : null,
        );
        addTearDown(() {
          service.dispose();
          PendingPropertySelection.changes.removeListener(onSelection);
          PendingPropertySelection.take();
          tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        await tester.pumpWidget(MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Map')),
        ));
        if (!coldStart) {
          navigatorKey.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Previous screen')),
            ),
          );
          await tester.pumpAndSettle();
          service.markHomeReady();
        }

        await service.initialize();
        if (coldStart) {
          expect(PendingPropertySelection.hasPending, isFalse);
          service.markHomeReady();
          await tester.pump(const Duration(milliseconds: 500));
        }
        await tester.pumpAndSettle();

        expect(navigatorKey.currentState!.canPop(), isFalse);
        expect(find.text('Map'), findsOneWidget);
        expect(notifications, 1);
        final feature = PendingPropertySelection.take();
        expect(feature, isNotNull);
        expect(feature!.featureId, 'layout-id');
        expect(feature.propertyType, 'Layout');
        expect(feature.name, 'Shared layout');
        expect(feature.boundaryGeoJson, boundary);
        expect(feature.metadata['location'], 'Palayambatti');
        expect(feature.metadata['mobileFocusZoomLevel'], '18.5');
        expect(feature.metadata['mapFocusPoint'],
            '{"type":"Point","coordinates":[78.1198,9.9252]}');
        expect(feature.centerPoint != null, coldStart);
        expect(requests.last, '/api/share/property/Layout/layout-id');
        expect(PendingPropertySelection.hasPending, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
