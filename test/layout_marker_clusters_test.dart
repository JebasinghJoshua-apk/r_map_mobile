import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:r_map_mobile/utils/layout_marker_clusters.dart';

void main() {
  const position = LatLng(9.9252, 78.1198);
  LayoutClusterItem item(String name, {String? alias, LatLng? point}) =>
      LayoutClusterItem(
        position: point ?? position,
        name: name,
        alias: alias,
      );

  test('nearby mixed names cluster through the web zoom threshold', () {
    final items = [item('Orange I'), item('Orange II'), item('Apple I')];
    for (final zoom in [5.0, 10.0, 12.0]) {
      final clusters = clusterLayoutMarkers(items, zoom);
      expect(clusters, hasLength(1));
      expect(clusters.single.title, '3 Layouts');
      expect(clusters.single.indices, [0, 1, 2]);
    }
  });

  test('same-name layouts retain the named cluster at low and middle zoom', () {
    for (final zoom in [10.0, 12.0, 12.01, 14.0, 15.0]) {
      final clusters = clusterLayoutMarkers(
        [item('Orange I'), item('Orange II')],
        zoom,
      );
      expect(clusters.single.title, 'Orange (2)');
    }
  });

  test('mixed groups split into named groups and individuals at middle zoom',
      () {
    final clusters = clusterLayoutMarkers([
      item('Orange I'),
      item('Orange II'),
      item('Apple 1'),
      item('Apple 2'),
      item('Pear'),
    ], 13);
    expect(
        clusters.map((cluster) => cluster.title), ['Orange (2)', 'Apple (2)']);
    expect(clusters.expand((cluster) => cluster.indices), [0, 1, 2, 3]);
  });

  test('mixed count represents actual layouts rather than named groups', () {
    final clusters = clusterLayoutMarkers([
      item('Orange I'),
      item('Orange II'),
      item('Apple 1'),
      item('Apple 2'),
      item('Pear'),
    ], 12);
    expect(clusters.single.title, '5 Layouts');
    expect(clusters.single.indices, hasLength(5));
  });

  test('all layouts are individual above zoom 15', () {
    expect(clusterLayoutMarkers([item('Orange I'), item('Orange II')], 15.01),
        isEmpty);
  });

  test('screen-space grid separates the same points as zoom increases', () {
    double longitudeAtCellOffset(double offset) =>
        ((8000 + offset) * 72 / (256 * 4096)) * 360 - 180;
    final items = [
      item('Orange I', point: LatLng(9.9, longitudeAtCellOffset(0.1))),
      item('Orange II', point: LatLng(9.9, longitudeAtCellOffset(0.8))),
    ];
    expect(clusterLayoutMarkers(items, 12).single.title, 'Orange (2)');
    expect(clusterLayoutMarkers(items, 13), isEmpty);
  });

  test('distant layouts remain separate even with the same name', () {
    final items = [
      item('Orange I'),
      item('Orange II', point: const LatLng(13.08, 80.27)),
    ];
    for (final zoom in [10.0, 12.0, 14.0, 15.0]) {
      expect(clusterLayoutMarkers(items, zoom), isEmpty);
    }
  });

  test('explicit aliases take precedence and compare case-insensitively', () {
    final clusters = clusterLayoutMarkers([
      item('First project', alias: ' Orange '),
      item('Second project', alias: 'orange'),
    ], 14);
    expect(clusters.single.title, 'Orange (2)');
  });

  test('different aliases are not merged as a named group', () {
    expect(
        clusterLayoutMarkers([
          item('Orange I', alias: 'East'),
          item('Orange II', alias: 'West'),
        ], 14),
        isEmpty);
  });

  test('empty aliases fall back to case-insensitive numeric base names', () {
    final clusters = clusterLayoutMarkers([
      item('Orange 1', alias: ' '),
      item('orange 2'),
    ], 14);
    expect(clusters.single.title, 'Orange (2)');
  });

  test('cluster position averages all public marker positions', () {
    final clusters = clusterLayoutMarkers([
      item('Orange I'),
      item('Orange II', point: const LatLng(9.92521, 78.11981)),
    ], 12);
    expect(clusters.single.position.latitude, closeTo(9.925205, 0.0000001));
    expect(clusters.single.position.longitude, closeTo(78.119805, 0.0000001));
  });

  test('empty and single-marker inputs do not produce a cluster', () {
    expect(clusterLayoutMarkers([], 12), isEmpty);
    expect(clusterLayoutMarkers([item('Orange')], 12), isEmpty);
  });

  test('Mercator latitude is clamped for polar marker positions', () {
    final clusters = clusterLayoutMarkers([
      item('Orange I', point: const LatLng(90, 78)),
      item('Orange II', point: const LatLng(90, 78)),
    ], 12);
    expect(clusters.single.title, 'Orange (2)');
  });
}
