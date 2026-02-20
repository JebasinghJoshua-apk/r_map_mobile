import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'toast_message.dart';

/// Bottom sheet displaying QR code for a layout with print capability.
///
/// The QR code is sized for 2"×1" (50.8mm × 25.4mm) labels at 300 DPI.
class LayoutQrCodeSheet extends StatefulWidget {
  const LayoutQrCodeSheet({
    super.key,
    required this.layoutId,
    required this.layoutName,
    required this.shareUrl,
  });

  final String layoutId;
  final String layoutName;
  final String shareUrl;

  @override
  State<LayoutQrCodeSheet> createState() => _LayoutQrCodeSheetState();
}

class _LayoutQrCodeSheetState extends State<LayoutQrCodeSheet> {
  final GlobalKey _qrKey = GlobalKey();
  bool _isPrinting = false;
  bool _isCopied = false;

  Future<void> _copyUrl() async {
    await Clipboard.setData(ClipboardData(text: widget.shareUrl));
    setState(() {
      _isCopied = true;
    });
    if (mounted) {
      ToastMessage.show(context, 'URL copied to clipboard');
    }
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isCopied = false;
        });
      }
    });
  }

  Future<void> _shareUrl() async {
    final text = '${widget.layoutName}\n\nView layout:\n${widget.shareUrl}';
    await Share.share(text, subject: widget.layoutName);
  }

  Future<void> _printQrCode() async {
    setState(() {
      _isPrinting = true;
    });

    try {
      // Generate PDF with QR code for 2"×1" label
      final pdf = pw.Document();

      // Label dimensions: 2" × 1" = 144pt × 72pt
      const labelWidth = 144.0; // 2 inches in points
      const labelHeight = 72.0; // 1 inch in points

      // Generate QR code image data
      // ignore: deprecated_member_use - using legacy API for compatibility
      final qrImage = await QrPainter(
        data: widget.shareUrl,
        version: QrVersions.auto,
        gapless: true,
        color: const Color(0xFF000000),
        emptyColor: const Color(0xFFFFFFFF),
      ).toImageData(300); // 300 DPI for high quality printing

      if (qrImage == null) {
        throw Exception('Failed to generate QR code image');
      }

      final qrBytes = qrImage.buffer.asUint8List();

      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(labelWidth, labelHeight),
          margin: pw.EdgeInsets.zero,
          build: (context) {
            return pw.Container(
              width: labelWidth,
              height: labelHeight,
              padding: const pw.EdgeInsets.all(4),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // QR Code - square, fitting the height
                  pw.Container(
                    width: 64,
                    height: 64,
                    child: pw.Image(
                      pw.MemoryImage(qrBytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  // Text content
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          widget.layoutName,
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: pw.TextOverflow.clip,
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Scan to view',
                          style: const pw.TextStyle(
                            fontSize: 7,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

      // Print the PDF
      await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(),
        name:
            'Layout_${widget.layoutName.replaceAll(RegExp(r'[^\w\s]'), '_')}.pdf',
      );

      if (mounted) {
        ToastMessage.show(context, 'QR code sent to printer');
      }
    } catch (e) {
      if (mounted) {
        ToastMessage.show(context, 'Failed to print QR code');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPrinting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          const Text(
            'Layout QR Code',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),

          // Layout name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              widget.layoutName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 24),

          // QR Code preview (2:1 aspect ratio label preview)
          RepaintBoundary(
            key: _qrKey,
            child: Container(
              width: 280,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x10000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // QR Code
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: QrImageView(
                      data: widget.shareUrl,
                      version: QrVersions.auto,
                      size: 110,
                      gapless: true,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Text content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.layoutName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Scan to view layout',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Label size info
          const Text(
            'Label size: 2" × 1" (50mm × 25mm)',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 24),

          // URL display
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.link,
                    size: 18,
                    color: Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.shareUrl,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF4B5563),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _copyUrl,
                    child: Icon(
                      _isCopied ? Icons.check : Icons.copy,
                      size: 18,
                      color: _isCopied
                          ? const Color(0xFF059669)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                // Share button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _shareUrl,
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF374151),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Print button
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isPrinting ? null : _printQrCode,
                    icon: _isPrinting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.print, size: 18),
                    label: Text(_isPrinting ? 'Printing...' : 'Print'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0FAD97),
                      disabledBackgroundColor: const Color(0xFFCBD5E1),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Done button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
