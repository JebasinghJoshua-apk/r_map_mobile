import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api_constants.dart';

class PlaceZoomOverride {
  const PlaceZoomOverride({
    required this.googlePlaceId,
    required this.displayName,
    required this.normalizedName,
    required this.zoomLevel,
  });

  final String googlePlaceId;
  final String displayName;
  final String normalizedName;
  final double zoomLevel;

  Map<String, dynamic> toJson() => {
        'googlePlaceId': googlePlaceId,
        'displayName': displayName,
        'normalizedName': normalizedName,
        'zoomLevel': zoomLevel,
      };

  factory PlaceZoomOverride.fromJson(Map<String, dynamic> json) {
    return PlaceZoomOverride(
      googlePlaceId: (json['googlePlaceId'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '',
      normalizedName: (json['normalizedName'] as String?) ?? '',
      zoomLevel: ((json['zoomLevel'] as num?) ?? 0).toDouble(),
    );
  }
}

class PlaceZoomOverrideService {
  PlaceZoomOverrideService({http.Client? client})
      : _client = client ?? http.Client();

  static const _cacheKey = 'place_zoom_overrides_v1';
  static const Duration _timeout = Duration(seconds: 3);

  final http.Client _client;
  bool _loadedCache = false;
  Map<String, PlaceZoomOverride> _byPlaceId = const {};
  Map<String, PlaceZoomOverride> _byName = const {};

  Future<void> loadCached() async {
    if (_loadedCache) return;
    _loadedCache = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((item) => PlaceZoomOverride.fromJson(
                item.cast<String, dynamic>(),
              ))
          .where((item) => item.zoomLevel > 0)
          .toList(growable: false);
      _replace(list);
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to load place zoom cache: $e');
    }
  }

  Future<void> refresh() async {
    try {
      final base = ApiConstants.mobileBffBaseUrl.endsWith('/')
          ? ApiConstants.mobileBffBaseUrl.substring(
              0,
              ApiConstants.mobileBffBaseUrl.length - 1,
            )
          : ApiConstants.mobileBffBaseUrl;
      final uri = Uri.parse('$base/mobile/place-zoom-overrides');
      final response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return;

      final list = (jsonDecode(response.body) as List)
          .whereType<Map>()
          .map((item) => PlaceZoomOverride.fromJson(
                item.cast<String, dynamic>(),
              ))
          .where((item) => item.zoomLevel > 0)
          .toList(growable: false);

      _replace(list);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(list.map((item) => item.toJson()).toList()),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to refresh place zoom overrides: $e');
    }
  }

  Future<double?> refreshAndFindZoom({
    required String placeId,
    required String placeName,
  }) async {
    await loadCached();
    await refresh();
    return findZoom(placeId: placeId, placeName: placeName);
  }

  double? findZoom({required String placeId, required String placeName}) {
    final byPlace = _byPlaceId[placeId.trim()];
    if (byPlace != null) return byPlace.zoomLevel;

    final byName = _byName[normalizePlaceName(placeName)];
    return byName?.zoomLevel;
  }

  void _replace(List<PlaceZoomOverride> items) {
    _byPlaceId = {
      for (final item in items)
        if (item.googlePlaceId.trim().isNotEmpty)
          item.googlePlaceId.trim(): item,
    };
    _byName = {
      for (final item in items)
        if (item.normalizedName.trim().isNotEmpty)
          item.normalizedName.trim(): item,
    };
  }

  static String normalizePlaceName(String value) {
    return value.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
  }
}