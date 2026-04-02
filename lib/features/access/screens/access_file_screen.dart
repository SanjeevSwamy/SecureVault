import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:secure_vault/services/filebase_service.dart';
import 'package:secure_vault/services/wallet_service.dart';
import 'package:secure_vault/features/dashboard/screens/dashboard_screen.dart';

// ---------------------------------------------------------------------------
//  FILE ACCESS SCREEN
//  "Reliable. Clean. Understandable. Safe."
// ---------------------------------------------------------------------------

class FileAccessScreen extends StatefulWidget {
  final String? prefillCid;
  const FileAccessScreen({super.key, this.prefillCid});

  @override
  State<FileAccessScreen> createState() => _FileAccessScreenState();
}

class _FileAccessScreenState extends State<FileAccessScreen>
    with TickerProviderStateMixin {
  // ── Controllers ──────────────────────────────────────────────────────────
  final TextEditingController _hashController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // ── Animation ────────────────────────────────────────────────────────────
  late AnimationController _slideController;
  late Animation<Offset> _slideAnim;

  // ── State ─────────────────────────────────────────────────────────────────
  _ScreenView _currentView = _ScreenView.input;
  bool _isLoadingFiles = false;
  int _loadingStep = 0;
  String _statusMessage = '';
  String _fileName = '';
  String _fileSize = '';
  String _txHash = '';
  String _rawHash = '';
  String _fileCid = '';
  Uint8List? _decryptedFileData;
  String _detectedFileType = '';

  // ── Search / file list ───────────────────────────────────────────────────
  List<Map<String, dynamic>> _userFiles = [];
  List<Map<String, dynamic>> _filteredFiles = [];
  String _searchQuery = '';

  // ── Loading status lines ─────────────────────────────────────────────────
  static const List<String> _loadingSteps = [
    'Connecting to IPFS nodes…',
    'Locating content on network…',
    'Downloading encrypted chunks…',
    'Assembling file fragments…',
    'Decrypting with your key…',
    'Verifying integrity…',
  ];

  // ── Palette — blue + green + red + grays only ────────────────────────────
  static const Color _accent  = Color(0xFF2563EB);
  static const Color _success = Color(0xFF10B981);
  static const Color _danger  = Color(0xFFEF4444);
  static const Color _surface = Color(0xFF0F172A);
  static const Color _card    = Color(0xFF1E293B);
  static const Color _border  = Color(0xFF334155);

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    if (widget.prefillCid != null) {
      _hashController.text = widget.prefillCid!;
    }

    _searchController.addListener(() {
      setState(() {
        _searchQuery   = _searchController.text.toLowerCase();
        _filteredFiles = _userFiles.where((f) {
          final name = (f['name'] ?? f['cid'] ?? '').toString().toLowerCase();
          return name.contains(_searchQuery);
        }).toList();
      });
    });
  }

  @override
  void dispose() {
    _hashController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  // ── Logic ─────────────────────────────────────────────────────────────────

  Future<void> _loadUserFiles() async {
    setState(() => _isLoadingFiles = true);
    try {
      final walletData = await SessionWalletService.getSessionWalletData();
      final address    = walletData['address'] ?? '';
      if (address.isEmpty) throw Exception('No wallet connected');
      final files = await FilebaseService.getUserFiles(address);
      setState(() {
        _userFiles     = List<Map<String, dynamic>>.from(files);
        _filteredFiles = _userFiles;
      });
    } catch (e) {
      _showSnack('Could not load files: $e', isError: true);
    } finally {
      setState(() => _isLoadingFiles = false);
    }
  }

Future<void> _decryptFile({String? cid}) async {
  final hash = cid ?? _hashController.text.trim();
  if (hash.isEmpty) {
    setState(() => _statusMessage = 'Please enter a valid CID.');
    return;
  }

  setState(() {
    _loadingStep = 0;
    _statusMessage = '';
    _currentView = _ScreenView.loading;
  });

  Timer? loadingTimer;
  int step = 0;

  loadingTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
    if (!mounted) return;
    if (step < _loadingSteps.length - 1) {
      step++;
      setState(() => _loadingStep = step);
    }
  });

  try {
    final walletData = await SessionWalletService.getSessionWalletData();
    final address = walletData['address'] ?? '';
    if (address.isEmpty) throw Exception('No wallet connected');

    final data = await FilebaseService.downloadDecryptedFile(
      cid: hash,
      walletAddress: address,
    );
    if (data == null) throw Exception('File not found or decryption failed');

    String foundTxHash = '';
    String foundName = _extractFileNameFromCID(hash);
    String foundRawHash = '';

    // ✅ Use cached files instead of API call
    final fileMeta = _userFiles.firstWhere(
      (f) => f['cid'] == hash,
      orElse: () => {},
    );

    foundTxHash = fileMeta['txHash'] ?? '';
    foundRawHash = fileMeta['rawHash'] ?? '';
    if ((fileMeta['name'] ?? '').toString().isNotEmpty) {
      foundName = fileMeta['name'];
    }

    loadingTimer.cancel();

    if (!mounted) return;
    _slideController
      ..reset()
      ..forward();

    setState(() {
      _decryptedFileData = data;
      _currentView = _ScreenView.decrypted;
      _fileName = foundName;
      _fileSize = _formatFileSize(data.length);
      _txHash = foundTxHash;
      _rawHash = foundRawHash;
      _fileCid = hash;
      _detectedFileType = _detectFileType(data, foundName);
      _statusMessage = '';
    });
  } catch (e) {
    loadingTimer.cancel();
    if (!mounted) return;
    setState(() {
      _currentView = _ScreenView.input;
      _statusMessage = e.toString().replaceAll('Exception:', '').trim();
    });
  }
}

  String _extractFileNameFromCID(String cid) {
    try {
      final parts = cid.split('_');
      if (parts.length >= 3) return parts.sublist(1, parts.length - 1).join('_');
      if (parts.length == 2) return parts.last;
    } catch (_) {}
    return 'File_${cid.substring(0, 8)}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _detectFileType(Uint8List data, String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) return 'image';
    if (ext == 'pdf') return 'pdf';
    if (['txt', 'md', 'json', 'csv', 'log', 'xml', 'yaml', 'yml'].contains(ext)) return 'text';
    if (data.length >= 4) {
      if (data[0] == 0x89 && data[1] == 0x50) return 'image'; // PNG
      if (data[0] == 0xFF && data[1] == 0xD8) return 'image'; // JPEG
      if (data[0] == 0x25 && data[1] == 0x50 &&
          data[2] == 0x44 && data[3] == 0x46) return 'pdf';   // PDF
    }
    return 'binary';
  }

  Future<void> _downloadFile() async {
    if (_decryptedFileData == null) return;
    try {
      final dir  = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      await file.writeAsBytes(_decryptedFileData!);
      if (!mounted) return;
      _showSnack('Saved to Documents');
    } catch (e) {
      _showSnack('Download failed: $e', isError: true);
    }
  }

  Future<void> _shareFile() async {
    if (_decryptedFileData == null) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final file    = File('${tempDir.path}/$_fileName');
      await file.writeAsBytes(_decryptedFileData!);
      await Share.shareXFiles([XFile(file.path)], subject: _fileName);
    } catch (e) {
      _showSnack('Share failed: $e', isError: true);
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('Copied to clipboard');
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.spaceGrotesk(
              color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: isError ? _danger : _success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: _buildCurrentView(),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
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
          child: const Icon(Icons.chevron_left_rounded,
              size: 20, color: Colors.white),
        ),
        onPressed: () => Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (r) => false,
        ),
      ),
      title: Text(
        'Secure Files',
        style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white),
      ),
      centerTitle: true,
      actions: [
        if (_currentView != _ScreenView.loading)
          IconButton(
            tooltip: 'Browse files',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _currentView == _ScreenView.search
                    ? _accent.withOpacity(0.15)
                    : _card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _currentView == _ScreenView.search
                      ? _accent.withOpacity(0.5)
                      : _border,
                ),
              ),
              child: Icon(
                Icons.folder_open_rounded,
                size: 18,
                color: _currentView == _ScreenView.search
                    ? _accent
                    : Colors.grey[500],
              ),
            ),
            onPressed: () {
              if (_currentView == _ScreenView.search) {
                setState(() => _currentView = _ScreenView.input);
              } else {
                setState(() => _currentView = _ScreenView.search);
                if (_userFiles.isEmpty) _loadUserFiles();
              }
            },
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildCurrentView() {
    switch (_currentView) {
      case _ScreenView.input:     return _buildInputView();
      case _ScreenView.search:    return _buildSearchView();
      case _ScreenView.loading:   return _buildLoadingView();
      case _ScreenView.decrypted: return _buildDecryptedView();
    }
  }

  // ── INPUT VIEW ─────────────────────────────────────────────────────────────

  Widget _buildInputView() {
    return SingleChildScrollView(
      key: const ValueKey('InputView'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Small icon badge — not a giant glow circle
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: const Icon(Icons.lock_outline_rounded,
              size: 28, color: _accent),
        ),
        const SizedBox(height: 24),

        Text(
          'Access file by CID',
          textAlign: TextAlign.center,
          style: GoogleFonts.spaceGrotesk(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter a content identifier to retrieve and decrypt\na file stored on IPFS.',
          textAlign: TextAlign.center,
          style: GoogleFonts.spaceGrotesk(
              fontSize: 14, color: Colors.grey[500], height: 1.55),
        ),
        const SizedBox(height: 32),

        // CID input
        Container(
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _hashController,
                style: GoogleFonts.sourceCodePro(
                    fontSize: 13,
                    color: Colors.white,
                    letterSpacing: 0.4),
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Paste CID here…',
                  hintStyle: GoogleFonts.sourceCodePro(
                      fontSize: 13, color: Colors.grey[600]),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: IconButton(
                icon: Icon(Icons.content_paste_rounded,
                    size: 18, color: Colors.grey[600]),
                tooltip: 'Paste',
                onPressed: () async {
                  final d = await Clipboard.getData('text/plain');
                  if (d?.text != null) _hashController.text = d!.text!;
                },
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),

        _primaryButton(
          label: 'Open File',
          icon: Icons.lock_open_rounded,
          onTap: _decryptFile,
        ),
        const SizedBox(height: 32),

        Row(children: [
          Expanded(child: Divider(color: _border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text('or',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, color: Colors.grey[600])),
          ),
          Expanded(child: Divider(color: _border)),
        ]),
        const SizedBox(height: 20),

        TextButton.icon(
          onPressed: () {
            setState(() => _currentView = _ScreenView.search);
            if (_userFiles.isEmpty) _loadUserFiles();
          },
          icon: Icon(Icons.folder_open_rounded,
              size: 16, color: Colors.grey[500]),
          label: Text('Browse files',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w600)),
        ),

        if (_statusMessage.isNotEmpty) ...[
          const SizedBox(height: 24),
          _errorBanner(_statusMessage),
        ],
        const SizedBox(height: 32),
      ]),
    );
  }

  // ── SEARCH / BROWSE VIEW ───────────────────────────────────────────────────

  Widget _buildSearchView() {
    return Column(
      key: const ValueKey('SearchView'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Row(children: [
              const SizedBox(width: 14),
              Icon(Icons.search_rounded, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 14, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by name or CID…',
                    hintStyle: GoogleFonts.spaceGrotesk(
                        fontSize: 14, color: Colors.grey[600]),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: 16, color: Colors.grey[600]),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _filteredFiles = _userFiles);
                  },
                ),
            ]),
          ),
        ),

        // Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Row(children: [
            Text(
              '${_filteredFiles.length} file${_filteredFiles.length == 1 ? '' : 's'}',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 12, color: Colors.grey[600]),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _loadUserFiles,
              icon: Icon(Icons.refresh_rounded,
                  size: 14, color: Colors.grey[600]),
              label: Text('Refresh',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, color: Colors.grey[600])),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6)),
            ),
          ]),
        ),

        Expanded(
          child: _isLoadingFiles
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                        color: _accent, strokeWidth: 2.4),
                  ),
                  const SizedBox(height: 14),
                  Text('Loading…',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 13, color: Colors.grey[600])),
                ]))
              : _filteredFiles.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Icon(Icons.folder_off_rounded,
                            size: 40, color: Colors.grey[800]),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No results for "$_searchQuery"'
                              : 'No files in your vault',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 14, color: Colors.grey[600]),
                        ),
                      ]))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
                      itemCount: _filteredFiles.length,
                      itemBuilder: (_, i) =>
                          _fileListTile(_filteredFiles[i]),
                    ),
        ),
      ],
    );
  }

  Widget _fileListTile(Map<String, dynamic> file) {
    final name = (file['name'] ??
            _extractFileNameFromCID(file['cid'] ?? ''))
        .toString();
    final cid  = (file['cid'] ?? '').toString();
    final size = file['size'] != null
        ? _formatFileSize(int.tryParse(file['size'].toString()) ?? 0)
        : '—';
    final date = file['uploadedAt'] ?? '';
    final ext  = name.split('.').last.toLowerCase();

    return GestureDetector(
      onTap: () => _decryptFile(cid: cid),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          // Real icon, not an emoji
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _fileIconColor(ext).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(_fileIconData(ext),
                  size: 20, color: _fileIconColor(ext)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(name,
                  style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.white),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(
                [if (size != '—') size, if (date.isNotEmpty) date]
                    .join('  ·  '),
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, color: Colors.grey[600]),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          // Trailing chevron — no "Decrypt" chip needed, tile is tappable
          Icon(Icons.chevron_right_rounded,
              size: 18, color: Colors.grey[700]),
        ]),
      ),
    );
  }

  // ── LOADING VIEW ───────────────────────────────────────────────────────────

  Widget _buildLoadingView() {
    final stepLabel =
        _loadingSteps[_loadingStep.clamp(0, _loadingSteps.length - 1)];

    return Center(
      key: const ValueKey('LoadingView'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                  strokeWidth: 2.8, color: _accent),
            ),
            const SizedBox(height: 28),
            Text(
              'Retrieving file…',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: Text(
                stepLabel,
                key: ValueKey(stepLabel),
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    color: Colors.grey[500],
                    height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── DECRYPTED VIEW ─────────────────────────────────────────────────────────

  Widget _buildDecryptedView() {
    return SingleChildScrollView(
      key: const ValueKey('DecryptedView'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: SlideTransition(
        position: _slideAnim,
        child: Column(children: [
          _buildSuccessHeader(),
          const SizedBox(height: 20),

          _buildFileCard(),
          const SizedBox(height: 12),

          _buildPreviewSection(),
          const SizedBox(height: 12),

          if (_txHash.isNotEmpty) _buildVerificationCard(),
          if (_txHash.isNotEmpty) const SizedBox(height: 12),

          if (_rawHash.isNotEmpty) _buildPublicVerificationCard(),
if (_rawHash.isNotEmpty) const SizedBox(height: 12),

          _buildCidRow(),
          const SizedBox(height: 24),

          _buildActionButtons(),
        ]),
      ),
    );
  }

  Widget _buildSuccessHeader() {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _success.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.check_circle_rounded,
            color: _success, size: 22),
      ),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('File ready',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        Text('Decrypted and verified successfully',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 13, color: Colors.grey[500])),
      ]),
    ]);
  }
  Widget _buildPublicVerificationCard() {
  final shortHash = _rawHash.length > 20
      ? '${_rawHash.substring(0, 10)}…${_rawHash.substring(_rawHash.length - 10)}'
      : _rawHash;

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
            const Icon(Icons.fingerprint_rounded, size: 18, color: _accent),
            const SizedBox(width: 8),
            Text(
              'Public Verification',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'This SHA-256 fingerprint can be shared with others so they can verify the original file is unchanged.',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            color: Colors.grey[500],
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  shortHash,
                  style: GoogleFonts.sourceCodePro(
                    fontSize: 12,
                    color: Colors.grey[400],
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _copyToClipboard(_rawHash),
                child: Icon(
                  Icons.copy_rounded,
                  size: 15,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            Share.share(
              'Public File Fingerprint (SHA-256):\n$_rawHash',
              subject: 'File Verification Fingerprint',
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Share fingerprint',
                style: GoogleFonts.spaceGrotesk(
                  color: _accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.share_rounded, size: 13, color: _accent),
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _buildFileCard() {
    final ext = _fileName.split('.').last.toLowerCase();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _fileIconColor(ext).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Icon(_fileIconData(ext),
                size: 22, color: _fileIconColor(ext)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(_fileName,
                style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Colors.white),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              '$_fileSize  ·  ${ext.toUpperCase()}',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 12, color: Colors.grey[500]),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── PREVIEW SECTION — thumbnail + open button ─────────────────────────────

  Widget _buildPreviewSection() {
    if (_decryptedFileData == null) return const SizedBox.shrink();

    if (_detectedFileType == 'image') return _buildImagePreviewCard();
    if (_detectedFileType == 'pdf')   return _buildPdfPreviewCard();
    if (_detectedFileType == 'text')  return _buildTextPreviewCard();
    return const SizedBox.shrink(); // binary — no preview card shown
  }

  // Image: blurred/cropped thumbnail + "Open image" button
  Widget _buildImagePreviewCard() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Thumbnail strip — fixed height, cover-cropped
        Stack(children: [
          SizedBox(
            width: double.infinity,
            height: 160,
            child: Image.memory(
              _decryptedFileData!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 160,
                color: _surface,
                child: Center(
                  child: Icon(Icons.broken_image_rounded,
                      size: 36, color: Colors.grey[700]),
                ),
              ),
            ),
          ),
          // Subtle dark gradient at bottom so label is readable
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
                ),
              ),
            ),
          ),
          // "Tap to expand" hint
          const Positioned(
            bottom: 10, right: 12,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.open_in_full_rounded, size: 12, color: Colors.white70),
              SizedBox(width: 4),
              Text('Tap to expand',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
          // Full-area tap target
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openImageViewer(),
              ),
            ),
          ),
        ]),

        // Bottom bar with label + open button
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(children: [
            Icon(Icons.image_rounded,
                size: 16, color: Colors.grey[500]),
            const SizedBox(width: 8),
            Text('Image preview',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[400])),
            const Spacer(),
            _previewChip(
              label: 'Open image',
              icon: Icons.open_in_full_rounded,
              onTap: _openImageViewer,
            ),
          ]),
        ),
      ]),
    );
  }

  // PDF: icon + page-count placeholder + "Open PDF" button
  Widget _buildPdfPreviewCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        // PDF icon tile
        Container(
          width: 52,
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFFEF4444).withOpacity(0.2)),
          ),
          child: const Center(
            child: Icon(Icons.picture_as_pdf_rounded,
                size: 26, color: Color(0xFFEF4444)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('PDF document',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
            const SizedBox(height: 3),
            Text('Tap to open full viewer',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, color: Colors.grey[600])),
          ]),
        ),
        const SizedBox(width: 8),
        _previewChip(
          label: 'Open PDF',
          icon: Icons.open_in_new_rounded,
          onTap: _openPdfViewer,
        ),
      ]),
    );
  }

  // Text: small scrollable snippet + "Open" button
  Widget _buildTextPreviewCard() {
    final text = String.fromCharCodes(_decryptedFileData!);
    final snippet = text.length > 300
        ? '${text.substring(0, 300)}…'
        : text;

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Snippet
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          child: Text(snippet,
              style: GoogleFonts.sourceCodePro(
                  fontSize: 11.5,
                  color: Colors.grey[500],
                  height: 1.6),
              maxLines: 6,
              overflow: TextOverflow.fade),
        ),
        const SizedBox(height: 10),
        const Divider(height: 1, color: Color(0xFF334155)),
        // Bottom bar
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(children: [
            Icon(Icons.notes_rounded, size: 15, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Text('Text file',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[400])),
            const Spacer(),
            _previewChip(
              label: 'Open full',
              icon: Icons.open_in_full_rounded,
              onTap: _openTextViewer,
            ),
          ]),
        ),
      ]),
    );
  }

  // Small tappable chip used in all preview cards
  Widget _previewChip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _accent.withOpacity(0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: _accent),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _accent)),
        ]),
      ),
    );
  }

  // ── Viewer launchers ──────────────────────────────────────────────────────

  void _openImageViewer() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ImageViewerPage(
        data: _decryptedFileData!,
        fileName: _fileName,
      ),
    ));
  }

  void _openPdfViewer() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PdfViewerPage(
        data: _decryptedFileData!,
        fileName: _fileName,
      ),
    ));
  }

  void _openTextViewer() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _TextViewerPage(
        data: _decryptedFileData!,
        fileName: _fileName,
      ),
    ));
  }

  Widget _buildVerificationCard() {
    final shortHash = _txHash.length > 16
        ? '${_txHash.substring(0, 8)}…${_txHash.substring(_txHash.length - 8)}'
        : _txHash;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header — neutral card, green verified badge, no orange
        Row(children: [
          const Icon(Icons.verified_outlined, size: 18, color: _success),
          const SizedBox(width: 8),
          Text('Verification',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('Verified',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _success)),
          ),
        ]),
        const SizedBox(height: 10),

        Text(
          'A matching verification record was found on Ethereum Sepolia.',
          style: GoogleFonts.spaceGrotesk(
              fontSize: 13, color: Colors.grey[500], height: 1.5),
        ),
        const SizedBox(height: 12),

        // Hash
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(
              child: Text(shortHash,
                  style: GoogleFonts.sourceCodePro(
                      fontSize: 12, color: Colors.grey[400])),
            ),
            GestureDetector(
              onTap: () => _copyToClipboard(_txHash),
              child: Icon(Icons.copy_rounded,
                  size: 15, color: Colors.grey[600]),
            ),
          ]),
        ),
        const SizedBox(height: 12),

        GestureDetector(
          onTap: () async {
            final uri =
                Uri.parse('https://sepolia.etherscan.io/tx/$_txHash');
            if (await canLaunchUrl(uri)) await launchUrl(uri);
          },
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('View on Etherscan',
                style: GoogleFonts.spaceGrotesk(
                    color: _accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new_rounded,
                size: 13, color: _accent),
          ]),
        ),
      ]),
    );
  }

  Widget _buildCidRow() {
    final shortCid = _fileCid.length > 20
        ? '${_fileCid.substring(0, 10)}…${_fileCid.substring(_fileCid.length - 10)}'
        : _fileCid;

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        Text('CID',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(shortCid,
              style: GoogleFonts.sourceCodePro(
                  fontSize: 12, color: Colors.grey[500])),
        ),
        GestureDetector(
          onTap: () => _copyToClipboard(_fileCid),
          child: Icon(Icons.copy_rounded,
              size: 15, color: Colors.grey[600]),
        ),
      ]),
    );
  }

  Widget _buildActionButtons() {
    return Column(children: [
      _primaryButton(
        label: 'Download',
        icon: Icons.download_rounded,
        onTap: _downloadFile,
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _secondaryButton(
            label: 'Share',
            icon: Icons.share_rounded,
            onTap: _shareFile,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _secondaryButton(
            label: 'New search',
            icon: Icons.search_rounded,
           onTap: () => setState(() {
  _currentView = _ScreenView.input;
  _hashController.clear();
  _rawHash = '';
}),
          ),
        ),
      ]),
    ]);
  }

  // ── Reusable widgets ───────────────────────────────────────────────────────

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w700, fontSize: 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label,
            style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w600, fontSize: 14)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.grey[300],
          side: BorderSide(color: _border),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _errorBanner(String msg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _danger.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _danger.withOpacity(0.2)),
        ),
        child: Row(children: [
          Icon(Icons.error_outline_rounded, size: 16, color: _danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: GoogleFonts.spaceGrotesk(
                    color: _danger,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        ]),
      );

  // ── File type helpers ──────────────────────────────────────────────────────

  IconData _fileIconData(String ext) {
    switch (ext) {
      case 'pdf':                                        return Icons.picture_as_pdf_rounded;
      case 'jpg': case 'jpeg':
      case 'png': case 'gif': case 'webp':              return Icons.image_rounded;
      case 'mp4': case 'mov': case 'avi':               return Icons.movie_rounded;
      case 'mp3': case 'wav':                           return Icons.audio_file_rounded;
      case 'doc': case 'docx':                          return Icons.description_rounded;
      case 'xls': case 'xlsx':                          return Icons.table_chart_rounded;
      case 'zip': case 'rar':                           return Icons.folder_zip_rounded;
      case 'txt': case 'md':                            return Icons.notes_rounded;
      default:                                          return Icons.insert_drive_file_rounded;
    }
  }

  Color _fileIconColor(String ext) {
    switch (ext) {
      case 'pdf':                                        return const Color(0xFFEF4444);
      case 'jpg': case 'jpeg':
      case 'png': case 'gif': case 'webp':              return const Color(0xFF8B5CF6);
      case 'mp4': case 'mov': case 'avi':               return const Color(0xFF3B82F6);
      case 'mp3': case 'wav':                           return const Color(0xFFEC4899);
      case 'doc': case 'docx':                          return const Color(0xFF2563EB);
      case 'xls': case 'xlsx':                          return const Color(0xFF10B981);
      case 'zip': case 'rar':                           return const Color(0xFFF59E0B);
      case 'txt': case 'md':                            return const Color(0xFF64748B);
      default:                                          return const Color(0xFF64748B);
    }
  }
}

// ── Screen state enum ──────────────────────────────────────────────────────────
enum _ScreenView { input, search, loading, decrypted }

// ── Shared viewer colours (mirrors the main screen palette) ──────────────────
const _vSurface = Color(0xFF0F172A);
const _vCard    = Color(0xFF1E293B);
const _vBorder  = Color(0xFF334155);

// ─────────────────────────────────────────────────────────────────────────────
//  IMAGE VIEWER PAGE — pinch-to-zoom, double-tap to zoom, tap to toggle UI
// ─────────────────────────────────────────────────────────────────────────────

class _ImageViewerPage extends StatefulWidget {
  final Uint8List data;
  final String fileName;
  const _ImageViewerPage({required this.data, required this.fileName});

  @override
  State<_ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<_ImageViewerPage> {
  final TransformationController _transform = TransformationController();
  bool _showUI = true;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _doubleTapZoom(TapDownDetails details) {
    if (_transform.value != Matrix4.identity()) {
      _transform.value = Matrix4.identity();
    } else {
      final pos = details.localPosition;
      _transform.value = Matrix4.identity()
        ..translate(-pos.dx * 1.5, -pos.dy * 1.5)
        ..scale(2.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _showUI
          ? AppBar(
              backgroundColor: Colors.black.withOpacity(0.55),
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                widget.fileName,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                  tooltip: 'Reset zoom',
                  onPressed: () => _transform.value = Matrix4.identity(),
                ),
                const SizedBox(width: 4),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _showUI = !_showUI),
        onDoubleTapDown: _doubleTapZoom,
        onDoubleTap: () {},
        child: Center(
          child: InteractiveViewer(
            transformationController: _transform,
            minScale: 0.5,
            maxScale: 6.0,
            child: Image.memory(
              widget.data,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_rounded, size: 52, color: Colors.grey[700]),
                  const SizedBox(height: 12),
                  Text('Could not render image.',
                      style: GoogleFonts.spaceGrotesk(
                          color: Colors.grey[500], fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PDF VIEWER PAGE — syncfusion_flutter_pdfviewer, full scroll + zoom
// ─────────────────────────────────────────────────────────────────────────────

class _PdfViewerPage extends StatefulWidget {
  final Uint8List data;
  final String fileName;
  const _PdfViewerPage({required this.data, required this.fileName});

  @override
  State<_PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<_PdfViewerPage> {
  final PdfViewerController _pdfController = PdfViewerController();
  int _currentPage = 1;
  int _totalPages  = 1;

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _vSurface,
      appBar: AppBar(
        backgroundColor: _vCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.fileName,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                overflow: TextOverflow.ellipsis),
            Text('Page $_currentPage of $_totalPages',
                style: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_in_rounded, color: Colors.white70, size: 22),
            tooltip: 'Zoom in',
            onPressed: () => _pdfController.zoomLevel =
                (_pdfController.zoomLevel + 0.25).clamp(0.75, 4.0),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out_rounded, color: Colors.white70, size: 22),
            tooltip: 'Zoom out',
            onPressed: () => _pdfController.zoomLevel =
                (_pdfController.zoomLevel - 0.25).clamp(0.75, 4.0),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SfPdfViewer.memory(
        widget.data,
        controller: _pdfController,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        pageLayoutMode: PdfPageLayoutMode.continuous,
        onPageChanged: (PdfPageChangedDetails details) {
          setState(() => _currentPage = details.newPageNumber);
        },
        onDocumentLoaded: (PdfDocumentLoadedDetails details) {
          setState(() => _totalPages = details.document.pages.count);
        },
        onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to load PDF: ${details.error}',
                style: GoogleFonts.spaceGrotesk(color: Colors.white)),
            backgroundColor: const Color(0xFFEF4444),
          ));
        },
      ),
      bottomNavigationBar: Container(
        height: 52,
        decoration: BoxDecoration(
          color: _vCard,
          border: Border(top: BorderSide(color: _vBorder)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70),
              onPressed: _currentPage > 1 ? () => _pdfController.previousPage() : null,
            ),
            Text('$_currentPage / $_totalPages',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70),
              onPressed: _currentPage < _totalPages
                  ? () => _pdfController.nextPage()
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TEXT VIEWER PAGE — full selectable text, copy-all, char/line count
// ─────────────────────────────────────────────────────────────────────────────

class _TextViewerPage extends StatefulWidget {
  final Uint8List data;
  final String fileName;
  const _TextViewerPage({required this.data, required this.fileName});

  @override
  State<_TextViewerPage> createState() => _TextViewerPageState();
}

class _TextViewerPageState extends State<_TextViewerPage> {
  late final String _text;
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text = String.fromCharCodes(widget.data);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _vSurface,
      appBar: AppBar(
        backgroundColor: _vCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: GoogleFonts.spaceGrotesk(fontSize: 14, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Find in file…',
                  hintStyle: GoogleFonts.spaceGrotesk(
                      fontSize: 14, color: Colors.grey[600]),
                  border: InputBorder.none,
                ),
              )
            : Text(widget.fileName,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(
              _showSearch ? Icons.close_rounded : Icons.search_rounded,
              color: Colors.white70, size: 20,
            ),
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) _searchController.clear();
            }),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 20),
            tooltip: 'Copy all',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _text));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Copied to clipboard',
                    style: GoogleFonts.spaceGrotesk(color: Colors.white)),
                backgroundColor: const Color(0xFF10B981),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                margin: const EdgeInsets.all(16),
              ));
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          _text,
          style: GoogleFonts.sourceCodePro(
              fontSize: 13, color: Colors.grey[300], height: 1.65),
        ),
      ),
      bottomNavigationBar: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: _vCard,
          border: Border(top: BorderSide(color: _vBorder)),
        ),
        child: Row(children: [
          Text(
            '${_text.length} chars  ·  ${_text.split('\n').length} lines',
            style: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.grey[600]),
          ),
          const Spacer(),
          Text(widget.fileName,
              style: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.grey[700])),
        ]),
      ),
    );
  }
}