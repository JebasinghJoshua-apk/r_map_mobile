import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:r_map_mobile/models/map_viewport_models.dart';
import 'package:r_map_mobile/utils/layout_map_focus.dart';

void main() {
  const marker = LatLng(9.93, 78.12);
  const fallback = LatLng(9.94, 78.13);
  const focusPoint = LatLng(9.9252, 78.1198);
  const focusJson = '{"type":"Point","coordinates":[78.1198,9.9252]}';
  const boundary =
      '{"type":"Polygon","coordinates":[[[78,9],[78.01,9],[78.01,9.01],[78,9]]]}';

  MapPropertyFeature feature({
    String? focus = focusJson,
    String propertyType = 'Layout',
  }) =>
      MapPropertyFeature.fromJson({
        'propertyId': 'property-id',
        'featureId': 'layout-id',
        'propertyType': propertyType,
        'name': 'Layout',
        'centerGeoJson': '{"type":"Point","coordinates":[78.12,9.93]}',
        'boundaryGeoJson': boundary,
        'metadata': {'mapFocusPoint': focus},
      });

  LayoutMapFocus resolve(MapPropertyFeature value, {double? zoom}) =>
      LayoutMapFocus.resolve(
        value,
        fallbackTarget: fallback,
        fallbackZoom: 18.5,
        configuredZoom: zoom,
      );

  test('map focus changes only camera target, not marker or boundary', () {
    final value = feature();
    final result = resolve(value, zoom: 20);
    expect(result.target, focusPoint);
    expect(result.zoom, 20);
    expect(result.boundaryGeoJson, isNull);
    expect(value.centerPoint, marker);
    expect(value.boundaryGeoJson, boundary);
  });

  test('map focus without configured zoom uses default and skips boundary fit',
      () {
    final result = resolve(feature());
    expect(result.target, focusPoint);
    expect(result.zoom, 18.5);
    expect(result.boundaryGeoJson, isNull);
  });

  test('missing map focus preserves marker focus with configured zoom', () {
    final result = resolve(feature(focus: null), zoom: 19);
    expect(result.target, marker);
    expect(result.zoom, 19);
    expect(result.boundaryGeoJson, isNull);
  });

  test('missing focus and zoom preserve existing boundary fitting', () {
    final result = resolve(feature(focus: null));
    expect(result.target, fallback);
    expect(result.zoom, 18.5);
    expect(result.boundaryGeoJson, boundary);
  });

  test('map focus metadata is ignored for non-layout properties', () {
    final result = resolve(feature(propertyType: 'Land'), zoom: 19);
    expect(result.target, marker);
  });

  test(
      'zero and edge coordinates are valid and retain longitude/latitude order',
      () {
    expect(
        parseLayoutMapFocusPoint(
          '{"type":"Point","coordinates":[0,0]}',
        ),
        const LatLng(0, 0));
    expect(
        parseLayoutMapFocusPoint(
          '{"type":"Point","coordinates":[-180,90]}',
        ),
        const LatLng(90, -180));
  });

  for (final invalid in [
    '',
    'invalid',
    'null',
    '[]',
    '{"type":"Polygon","coordinates":[78,9]}',
    '{"type":"Point","coordinates":[78]}',
    '{"type":"Point","coordinates":[78,9,0]}',
    '{"type":"Point","coordinates":["78",9]}',
    '{"type":"Point","coordinates":[181,9]}',
    '{"type":"Point","coordinates":[78,91]}',
    '{"type":"Point","coordinates":[1e999,9]}',
  ]) {
    test('invalid focus falls back without clamping: $invalid', () {
      expect(parseLayoutMapFocusPoint(invalid), isNull);
      expect(resolve(feature(focus: invalid), zoom: 19).target, marker);
    });
  }
}
