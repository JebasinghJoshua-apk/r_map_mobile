import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/api_constants.dart';
import 'toast_message.dart';

/// Data required to populate the share bottom sheet for a plot.
class SharePlotInfo {
  const SharePlotInfo({
    required this.plotId,
    required this.layoutFeatureId,
    required this.plotNumber,
    this.layoutName,
    this.location,
    this.areaLabel,
    this.priceLabel,
    this.status,
    this.heroImageUrl,
  });

  final String plotId;
  final String layoutFeatureId;
  final String plotNumber;
  final String? layoutName;
  final String? location;
  final String? areaLabel;
  final String? priceLabel;
  final String? status;

  /// Layout's hero image URL for sharing.
  final String? heroImageUrl;
}

// ───────────────────────────────────────────────────────────────────
//  Public helper – call from any screen
// ───────────────────────────────────────────────────────────────────

/// Shows the share bottom sheet for a plot.
void showSharePlotSheet(BuildContext context, SharePlotInfo info) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SharePlotSheet(info: info),
  );
}

/// Fetches plot share summary from the API and shows the share sheet.
Future<void> showSharePlotSheetWithFetch(
  BuildContext context, {
  required String plotId,
  required String layoutFeatureId,
  required String plotNumber,
  String? areaLabel,
  String? status,
}) async {
  // Show loading indicator
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );

  try {
    final baseUrl = ApiConstants.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$baseUrl/api/share/plot/$layoutFeatureId/$plotId';
    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

    if (!context.mounted) return;
    Navigator.of(context).pop(); // Dismiss loading

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;

      final info = SharePlotInfo(
        plotId: plotId,
        layoutFeatureId: layoutFeatureId,
        plotNumber: plotNumber,
        layoutName: json['layoutName'] as String?,
        location: json['location'] as String?,
        areaLabel: areaLabel ?? _formatArea(json['areaSqFt']),
        priceLabel: json['priceLabel'] as String?,
        status: status ?? json['status'] as String?,
        heroImageUrl: json['heroImageUrl'] as String?,
      );

      if (!context.mounted) return;
      showSharePlotSheet(context, info);
    } else {
      // Fallback: show basic share sheet without API data
      final info = SharePlotInfo(
        plotId: plotId,
        layoutFeatureId: layoutFeatureId,
        plotNumber: plotNumber,
        areaLabel: areaLabel,
        status: status,
      );
      if (!context.mounted) return;
      showSharePlotSheet(context, info);
    }
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // Dismiss loading
    debugPrint('[SharePlot] fetch error: $e');

    // Fallback: show basic share sheet
    final info = SharePlotInfo(
      plotId: plotId,
      layoutFeatureId: layoutFeatureId,
      plotNumber: plotNumber,
      areaLabel: areaLabel,
      status: status,
    );
    showSharePlotSheet(context, info);
  }
}

String? _formatArea(dynamic areaSqFt) {
  if (areaSqFt == null) return null;
  if (areaSqFt is num && areaSqFt > 0) {
    return '${areaSqFt.toStringAsFixed(0)} Sq.ft';
  }
  return null;
}

// ───────────────────────────────────────────────────────────────────
//  Private implementation
// ───────────────────────────────────────────────────────────────────

String _buildShareUrl(SharePlotInfo info) {
  final base = ApiConstants.webBaseUrl.replaceAll(RegExp(r'/$'), '');
  return '$base/plot/${info.layoutFeatureId}/${info.plotId}';
}

String _buildShareText(SharePlotInfo info) {
  final parts = <String>[];

  // Plot label
  final plotLabel =
      info.plotNumber.isNotEmpty ? 'Plot #${info.plotNumber}' : 'Plot';
  parts.add(plotLabel);

  // Layout name
  if (info.layoutName != null && info.layoutName!.trim().isNotEmpty) {
    parts.add(info.layoutName!.trim());
  }

  // Area
  if (info.areaLabel != null && info.areaLabel!.trim().isNotEmpty) {
    parts.add(info.areaLabel!.trim());
  }

  // Price
  if (info.priceLabel != null && info.priceLabel!.trim().isNotEmpty) {
    parts.add(info.priceLabel!.trim());
  }

  // Status (only if not "Available")
  if (info.status != null &&
      info.status!.trim().isNotEmpty &&
      info.status!.trim().toLowerCase() != 'available') {
    parts.add(info.status!.trim());
  }

  return parts.join(' | ');
}

Future<File?> _downloadImage(String url) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;

    final dir = await getTemporaryDirectory();
    final ext = response.headers['content-type']?.contains('png') == true
        ? 'png'
        : 'jpg';
    final file = File('${dir.path}/share_plot.$ext');
    await file.writeAsBytes(response.bodyBytes);
    return file;
  } catch (_) {
    return null;
  }
}

class _SharePlotSheet extends StatefulWidget {
  const _SharePlotSheet({required this.info});

  final SharePlotInfo info;

  @override
  State<_SharePlotSheet> createState() => _SharePlotSheetState();
}

class _SharePlotSheetState extends State<_SharePlotSheet> {
  bool _copied = false;
  bool _imageError = false;
  Uint8List? _heroBytes;

  SharePlotInfo get info => widget.info;

  late final String _shareUrl;
  late final String _shareText;

  /// Layout's hero image URL.
  late final String? _heroImageUrl;

  @override
  void initState() {
    super.initState();
    _shareUrl = _buildShareUrl(info);
    _shareText = _buildShareText(info);
    _heroImageUrl = info.heroImageUrl;
    _preloadImage();
  }

  /// Loads the preview image from the layout's hero photo.
  Future<void> _preloadImage() async {
    final heroUrl = _heroImageUrl;
    if (heroUrl == null || heroUrl.isEmpty) {
      setState(() => _imageError = true);
      return;
    }

    try {
      final response = await http.get(Uri.parse(heroUrl));
      if (response.statusCode == 200 && mounted) {
        setState(() => _heroBytes = response.bodyBytes);
      } else if (mounted) {
        setState(() => _imageError = true);
      }
    } catch (_) {
      if (mounted) setState(() => _imageError = true);
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _shareUrl));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _shareViaWhatsApp() async {
    final text = '$_shareText\n\nView details:\n$_shareUrl';
    final encoded = Uri.encodeComponent(text);
    final uri = Uri.parse('https://wa.me/?text=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await _nativeShare();
    }
  }

  Future<void> _shareViaFacebook() async {
    final encoded = Uri.encodeComponent(_shareUrl);
    final uri =
        Uri.parse('https://www.facebook.com/sharer/sharer.php?u=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ToastMessage.show(context, 'Unable to open Facebook');
    }
  }

  Future<void> _nativeShare() async {
    final fullText = '$_shareText\n\nView details:\n$_shareUrl';
    final heroUrl = _heroImageUrl;
    if (heroUrl != null && heroUrl.isNotEmpty) {
      final file = await _downloadImage(heroUrl);
      if (file != null) {
        await Share.shareXFiles(
          [XFile(file.path)],
          text: fullText,
        );
        return;
      }
    }
    await Share.share(fullText);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    // Build title
    final plotLabel =
        info.plotNumber.isNotEmpty ? 'Plot #${info.plotNumber}' : 'Plot';
    final displayTitle = info.layoutName != null && info.layoutName!.isNotEmpty
        ? '$plotLabel - ${info.layoutName}'
        : plotLabel;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Share Plot',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Preview card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFFF8FAFC),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image
                  if (_heroImageUrl case final heroUrl? when heroUrl.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      height: 160,
                      child: _buildPreviewImage(),
                    ),
                  // Info
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (info.location != null &&
                            info.location!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  info.location!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (info.areaLabel != null &&
                                info.areaLabel!.trim().isNotEmpty)
                              Text(
                                info.areaLabel!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            if (info.priceLabel != null &&
                                info.priceLabel!.trim().isNotEmpty)
                              Text(
                                info.priceLabel!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            if (info.status != null &&
                                info.status!.trim().isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _statusColor(info.status!)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  info.status!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _statusColor(info.status!),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Share URL row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFFF8FAFC),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _shareUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _copyLink,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _copied ? const Color(0xFFF0FDFA) : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _copied
                              ? const Color(0xFF0D9488)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _copied ? Icons.check : Icons.copy,
                            size: 14,
                            color: _copied
                                ? const Color(0xFF0D9488)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _copied ? 'Copied' : 'Copy',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _copied
                                  ? const Color(0xFF0D9488)
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Share buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _ShareButton(
                  icon: Icons.chat_rounded,
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: _shareViaWhatsApp,
                ),
                const SizedBox(width: 12),
                _ShareButton(
                  icon: Icons.facebook_rounded,
                  label: 'Facebook',
                  color: const Color(0xFF1877F2),
                  onTap: _shareViaFacebook,
                ),
                const SizedBox(width: 12),
                _ShareButton(
                  icon: Icons.share_rounded,
                  label: 'More',
                  color: const Color(0xFF64748B),
                  outlined: true,
                  onTap: _nativeShare,
                ),
              ],
            ),
          ),

          SizedBox(height: 20 + bottomPad),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    final lower = status.toLowerCase();
    if (lower == 'sold') return const Color(0xFFC0392B);
    if (lower == 'booked') return const Color(0xFFF4B400);
    return const Color(0xFF0D9488); // Available / default
  }

  Widget _buildPreviewImage() {
    if (_heroBytes != null) {
      return Image.memory(
        _heroBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
      );
    }
    if (_imageError) {
      return const Center(
        child: Icon(Icons.image_not_supported_outlined,
            size: 40, color: Color(0xFFCBD5E1)),
      );
    }
    // Loading
    return const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: outlined ? Colors.white : color,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: outlined
                ? BoxDecoration(
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: outlined ? color : Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: outlined ? const Color(0xFF0F172A) : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
