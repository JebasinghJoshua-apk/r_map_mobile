import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/map_viewport_models.dart';
import '../screens/property_detail_screen.dart';
import '../screens/layout_detail_screen.dart';
import '../utils/pending_plot_selection.dart';

/// Parsed deep-link destination.
class _DeepLinkTarget {
  const _DeepLinkTarget({
    required this.propertyType,
    required this.featureId,
    required this.isSharePage,
    this.isPlotLink = false,
    this.layoutFeatureId,
    this.plotId,
    this.shortCode,
  });
  final String propertyType;
  final String featureId;
  final bool isSharePage;

  /// True if this is a plot deep link (/plot/{layoutFeatureId}/{plotId}).
  final bool isPlotLink;
  final String? layoutFeatureId;
  final String? plotId;

  /// Short code for /s/{code} URLs (layouts).
  final String? shortCode;
}

/// Handles incoming deep links for `/property/...` and `/share/...` URLs and
/// navigates to the appropriate detail screen.
///
/// Uses a [MethodChannel] to receive deep link intents from Android native code.
/// Cold-start links are fetched via [getInitialLink], warm-start links arrive
/// via the stream.
class DeepLinkService {
  DeepLinkService({required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  /// Pending deep-link URI that arrived before the navigator was ready
  /// (e.g. during the splash screen).
  Uri? _pendingUri;

  /// Whether the home screen has signalled it is ready.
  bool _homeScreenReady = false;

  /// Last URI we successfully started navigating to. Prevents duplicate
  /// navigation when the same link is delivered twice (e.g. via both
  /// onNewIntent and onResume on Android).
  String? _lastHandledUri;

  static const _allowedHosts = {
    'rmap.in',
    'www.rmap.in',
    'mango-beach-047e3b400.4.azurestaticapps.net',
  };

  static const _channel = MethodChannel('com.rmap.mobile/deeplink');

  // ───────────────────────────────────────────────────────────────────
  //  Public API
  // ───────────────────────────────────────────────────────────────────

  /// Call once from main / app widget. Sets up the listener for incoming links.
  Future<void> initialize() async {
    // Handle initial link (cold start via deep link).
    try {
      final initialLink = await _channel.invokeMethod<String>('getInitialLink');
      if (initialLink != null && initialLink.isNotEmpty) {
        final uri = Uri.tryParse(initialLink);
        if (uri != null) _handleUri(uri);
      }
    } catch (_) {
      // No initial link or channel not available.
    }

    // Listen for warm-start links.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNewLink') {
        final link = call.arguments as String?;
        if (link != null && link.isNotEmpty) {
          final uri = Uri.tryParse(link);
          if (uri != null) _handleUri(uri);
        }
      }
    });
  }

  /// Call from the home screen's initState so the service knows navigation is
  /// safe.
  void markHomeReady() {
    _homeScreenReady = true;
    _drainPending();
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }

  // ───────────────────────────────────────────────────────────────────
  //  Link handling
  // ───────────────────────────────────────────────────────────────────

  void _handleUri(Uri uri) {
    debugPrint('[DeepLink] received: $uri');

    // Only handle our known hosts.
    if (!_allowedHosts.contains(uri.host)) return;

    // Deduplicate: skip if we already handled this exact URI recently.
    final uriString = uri.toString();
    if (uriString == _lastHandledUri) {
      debugPrint('[DeepLink] skipping duplicate: $uri');
      return;
    }

    final target = _parseUri(uri);
    if (target == null) return;

    // /launch links just open the app – no navigation needed.
    // Mark as handled so onResume won't re-process.
    _lastHandledUri = uriString;

    if (!_homeScreenReady) {
      // The app just launched – stash this until the navigator is ready.
      _pendingUri = uri;
      return;
    }

    _navigateToTarget(target);
  }

  void _drainPending() {
    if (_pendingUri == null) return;
    final uri = _pendingUri!;
    _pendingUri = null;
    final target = _parseUri(uri);
    if (target != null) {
      // Small delay to ensure the home screen is fully mounted.
      Future.delayed(const Duration(milliseconds: 500), () {
        _navigateToTarget(target);
      });
    }
  }

  /// Parses `/property/{propertyType}/{featureId}/...` or
  /// `/share/{propertyType}/{featureId}` or
  /// `/plot/{layoutFeatureId}/{plotId}` into a [_DeepLinkTarget].
  _DeepLinkTarget? _parseUri(Uri uri) {
    final segments = uri.pathSegments;
    // /property/{type}/{featureId}[/{slug}]
    if (segments.length >= 3 && segments[0] == 'property') {
      return _DeepLinkTarget(
        propertyType: segments[1],
        featureId: segments[2],
        isSharePage: false,
      );
    }
    // /share/{type}/{featureId}
    if (segments.length >= 3 && segments[0] == 'share') {
      return _DeepLinkTarget(
        propertyType: segments[1],
        featureId: segments[2],
        isSharePage: true,
      );
    }
    // /plot/{layoutFeatureId}/{plotId}[/{slug}]
    if (segments.length >= 3 && segments[0] == 'plot') {
      return _DeepLinkTarget(
        propertyType: 'Plot',
        featureId: segments[2],
        isSharePage: false,
        isPlotLink: true,
        layoutFeatureId: segments[1],
        plotId: segments[2],
      );
    }
    // /s/{shortCode} - short URL for layouts
    if (segments.length >= 2 && segments[0] == 's') {
      return _DeepLinkTarget(
        propertyType: 'Layout',
        featureId: '', // Will be resolved via shortCode
        isSharePage: false,
        shortCode: segments[1],
      );
    }
    // /launch - just open the app (used by the web install banner)
    if (segments.isNotEmpty && segments[0] == 'launch') {
      debugPrint('[DeepLink] /launch → opening home screen');
      return null; // null = no navigation, app just opens to home
    }
    return null;
  }

  Future<void> _navigateToTarget(_DeepLinkTarget target) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    debugPrint(
      '[DeepLink] navigating → ${target.propertyType}/${target.featureId}${target.shortCode != null ? ' (shortCode: ${target.shortCode})' : ''}',
    );

    // Handle short URL (/s/{code}) - resolve shortCode to property type + ID.
    if (target.shortCode != null && target.shortCode!.isNotEmpty) {
      _showLoadingOverlay(nav.context);
      try {
        final resolved = await _resolveShortCode(target.shortCode!);
        if (nav.canPop()) nav.pop();

        if (resolved == null) {
          _showError(nav.context, 'Property not found');
          return;
        }

        // Navigate to the resolved property
        final isLayout = resolved.propertyType.toLowerCase() == 'layout';

        if (isLayout) {
          nav.push(
            MaterialPageRoute(
              builder: (_) => LayoutDetailScreen(
                layoutId: resolved.featureId,
                fromDeepLink: true,
              ),
            ),
          );
        } else {
          // Fetch property summary and navigate to PropertyDetailScreen
          final summary = await _fetchShareSummary(
            resolved.propertyType,
            resolved.featureId,
          );

          if (summary == null) {
            _showError(nav.context, 'Property not found');
            return;
          }

          // Build center GeoJSON from coordinates if available.
          String? centerGeoJson;
          final lat = summary['centerLatitude'];
          final lng = summary['centerLongitude'];
          if (lat is num && lng is num) {
            centerGeoJson = '{"type":"Point","coordinates":[$lng,$lat]}';
          }

          // Build a minimal MapPropertyFeature from the share summary.
          final feature = MapPropertyFeature(
            propertyId: summary['propertyId'] as String? ?? '',
            featureId: summary['featureId'] as String? ?? resolved.featureId,
            propertyType:
                summary['propertyType'] as String? ?? resolved.propertyType,
            name: summary['title'] as String? ?? 'Property',
            isOwnedByCurrentUser: false,
            listingType: summary['listingLabel'] as String?,
            boundaryGeoJson: summary['boundaryGeoJson'] as String?,
            centerGeoJson: centerGeoJson,
            metadata: _buildMetadataFromSummary(summary),
          );

          nav.push(
            MaterialPageRoute(
              builder: (_) => PropertyDetailScreen(
                feature: feature,
                fromDeepLink: true,
              ),
            ),
          );
        }
        return;
      } catch (e) {
        if (nav.canPop()) nav.pop();
        _showError(nav.context, 'Failed to load property');
        return;
      }
    }

    // Handle plot deep links - navigate to home map with focused plot.
    if (target.isPlotLink &&
        target.layoutFeatureId != null &&
        target.plotId != null) {
      await _navigateToPlot(nav, target.layoutFeatureId!, target.plotId!);
      return;
    }

    // Show a lightweight loading overlay while we fetch property info.
    _showLoadingOverlay(nav.context);

    try {
      // Fetch light-weight share summary from the public API.
      final summary = await _fetchShareSummary(
        target.propertyType,
        target.featureId,
      );

      // Dismiss loading overlay.
      if (nav.canPop()) nav.pop();

      if (summary == null) {
        _showError(nav.context, 'Property not found');
        return;
      }

      // Determine if this is a layout or a regular property.
      final isLayout = target.propertyType.toLowerCase() == 'layout' ||
          target.propertyType.toLowerCase() == 'layouts';

      if (isLayout) {
        // LayoutDetailScreen takes a layoutId (which is the featureId for
        // layouts).
        nav.push(
          MaterialPageRoute(
            builder: (_) => LayoutDetailScreen(
              layoutId: target.featureId,
              fromDeepLink: true,
            ),
          ),
        );
      } else {
        // Build center GeoJSON from coordinates if available.
        String? centerGeoJson;
        final lat = summary['centerLatitude'];
        final lng = summary['centerLongitude'];
        if (lat is num && lng is num) {
          centerGeoJson = '{"type":"Point","coordinates":[$lng,$lat]}';
        }

        // Build a minimal MapPropertyFeature from the share summary.
        final feature = MapPropertyFeature(
          propertyId: summary['propertyId'] as String? ?? '',
          featureId: summary['featureId'] as String? ?? target.featureId,
          propertyType:
              summary['propertyType'] as String? ?? target.propertyType,
          name: summary['title'] as String? ?? 'Property',
          isOwnedByCurrentUser: false,
          listingType: summary['listingLabel'] as String?,
          boundaryGeoJson: summary['boundaryGeoJson'] as String?,
          centerGeoJson: centerGeoJson,
          metadata: _buildMetadataFromSummary(summary),
        );

        nav.push(
          MaterialPageRoute(
            builder: (_) => PropertyDetailScreen(
              feature: feature,
              fromDeepLink: true,
            ),
          ),
        );
      }
    } catch (e) {
      // Dismiss loading overlay on error.
      if (nav.canPop()) nav.pop();
      debugPrint('[DeepLink] error: $e');
      _showError(nav.context, 'Could not open property');
    }
  }

  /// Navigate to home map and focus on a specific plot.
  Future<void> _navigateToPlot(
    NavigatorState nav,
    String layoutFeatureId,
    String plotId,
  ) async {
    debugPrint(
        '[DeepLink] navigating to plot $plotId in layout $layoutFeatureId');

    // Set pending plot selection. Coordinates will be fetched by the home
    // screen's _focusPlotFromDeepLink if needed.
    PendingPlotSelection.set(
      layoutFeatureId: layoutFeatureId,
      plotId: plotId,
      centerLatitude: null,
      centerLongitude: null,
    );

    // Pop to root (home map) if not already there.
    nav.popUntil((route) => route.isFirst);
  }

  // ───────────────────────────────────────────────────────────────────
  //  API helpers
  // ───────────────────────────────────────────────────────────────────

  /// Resolves a short code to property type and feature ID by calling the API.
  Future<({String propertyType, String featureId})?> _resolveShortCode(
      String shortCode) async {
    final baseUrl = ApiConstants.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$baseUrl/api/s/${Uri.encodeComponent(shortCode)}';

    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final propertyType = data['propertyType'] as String?;
        final featureId = data['featureId'] as String?;
        if (propertyType != null && featureId != null) {
          return (propertyType: propertyType, featureId: featureId);
        }
      }
    } catch (e) {
      debugPrint('[DeepLink] short code resolve error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _fetchShareSummary(
    String propertyType,
    String featureId,
  ) async {
    final baseUrl = ApiConstants.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$baseUrl/api/share/property/'
        '${Uri.encodeComponent(propertyType)}/$featureId';

    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[DeepLink] fetch error: $e');
    }
    return null;
  }

  Map<String, String?> _buildMetadataFromSummary(Map<String, dynamic> s) {
    return <String, String?>{
      if (s['location'] != null) 'location': s['location'] as String?,
      if (s['priceLabel'] != null) 'price': s['priceLabel'] as String?,
      if (s['areaLabel'] != null) 'area': s['areaLabel'] as String?,
      if (s['bedroomsLabel'] != null) 'bedrooms': s['bedroomsLabel'] as String?,
      if (s['listingLabel'] != null) 'listing': s['listingLabel'] as String?,
      if (s['subtitle'] != null) 'subtitle': s['subtitle'] as String?,
      if (s['heroImageUrl'] != null)
        'heroImageUrl': s['heroImageUrl'] as String?,
      if (s['description'] != null)
        'description': s['description'] as String?,
      if (s['contactName'] != null)
        'contactName': s['contactName'] as String?,
      if (s['contactNumbers'] != null)
        'contactNumbers': s['contactNumbers'] as String?,
      if (s['facingLabel'] != null) 'facing': s['facingLabel'] as String?,
      if (s['additionalDetails'] != null)
        'additionalInformation': s['additionalDetails'] as String?,
      if (s['subtitle'] != null) 'landType': s['subtitle'] as String?,
      if (s['buildingAgeLabel'] != null)
        'buildingAge': s['buildingAgeLabel'] as String?,
      if (s['floorsLabel'] != null) 'floors': s['floorsLabel'] as String?,
      if (s['shortCode'] != null) 'shortCode': s['shortCode'] as String?,
      if (s['surveyNumber'] != null)
        'surveyNumber': s['surveyNumber'] as String?,
      if (s['approvalNumber'] != null)
        'approvalNumber': s['approvalNumber'] as String?,
    };
  }

  // ───────────────────────────────────────────────────────────────────
  //  UI helpers
  // ───────────────────────────────────────────────────────────────────

  void _showLoadingOverlay(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Opening property…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }
}
