import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/api_constants.dart';
import 'toast_message.dart';

/// Data required to populate the share bottom sheet.
class SharePropertyInfo {
  const SharePropertyInfo({
    required this.title,
    required this.propertyType,
    required this.featureId,
    this.location,
    this.priceLabel,
    this.listingType,
    this.heroImageUrl,
  });

  final String title;
  final String propertyType;
  final String featureId;
  final String? location;
  final String? priceLabel;
  final String? listingType;

  /// Resolved absolute URL for the hero image (if available).
  final String? heroImageUrl;
}

// ───────────────────────────────────────────────────────────────────
//  Public helper – call from any screen
// ───────────────────────────────────────────────────────────────────

/// Shows the share bottom sheet for a property.
void showSharePropertySheet(BuildContext context, SharePropertyInfo info) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SharePropertySheet(info: info),
  );
}

// ───────────────────────────────────────────────────────────────────
//  Private implementation
// ───────────────────────────────────────────────────────────────────

String _buildShareUrl(SharePropertyInfo info) {
  final slug = info.title
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'(^-|-$)'), '');
  final base = ApiConstants.webBaseUrl.replaceAll(RegExp(r'/$'), '');
  final encodedType = Uri.encodeComponent(info.propertyType.trim());
  final fid = info.featureId.trim();
  return '$base/property/$encodedType/$fid${slug.isNotEmpty ? '/$slug' : ''}';
}

String _buildShareText(SharePropertyInfo info) {
  final parts = <String>[info.title];
  if (info.location != null && info.location!.trim().isNotEmpty) {
    parts.add(info.location!.trim());
  }
  if (info.priceLabel != null && info.priceLabel!.trim().isNotEmpty) {
    parts.add(info.priceLabel!.trim());
  }
  return parts.join(' — ');
}

String _buildMapImageUrl(SharePropertyInfo info) {
  final base = ApiConstants.webBaseUrl.replaceAll(RegExp(r'/$'), '');
  final encodedType = Uri.encodeComponent(info.propertyType.trim());
  final fid = info.featureId.trim();
  return '$base/api/share/property/$encodedType/$fid/image';
}

Future<File?> _downloadImage(String url) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;

    final dir = await getTemporaryDirectory();
    final ext = response.headers['content-type']?.contains('png') == true
        ? 'png'
        : 'jpg';
    final file = File('${dir.path}/share_property.$ext');
    await file.writeAsBytes(response.bodyBytes);
    return file;
  } catch (_) {
    return null;
  }
}

class _SharePropertySheet extends StatefulWidget {
  const _SharePropertySheet({required this.info});

  final SharePropertyInfo info;

  @override
  State<_SharePropertySheet> createState() => _SharePropertySheetState();
}

class _SharePropertySheetState extends State<_SharePropertySheet> {
  bool _copied = false;
  bool _imageLoaded = false;
  bool _imageError = false;
  Uint8List? _heroBytes;

  SharePropertyInfo get info => widget.info;

  late final String _shareUrl;
  late final String _shareText;
  late final String _heroUrl;

  @override
  void initState() {
    super.initState();
    _shareUrl = _buildShareUrl(info);
    _shareText = _buildShareText(info);
    _heroUrl = info.heroImageUrl ?? _buildMapImageUrl(info);
    _preloadImage();
  }

  Future<void> _preloadImage() async {
    try {
      final response = await http.get(Uri.parse(_heroUrl));
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _heroBytes = response.bodyBytes;
          _imageLoaded = true;
        });
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
    final text = '$_shareText\n$_shareUrl';
    final encoded = Uri.encodeComponent(text);
    final uri = Uri.parse('https://wa.me/?text=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Fallback: native share
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
    final file = await _downloadImage(_heroUrl);
    if (file != null) {
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '$_shareText\n$_shareUrl',
      );
    } else {
      await Share.share('$_shareText\n$_shareUrl');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

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
                  'Share Property',
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
                          info.title,
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
                        Row(
                          children: [
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
                            if (info.listingType != null &&
                                info.listingType!.trim().isNotEmpty &&
                                info.listingType!.trim().toLowerCase() !=
                                    'draft') ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDFA),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  info.listingType!.trim(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0D9488),
                                  ),
                                ),
                              ),
                            ],
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
