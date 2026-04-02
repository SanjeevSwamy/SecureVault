import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';

/// Result returned when a QR is successfully scanned or imported.
class QrScanResult {
  final String hash;
  final String? fileName;
  final int? fileSize;
  final DateTime? timestamp;

  const QrScanResult({
    required this.hash,
    this.fileName,
    this.fileSize,
    this.timestamp,
  });
}

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  static const _surface = Color(0xFF0F172A);

  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _scanned = false;
  bool _torchOn = false;
  String? _errorMsg;

  late final AnimationController _lineCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _scanner.dispose();
    _lineCtrl.dispose();
    super.dispose();
  }

  /// Unified detection logic for both Camera and Gallery
  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      QrScanResult? result;

      // 1. Try JSON payload
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final hash = map['sha256'] as String?;
        if (hash != null && hash.length == 64) {
          result = QrScanResult(
            hash: hash.toLowerCase(),
            fileName: map['file'] as String?,
            fileSize: map['size'] as int?,
            timestamp: map['ts'] != null
                ? DateTime.tryParse(map['ts'] as String)
                : null,
          );
        }
      } catch (_) {}

      // 2. Fall back: Deeplink
      if (result == null) {
        final uri = Uri.tryParse(raw);
        if (uri != null && uri.scheme == 'securevault') {
          final hash = uri.queryParameters['hash'];
          if (hash != null && hash.length == 64) {
            result = QrScanResult(hash: hash.toLowerCase());
          }
        }
      }

      // 3. Fall back: Raw hex
      if (result == null) {
        final trimmed = raw.trim().toLowerCase();
        if (trimmed.length == 64 &&
            RegExp(r'^[0-9a-f]{64}$').hasMatch(trimmed)) {
          result = QrScanResult(hash: trimmed);
        }
      }

      if (result != null) {
        _scanned = true;
        _scanner.stop();
        if (mounted) Navigator.of(context).pop(result);
        return;
      }
    }

    if (!_scanned && capture.barcodes.isNotEmpty) {
      setState(() => _errorMsg = 'QR code not recognized as a fingerprint.');
    }
  }

  /// Feature: Upload from Gallery
  Future<void> _uploadFromGallery() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    try {
      final BarcodeCapture? capture = await _scanner.analyzeImage(image.path);
      if (capture != null && capture.barcodes.isNotEmpty) {
        _onDetect(capture);
      } else {
        setState(() => _errorMsg = 'No QR code found in that image.');
      }
    } catch (e) {
      setState(() => _errorMsg = 'Could not read image file.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _surface,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _buildAppBar(),
        body: Stack(
          children: [
            MobileScanner(
              controller: _scanner,
              onDetect: _onDetect,
            ),
            _ScanOverlay(lineAnimation: _lineCtrl),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomBar(),
            ),
            if (_errorMsg != null)
              Positioned(
                top: 20,
                left: 24,
                right: 24,
                child: _ErrorBanner(
                  message: _errorMsg!,
                  onDismiss: () => setState(() => _errorMsg = null),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(Icons.chevron_left_rounded, size: 20, color: Colors.white),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Scan Fingerprint QR',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        centerTitle: true,
      );

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.9), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Scan a code or upload an image from your gallery',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CircleBtn(
                icon: _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                label: 'Flash',
                onTap: () {
                  _scanner.toggleTorch();
                  setState(() => _torchOn = !_torchOn);
                },
              ),
              _CircleBtn(
                icon: Icons.image_search_rounded,
                label: 'Gallery',
                onTap: _uploadFromGallery,
              ),
              _CircleBtn(
                icon: Icons.flip_camera_ios_rounded,
                label: 'Flip',
                onTap: () => _scanner.switchCamera(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── UI Components (Overlay, Brackets, Buttons, etc.) ──────────────────────────

class _ScanOverlay extends StatelessWidget {
  final AnimationController lineAnimation;
  const _ScanOverlay({required this.lineAnimation});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const cutout = 260.0;
    final top = (size.height - cutout) / 2 - 40;

    return Stack(
      children: [
        CustomPaint(
          size: Size(size.width, size.height),
          painter: _OverlayPainter(cutoutTop: top, cutoutSize: cutout),
        ),
        Positioned(
          top: top,
          left: (size.width - cutout) / 2,
          child: _CornerBrackets(size: cutout),
        ),
        Positioned(
          top: top,
          left: (size.width - cutout) / 2,
          child: AnimatedBuilder(
            animation: lineAnimation,
            builder: (_, __) => Transform.translate(
              offset: Offset(0, lineAnimation.value * (cutout - 3)),
              child: Container(
                width: cutout,
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.withOpacity(0), Colors.blue, Colors.blue.withOpacity(0)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final double cutoutTop;
  final double cutoutSize;
  const _OverlayPainter({required this.cutoutTop, required this.cutoutSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.65);
    final left = (size.width - cutoutSize) / 2;
    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(left, cutoutTop, cutoutSize, cutoutSize),
        const Radius.circular(16),
      ));
    canvas.drawPath(Path.combine(PathOperation.difference, full, hole), paint);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.cutoutTop != cutoutTop;
}

class _CornerBrackets extends StatelessWidget {
  final double size;
  const _CornerBrackets({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BracketPainter()),
    );
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 24.0;
    const r = 12.0;

    // Top Left
    canvas.drawPath(Path()..moveTo(0, len)..lineTo(0, r)..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))..lineTo(len, 0), paint);
    // Top Right
    canvas.drawPath(Path()..moveTo(size.width - len, 0)..lineTo(size.width - r, 0)..arcToPoint(Offset(size.width, r), radius: const Radius.circular(r))..lineTo(size.width, len), paint);
    // Bottom Left
    canvas.drawPath(Path()..moveTo(0, size.height - len)..lineTo(0, size.height - r)..arcToPoint(Offset(r, size.height), radius: const Radius.circular(r), clockwise: false)..lineTo(len, size.height), paint);
    // Bottom Right
    canvas.drawPath(Path()..moveTo(size.width - len, size.height)..lineTo(size.width - r, size.height)..arcToPoint(Offset(size.width, size.height - r), radius: const Radius.circular(r), clockwise: false)..lineTo(size.width, size.height - len), paint);
  }
  @override
  bool shouldRepaint(_) => false;
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white12),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.white60)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
          IconButton(onPressed: onDismiss, icon: const Icon(Icons.close, size: 18, color: Colors.redAccent)),
        ],
      ),
    );
  }
}