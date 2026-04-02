import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_vault/features/dashboard/screens/dashboard_screen.dart';

// New imports — add these two files next to this one
import 'qr_scanner_screen.dart';
import 'qr_sheet.dart';

class VerifyFileScreen extends StatefulWidget {
  const VerifyFileScreen({super.key});

  @override
  State<VerifyFileScreen> createState() => _VerifyFileScreenState();
}

class _VerifyFileScreenState extends State<VerifyFileScreen>
    with TickerProviderStateMixin {
  static const _surface = Color(0xFF0F172A);
  static const _card = Color(0xFF1E293B);
  static const _border = Color(0xFF334155);
  static const _accent = Color(0xFF2563EB);
  static const _success = Color(0xFF10B981);
  static const _danger = Color(0xFFEF4444);

  late final AnimationController _resultCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  late final Animation<double> _resultFade =
      CurvedAnimation(parent: _resultCtrl, curve: Curves.easeOut);

  late final Animation<Offset> _resultSlide =
      Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
    CurvedAnimation(parent: _resultCtrl, curve: Curves.easeOut),
  );

  _VerifyState _state = _VerifyState.idle;
  String _progressLabel = '';

  String? _fileName;
  int? _fileSize;
  DateTime? _hashTimestamp;

  String? _sha256Hash;
  bool? _hashMatches;
  String? _errorMessage;

  final TextEditingController _expectedHashController = TextEditingController();

  @override
  void dispose() {
    _resultCtrl.dispose();
    _expectedHashController.dispose();
    super.dispose();
  }

  // ── QR: scan incoming QR and auto-fill hash field ─────────────────────────

  Future<void> _scanQr() async {
    final result = await Navigator.push<QrScanResult>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result == null || !mounted) return;

    _expectedHashController.text = result.hash;

    _showSnack(
      result.fileName != null
          ? 'Hash loaded from QR · ${result.fileName}'
          : 'Hash loaded from QR',
    );
  }

  // ── QR: show share sheet for a computed hash ──────────────────────────────

  void _shareQr() {
    if (_sha256Hash == null) return;
    showQrSheet(
      context,
      hash: _sha256Hash!,
      fileName: _fileName ?? 'unknown',
      fileSize: _fileSize,
      timestamp: _hashTimestamp,
    );
  }

  // ── QR: from idle screen — generate QR for a manually pasted hash ─────────

  void _shareQrFromPasted() {
    final hash = _expectedHashController.text.trim().toLowerCase();
    if (hash.isEmpty) {
      _showSnack('Paste a fingerprint first.', isError: true);
      return;
    }
    if (hash.length != 64 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      _showSnack('That doesn\'t look like a valid SHA-256 hash.', isError: true);
      return;
    }
    showQrSheet(
      context,
      hash: hash,
      fileName: 'shared fingerprint',
      timestamp: DateTime.now(),
    );
  }

  // ── File pick + hash ──────────────────────────────────────────────────────

  Future<void> _pickAndVerify() async {
    final expectedHash = _expectedHashController.text.trim().toLowerCase();

    if (expectedHash.isEmpty) {
      _showSnack('Paste the shared file fingerprint first.', isError: true);
      return;
    }

    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final bytes = picked.bytes ??
        (picked.path != null ? await File(picked.path!).readAsBytes() : null);

    if (bytes == null) {
      _showSnack('Could not read file.', isError: true);
      return;
    }

    setState(() {
      _fileName = picked.name;
      _fileSize = picked.size;
      _sha256Hash = null;
      _hashMatches = null;
      _hashTimestamp = null;
      _errorMessage = null;
      _state = _VerifyState.hashing;
      _progressLabel = 'Reading file bytes…';
    });

    _resultCtrl.reset();

    await Future.delayed(const Duration(milliseconds: 80));
    setState(() => _progressLabel = 'Computing SHA-256 fingerprint…');
    await Future.delayed(const Duration(milliseconds: 60));

    final digest = sha256.convert(bytes);
    final hash = digest.toString();
    final now = DateTime.now();

    setState(() {
      _sha256Hash = hash;
      _hashTimestamp = now;
      _state = _VerifyState.checking;
      _progressLabel = 'Comparing with shared fingerprint…';
    });

    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    final matches = hash.toLowerCase() == expectedHash;

    _resultCtrl.forward();
    setState(() {
      _hashMatches = matches;
      _state = _VerifyState.result;
      _progressLabel = '';
    });
  }

  void _reset() {
    _resultCtrl.reset();
    _expectedHashController.clear();
    setState(() {
      _state = _VerifyState.idle;
      _fileName = null;
      _fileSize = null;
      _sha256Hash = null;
      _hashMatches = null;
      _hashTimestamp = null;
      _errorMessage = null;
      _progressLabel = '';
    });
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('$label copied');
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: isError ? _danger : _success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  static String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _surface,
        colorScheme: const ColorScheme.dark(primary: _accent),
      ),
      child: Scaffold(
        backgroundColor: _surface,
        appBar: _buildAppBar(),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.025),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: _buildBody(),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
        backgroundColor: _surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: const Icon(
              Icons.chevron_left_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
          onPressed: () async {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
              return;
            }
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const DashboardScreen()),
              (route) => false,
            );
          },
        ),
        title: Text(
          'Verify File',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      );

  Widget _buildBody() {
    switch (_state) {
      case _VerifyState.idle:
        return _buildIdle();
      case _VerifyState.hashing:
      case _VerifyState.checking:
        return _buildProgress();
      case _VerifyState.result:
        return _buildResult();
      case _VerifyState.error:
        return _buildError();
    }
  }

  // ── Idle screen ───────────────────────────────────────────────────────────

  Widget _buildIdle() {
    return SingleChildScrollView(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              size: 36,
              color: _accent,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Public File Verification',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Paste the shared SHA-256 fingerprint,\nthen select a file to verify its integrity.',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: Colors.grey[500],
              height: 1.6,
            ),
          ),
          const SizedBox(height: 28),

          // ── fingerprint input card ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Shared File Fingerprint',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[400],
                      ),
                    ),
                    const Spacer(),
                    // ── SCAN QR BUTTON (idle) ──────────────────────────────
                    GestureDetector(
                      onTap: _scanQr,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _accent.withOpacity(0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.qr_code_scanner_rounded,
                                size: 13, color: _accent),
                            const SizedBox(width: 5),
                            Text(
                              'Scan QR',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _expectedHashController,
                  maxLines: 3,
                  style: GoogleFonts.sourceCodePro(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.5,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Paste SHA-256 hash here…',
                    hintStyle: GoogleFonts.sourceCodePro(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: _surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _accent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── GENERATE QR from pasted hash (idle) ───────────────────
                GestureDetector(
                  onTap: _shareQrFromPasted,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.qr_code_2_rounded,
                            size: 15, color: _accent),
                        const SizedBox(width: 7),
                        Text(
                          'Generate QR from this fingerprint',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── file picker drop zone ─────────────────────────────────────
          GestureDetector(
            onTap: _pickAndVerify,
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _accent.withOpacity(0.4), width: 1.5),
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.upload_file_rounded,
                      size: 28,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tap to select a file',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The file is hashed locally and checked against the shared fingerprint',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12.5,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),
          _buildHowItWorks(),
        ],
      ),
    );
  }

  // ── How it works ──────────────────────────────────────────────────────────

  Widget _buildHowItWorks() {
    final steps = [
      (
        Icons.fingerprint_rounded,
        'Paste the public SHA-256 fingerprint shared by the original uploader — or scan a QR'
      ),
      (
        Icons.upload_file_rounded,
        'Select the file you want to check — the file stays on your device'
      ),
      (
        Icons.compare_arrows_rounded,
        'The app computes SHA-256 locally and compares both fingerprints'
      ),
      (
        Icons.check_circle_outlined,
        'If they match, the file is intact. If not, it was modified or is different'
      ),
      (
        Icons.qr_code_2_rounded,
        'Share a QR of any fingerprint — recipients verify offline, no internet needed'
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How verification works',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 16),
          ...steps.asMap().entries.map((e) {
            final isLast = e.key == steps.length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(e.value.$1, size: 15, color: _accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        e.value.$2,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12.5,
                          color: Colors.grey[500],
                          height: 1.55,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Progress screen ───────────────────────────────────────────────────────

  Widget _buildProgress() {
    final isChecking = _state == _VerifyState.checking;

    return Center(
      key: const ValueKey('progress'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_fileName != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                margin: const EdgeInsets.only(bottom: 32),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.insert_drive_file_rounded,
                        size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        _fileName!,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          color: Colors.grey[400],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: 46,
              height: 46,
              child: CircularProgressIndicator(
                strokeWidth: 2.8,
                color: isChecking ? _success : _accent,
              ),
            ),
            const SizedBox(height: 28),
            _stepRow(
              icon: Icons.fingerprint_rounded,
              label: 'Compute SHA-256',
              done: isChecking,
              active: !isChecking,
            ),
            const SizedBox(height: 10),
            _stepRow(
              icon: Icons.compare_arrows_rounded,
              label: 'Compare fingerprint',
              done: false,
              active: isChecking,
            ),
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: Text(
                _progressLabel,
                key: ValueKey(_progressLabel),
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  color: Colors.grey[500],
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepRow({
    required IconData icon,
    required String label,
    required bool done,
    required bool active,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: done
              ? const Icon(Icons.check_circle_rounded,
                  size: 18, color: _success)
              : active
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: _accent,
                      ),
                    )
                  : Icon(Icons.radio_button_unchecked_rounded,
                      size: 18, color: Colors.grey[700]),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            color: done
                ? _success
                : active
                    ? Colors.white
                    : Colors.grey[700],
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // ── Result screen ─────────────────────────────────────────────────────────

  Widget _buildResult() {
    final verified = _hashMatches ?? false;
    final expectedHash = _expectedHashController.text.trim();

    return SingleChildScrollView(
      key: const ValueKey('result'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: FadeTransition(
        opacity: _resultFade,
        child: SlideTransition(
          position: _resultSlide,
          child: Column(
            children: [
              // ── verdict banner ──────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: (verified ? _success : _danger).withOpacity(0.07),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (verified ? _success : _danger).withOpacity(0.22),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            (verified ? _success : _danger).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        verified
                            ? Icons.verified_rounded
                            : Icons.gpp_bad_rounded,
                        color: verified ? _success : _danger,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            verified
                                ? 'File matches shared fingerprint'
                                : 'File does not match shared fingerprint',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            verified
                                ? 'This file is intact and matches the public fingerprint exactly.'
                                : 'This file differs from the shared fingerprint. It may be modified, corrupted, or a completely different file.',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 12.5,
                              color: Colors.grey[500],
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── QR SHARE BUTTON (result screen) ────────────────────────
              _qrShareCard(),

              const SizedBox(height: 12),

              _infoCard(
                title: 'File',
                rows: [
                  ('Name', _fileName ?? '—'),
                  if (_fileSize != null) ('Size', _fmtSize(_fileSize!)),
                ],
              ),
              const SizedBox(height: 12),
              _hashCard(
                title: 'Computed SHA-256',
                value: _sha256Hash ?? '',
                copyLabel: 'Computed hash',
              ),
              const SizedBox(height: 12),
              _hashCard(
                title: 'Shared SHA-256',
                value: expectedHash,
                copyLabel: 'Shared hash',
              ),
              const SizedBox(height: 12),
              _primaryBtn(
                label: 'Verify another file',
                icon: Icons.upload_file_rounded,
                onTap: _pickAndVerify,
              ),
              const SizedBox(height: 10),
              _secondaryBtn(label: 'Clear', onTap: _reset),
            ],
          ),
        ),
      ),
    );
  }

  /// QR share card shown on the result screen.
  Widget _qrShareCard() {
    return GestureDetector(
      onTap: _shareQr,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _accent.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.qr_code_2_rounded,
                  size: 20, color: _accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Share fingerprint as QR',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Anyone can scan and verify offline — no internet needed',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.chevron_right_rounded,
                  size: 16, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reusable widgets ──────────────────────────────────────────────────────

  Widget _hashCard({
    required String title,
    required String value,
    required String copyLabel,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fingerprint_rounded, size: 14, color: _accent),
              const SizedBox(width: 7),
              Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: GoogleFonts.sourceCodePro(
                      fontSize: 11,
                      color: Colors.grey[400],
                      height: 1.55,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _copy(value, copyLabel),
                  child: Icon(Icons.copy_rounded,
                      size: 15, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      key: const ValueKey('error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _danger.withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _danger.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: _danger, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage ?? 'Something went wrong.',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        color: _danger,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _primaryBtn(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onTap: _reset,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({
    required String title,
    required List<(String, String)> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 10),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    r.$1,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.$2,
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryBtn({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) =>
      SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );

  Widget _secondaryBtn({
    required String label,
    required VoidCallback onTap,
  }) =>
      SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey[400],
            side: BorderSide(color: _border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}

enum _VerifyState { idle, hashing, checking, result, error }