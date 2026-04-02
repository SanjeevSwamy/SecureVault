import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';

void showQrSheet(
  BuildContext context, {
  required String hash,
  required String fileName,
  int? fileSize,
  DateTime? timestamp,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QrSheet(
      hash: hash,
      fileName: fileName,
      fileSize: fileSize,
      timestamp: timestamp ?? DateTime.now(),
    ),
  );
}

class _QrSheet extends StatefulWidget {
  final String hash;
  final String fileName;
  final int? fileSize;
  final DateTime timestamp;

  const _QrSheet({
    required this.hash,
    required this.fileName,
    required this.fileSize,
    required this.timestamp,
  });

  @override
  State<_QrSheet> createState() => _QrSheetState();
}

class _QrSheetState extends State<_QrSheet> {
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isSharing = false;

  static const _surface = Color(0xFF0F172A);
  static const _card = Color(0xFF1E293B);
  static const _border = Color(0xFF334155);
  static const _accent = Color(0xFF2563EB);

  String get _payload {
    final data = {
      'sha256': widget.hash,
      'file': widget.fileName,
      if (widget.fileSize != null) 'size': widget.fileSize,
      'ts': widget.timestamp.toUtc().toIso8601String(),
      'link': 'securevault://verify?hash=${widget.hash}',
    };
    return jsonEncode(data);
  }

  Future<void> _shareQrCode() async {
    setState(() => _isSharing = true);
    try {
      // 1. Capture the QR as an image
      final Uint8List? imageBytes = await _screenshotController.capture();
      
      if (imageBytes != null) {
        // 2. Save to temp directory
        final tempDir = await getTemporaryDirectory();
        final file = await File('${tempDir.path}/qr_fingerprint.png').create();
        await file.writeAsBytes(imageBytes);

        // 3. Share with message
        final String message = "🔐 Secure Vault Fingerprint\n\n"
            "File: ${widget.fileName}\n"
            "Hash: ${widget.hash}\n\n"
            "Scan this QR in the Secure Vault app to verify the file's integrity offline.";

        await Share.shareXFiles(
          [XFile(file.path)],
          text: message,
          subject: 'File Fingerprint QR',
        );
      }
    } catch (e) {
      debugPrint("Error sharing QR: $e");
    } finally {
      setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: _border)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                width: 38,
                height: 4,
                decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            
            // Header
            _buildHeader(),
            const SizedBox(height: 28),

            // Captured QR Area
            Center(
              child: Screenshot(
                controller: _screenshotController,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: QrImageView(
                    data: _payload,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
            
            // Action Button: Share
            ElevatedButton.icon(
              onPressed: _isSharing ? null : _shareQrCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              icon: _isSharing 
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.share_rounded, size: 20),
              label: Text(
                _isSharing ? 'Generating...' : 'Share QR as Image',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
              ),
            ),

            const SizedBox(height: 24),
            
            // Metadata section (Reuse your existing meta rows)
            _buildMetadataSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
          child: const Icon(Icons.qr_code_2_rounded, size: 22, color: _accent),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share Fingerprint', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            Text('Verifiable offline via QR image', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: Colors.grey[500])),
          ],
        ),
      ],
    );
  }

  Widget _buildMetadataSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
      child: Column(
        children: [
          _metaRow(Icons.insert_drive_file_rounded, 'File', widget.fileName),
          _metaRow(Icons.fingerprint_rounded, 'SHA-256', widget.hash.substring(0, 8) + "..."),
        ],
      ),
    );
  }

  Widget _metaRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 13, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: Colors.grey[600])),
          const Spacer(),
          Text(value, style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }
}