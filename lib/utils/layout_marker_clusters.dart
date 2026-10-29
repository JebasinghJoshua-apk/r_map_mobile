import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

const double layoutProximityClusterMaxZoom = 12;
const double layoutNamedClusterMaxZoom = 15;
const double _clusterCellPixels = 72;

class LayoutClusterItem {
  const LayoutClusterItem({
    required this.position,
    required this.name,
    this.alias,
  });

  final LatLng position;
  final String name;
  final String? alias;

  String get label {
    final explicitAlias = alias?.trim();
    if (explicitAlias != null && explicitAlias.isNotEmpty) return explicitAlias;
    final base = name
        .trim()
        .replaceFirst(
          RegExp(
            r'[\s\-.]+(?:X{0,3}(?:IX|IV|V?I{0,3})|\d+)\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    return base.isEmpty ? name.trim() : base;
  }

  String get groupKey =>
      '${alias?.trim().isNotEmpty == true ? 'alias' : 'name'}:'
      '${label.toLowerCase()}';
}

class LayoutMarkerCluster {
  const LayoutMarkerCluster({
    required this.indices,
    required this.position,
    required this.title,
  });

  final List<int> indices;
  final LatLng position;
  final String title;
}

List<LayoutMarkerCluster> clusterLayoutMarkers(
  List<LayoutClusterItem> items,
  double zoom,
) {
  if (zoom > layoutNamedClusterMaxZoom) return const [];

  final cellSize = _clusterCellPixels / (256 * math.pow(2, zoom));
  final cells = <String, List<int>>{};
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final latitude = item.position.latitude.clamp(-85.05112878, 85.05112878);
    final sinLatitude = math.sin(latitude * math.pi / 180);
    final x = (item.position.longitude + 180) / 360;
    final y =
        0.5 - math.log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * math.pi);
    final nameKey = zoom <= layoutProximityClusterMaxZoom ? '' : item.groupKey;
    final key = '${(x / cellSize).floor()},${(y / cellSize).floor()}:$nameKey';
    cells.putIfAbsent(key, () => []).add(i);
  }

  final clusters = <LayoutMarkerCluster>[];
  for (final indices in cells.values) {
    if (indices.length < 2) continue;
    final first = items[indices.first];
    final sameName =
        indices.every((index) => items[index].groupKey == first.groupKey);
    var lat = 0.0;
    var lng = 0.0;
    for (final index in indices) {
      lat += items[index].position.latitude;
      lng += items[index].position.longitude;
    }
    clusters.add(LayoutMarkerCluster(
      indices: List.unmodifiable(indices),
      position: LatLng(lat / indices.length, lng / indices.length),
      title: sameName
          ? '${first.label} (${indices.length})'
          : '${indices.length} Layouts',
    ));
  }
  return clusters;
}
