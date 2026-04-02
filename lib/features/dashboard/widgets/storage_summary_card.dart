import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_vault/services/wallet_service.dart';
import 'package:secure_vault/services/filebase_service.dart';
import 'package:secure_vault/core/route_observer.dart';

class StorageSummaryCard extends StatefulWidget {
  const StorageSummaryCard({super.key});

  @override
  State<StorageSummaryCard> createState() => _StorageSummaryCardState();
}

class _StorageSummaryCardState extends State<StorageSummaryCard>
    with AutomaticKeepAliveClientMixin, RouteAware {

  String _walletAddress = '';
  String _networkName   = 'Ethereum';
  bool   _isConnected   = false;
  int    _filesStored   = 0;
  double _storageUsed   = 0.0;          // MB
  bool   _hasLoadedOnce = false;
  bool   _isRefreshing  = false;
  Map<String, dynamic> _fileTypeStats  = {};

  @override
  bool get wantKeepAlive => true;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadInstant();
    _loadFresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  /// Fires when upload screen (or any pushed route) is popped back to dashboard.
  @override
  void didPopNext() {
    _loadFresh();
  }

  // ── Step 1: paint from cache with zero awaits blocking the UI ─────────────

  Future<void> _loadInstant() async {
    try {
      // getSessionWalletData reads from SharedPrefs — fast, but still async
      final data = await SessionWalletService.getSessionWalletData();
      if (!mounted) return;

      final address = data['address'] ?? '';
      setState(() {
        _walletAddress = address;
        _networkName   = data['network'] ?? 'Ethereum';
        _isConnected   = data['isConnected'] ?? false;
      });

      if (address.isEmpty) {
        setState(() => _hasLoadedOnce = true);
        return;
      }

      // Paint cached stats immediately — no network call
      final cachedStats = FilebaseService.getCachedStats(address);
      final cachedFiles = FilebaseService.getCachedFiles(address);

      if (cachedStats != null || cachedFiles != null) {
        final files = cachedFiles ?? [];
        setState(() {
          _filesStored   = cachedStats?['totalFiles'] ?? files.length;
          _storageUsed   = ((cachedStats?['totalSize'] ?? 0) as num) / (1024 * 1024);
          _fileTypeStats = _buildTypeStats(files);
          _hasLoadedOnce = true;
        });
      } else {
        // Nothing cached — show skeleton so the user sees *something*
        setState(() => _hasLoadedOnce = true);
      }
    } catch (_) {
      if (mounted) setState(() => _hasLoadedOnce = true);
    }
  }

  // ── Step 2: fetch fresh data — retries if wallet not written to storage yet ─

  Future<void> _loadFresh() async {
    // On first wallet connect, storage might not be written yet.
    // Retry up to 5 times with 800ms gaps before giving up.
    const maxRetries = 5;
    const retryDelay = Duration(milliseconds: 800);

    String address = '';

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      if (!mounted) return;
      final data = await SessionWalletService.getSessionWalletData();
      address = data['address'] ?? '';

      if (address.isNotEmpty) {
        // Got the address — update connection state immediately
        if (mounted) {
          setState(() {
            _walletAddress = address;
            _networkName   = data['network'] ?? 'Ethereum';
            _isConnected   = data['isConnected'] ?? false;
          });
        }
        break;
      }

      // Address not ready yet — wait and retry
      debugPrint('StorageSummaryCard: wallet address empty, retry ${attempt + 1}/$maxRetries');
      await Future.delayed(retryDelay);
    }

    if (address.isEmpty || !mounted) {
      // Wallet genuinely not connected
      setState(() { _hasLoadedOnce = true; _isRefreshing = false; });
      return;
    }

    try {
      setState(() => _isRefreshing = true);

      // Run both fetches concurrently
      final results = await Future.wait([
        FilebaseService.getStorageStats(address),
        FilebaseService.getUserFilesWithSync(address),
      ]);

      if (!mounted) return;
      final stats = results[0] as Map<String, dynamic>;
      final files = results[1] as List<Map<String, dynamic>>;

      setState(() {
        _filesStored   = stats['totalFiles'] ?? files.length;
        _storageUsed   = ((stats['totalSize'] ?? 0) as num) / (1024 * 1024);
        _fileTypeStats = _buildTypeStats(files);
        _hasLoadedOnce = true;
        _isRefreshing  = false;
      });
    } catch (e) {
      debugPrint('StorageSummaryCard _loadFresh error: $e');
      if (mounted) setState(() { _hasLoadedOnce = true; _isRefreshing = false; });
    }
  }
  // Called from pull-to-refresh on the parent
  Future<void> refresh() async {
    setState(() => _isRefreshing = true);
    if (_walletAddress.isNotEmpty) {
      FilebaseService.clearCache(_walletAddress);
    }
    await _loadFresh();
  }

  // ── File-type stat helpers ─────────────────────────────────────────────────

  Map<String, dynamic> _buildTypeStats(List<Map<String, dynamic>> files) {
    final Map<String, Map<String, dynamic>> typeStats = {};
    int totalSize = 0;

    for (final file in files) {
      final raw      = (file['type'] as String? ?? 'unknown').toLowerCase();
      final category = _category(raw);
      final size     = (file['size'] as num? ?? 0).toInt();
      totalSize += size;

      typeStats.putIfAbsent(category, () => {
        'count':       0,
        'size':        0,
        'color':       _color(category),
        'icon':        _icon(category),
        'displayName': _displayName(category),
      });
      typeStats[category]!['count'] = (typeStats[category]!['count'] as int) + 1;
      typeStats[category]!['size']  = (typeStats[category]!['size']  as int) + size;
    }

    return {'types': typeStats, 'totalSize': totalSize};
  }

  String _category(String t) {
    switch (t) {
      case 'jpg': case 'jpeg': case 'png': case 'gif':
      case 'webp': case 'bmp': case 'tiff': case 'svg': return 'images';
      case 'pdf':                                        return 'pdf';
      case 'doc': case 'docx': case 'txt': case 'rtf':  return 'documents';
      case 'xlsx': case 'xls': case 'csv':               return 'spreadsheets';
      case 'pptx': case 'ppt':                           return 'presentations';
      case 'mp4': case 'mov': case 'avi':
      case 'mkv': case 'wmv': case 'flv':                return 'videos';
      case 'mp3': case 'wav': case 'flac':
      case 'm4a': case 'aac':                            return 'audio';
      case 'zip': case 'rar': case '7z':
      case 'tar': case 'gz':                             return 'archives';
      case 'js': case 'ts': case 'dart': case 'py':
      case 'java': case 'cpp': case 'c': case 'html':
      case 'css': case 'json': case 'xml':               return 'code';
      default:                                           return 'other';
    }
  }

  Color _color(String t) {
    switch (t) {
      case 'images':        return const Color(0xFF10B981);
      case 'pdf':           return const Color(0xFFEF4444);
      case 'documents':     return const Color(0xFF3B82F6);
      case 'spreadsheets':  return const Color(0xFF059669);
      case 'presentations': return const Color(0xFFF59E0B);
      case 'videos':        return const Color(0xFF8B5CF6);
      case 'audio':         return const Color(0xFFEC4899);
      case 'archives':      return const Color(0xFF6B7280);
      case 'code':          return const Color(0xFF7C3AED);
      default:              return const Color(0xFF9CA3AF);
    }
  }

  IconData _icon(String t) {
    switch (t) {
      case 'images':        return Icons.image_rounded;
      case 'pdf':           return Icons.picture_as_pdf_rounded;
      case 'documents':     return Icons.description_rounded;
      case 'spreadsheets':  return Icons.table_chart_rounded;
      case 'presentations': return Icons.slideshow_rounded;
      case 'videos':        return Icons.video_file_rounded;
      case 'audio':         return Icons.audio_file_rounded;
      case 'archives':      return Icons.folder_zip_rounded;
      case 'code':          return Icons.code_rounded;
      default:              return Icons.insert_drive_file_rounded;
    }
  }

  String _displayName(String t) {
    switch (t) {
      case 'images':        return 'Images';
      case 'pdf':           return 'PDFs';
      case 'documents':     return 'Documents';
      case 'spreadsheets':  return 'Spreadsheets';
      case 'presentations': return 'Presentations';
      case 'videos':        return 'Videos';
      case 'audio':         return 'Audio';
      case 'archives':      return 'Archives';
      case 'code':          return 'Code Files';
      default:              return 'Other';
    }
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(children: [
      IntrinsicHeight(
        child: Row(children: [
          Expanded(child: _buildMetricCard(
            value:      _hasLoadedOnce ? '$_filesStored' : '—',
            title:      'Files Stored',
            subtitle:   _hasLoadedOnce
                ? (_filesStored > 0 ? 'Encrypted & secure' : 'No files yet')
                : 'Loading…',
            startColor: const Color(0xFF2563EB),
            endColor:   const Color(0xFF0891B2),
            showBadge:  true,
          )),
          const SizedBox(width: 16),
          Expanded(child: _buildMetricCard(
            value: _hasLoadedOnce
                ? (_storageUsed < 1
                    ? '${(_storageUsed * 1024).toStringAsFixed(0)} KB'
                    : '${_storageUsed.toStringAsFixed(1)} MB')
                : '—',
            title:      'Storage Used',
            subtitle:   _hasLoadedOnce
                ? (_storageUsed > 0 ? 'On IPFS network' : '0 % of unlimited')
                : 'Loading…',
            startColor: const Color(0xFF0891B2),
            endColor:   const Color(0xFF2563EB),
            showBadge:  false,
          )),
        ]),
      ),

      if (_hasLoadedOnce && _filesStored > 0) ...[
        const SizedBox(height: 16),
        _buildBreakdownCard(),
      ],

      const SizedBox(height: 16),
      _buildWalletCard(),
    ]);
  }

  // ── Metric cards ───────────────────────────────────────────────────────────

  Widget _buildMetricCard({
    required String   value,
    required String   title,
    required String   subtitle,
    required Color    startColor,
    required Color    endColor,
    required bool     showBadge,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey('$value$title'),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [startColor, endColor],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: startColor.withOpacity(0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Show a shimmer-ish placeholder while loading
            if (!_hasLoadedOnce)
              Container(
                height: 32,
                width: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
              )
            else
              Text(value,
                  style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: -0.8,
                      height: 1.1)),
            const SizedBox(height: 6),
            Text(title,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.9),
                    letterSpacing: -0.2)),
            const SizedBox(height: 8),
            if (showBadge)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    !_hasLoadedOnce
                        ? Icons.hourglass_empty_rounded
                        : _filesStored > 0
                            ? Icons.security_rounded
                            : Icons.folder_outlined,
                    size: 12,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  const SizedBox(width: 3),
                  Text(subtitle,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.9),
                          letterSpacing: -0.1)),
                ]),
              )
            else
              Text(subtitle,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.8),
                      letterSpacing: -0.1),
                  overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  // ── Breakdown card ─────────────────────────────────────────────────────────

  Widget _buildBreakdownCard() {
    final types     = (_fileTypeStats['types'] as Map<String, Map<String, dynamic>>? ?? {});
    final totalSize = (_fileTypeStats['totalSize'] as int? ?? 0);

    if (types.isEmpty) return const SizedBox.shrink();

    final sorted = types.entries.toList()
      ..sort((a, b) =>
          (b.value['size'] as int).compareTo(a.value['size'] as int));

    const visibleCount = 4;
    final visible  = sorted.take(visibleCount).toList();
    final overflow = sorted.skip(visibleCount).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: const Color(0xFF2563EB).withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.pie_chart_rounded,
                size: 18, color: Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Text('Storage Breakdown',
              style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                  letterSpacing: -0.3)),
          const Spacer(),
          // Subtle refresh indicator
          if (_isRefreshing)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 1.8, color: Color(0xFF2563EB)),
            ),
        ]),

        const SizedBox(height: 20),

        // Stacked progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: sorted.map((e) {
                final size = e.value['size'] as int;
                final pct  = totalSize > 0 ? size / totalSize : 0.0;
                return Expanded(
                  flex: (pct * 100).round().clamp(1, 100),
                  child: ColoredBox(color: e.value['color'] as Color),
                );
              }).toList(),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Visible rows
        ...visible.map((e) => _typeRow(e.value, totalSize)),

        // "+N more" — tappable
        if (overflow.isNotEmpty)
          GestureDetector(
            onTap: () => _showAllTypesSheet(sorted, totalSize),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Text(
                  '+ ${overflow.length} more file ${overflow.length == 1 ? 'type' : 'types'}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    size: 16, color: Color(0xFF2563EB)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _typeRow(Map<String, dynamic> data, int totalSize) {
    final size        = data['size']        as int;
    final count       = data['count']       as int;
    final color       = data['color']       as Color;
    final icon        = data['icon']        as IconData;
    final displayName = data['displayName'] as String;
    final pct         = totalSize > 0 ? size / totalSize * 100 : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(displayName,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: -0.1)),
            Text('$count ${count == 1 ? 'file' : 'files'}',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.5))),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_fmtSize(size),
              style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface)),
          Text('${pct.toStringAsFixed(1)}%',
              style: GoogleFonts.inter(
                  fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ]),
      ]),
    );
  }

  // ── "All types" bottom sheet ───────────────────────────────────────────────

  void _showAllTypesSheet(
    List<MapEntry<String, Map<String, dynamic>>> sorted,
    int totalSize,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AllTypesSheet(
        sorted:    sorted,
        totalSize: totalSize,
        typeRow:   _typeRow,
        fmtSize:   _fmtSize,
      ),
    );
  }

  // ── Wallet card ────────────────────────────────────────────────────────────

  Widget _buildWalletCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isConnected
              ? Colors.black.withOpacity(0.2)
              : const Color(0xFF2563EB).withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
            Text(
              _isConnected ? 'Wallet Connected' : 'No Wallet Connected',
              style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                  letterSpacing: -0.4),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _isConnected
                      ? const Color(0xFF10B981)
                      : Colors.orange,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isConnected ? 'Session Active' : 'Session Inactive',
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _isConnected
                        ? const Color(0xFF10B981)
                        : Colors.orange,
                    letterSpacing: -0.2),
              ),
            ]),
            const SizedBox(height: 8),
            Text(_networkName,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                    letterSpacing: -0.1)),
            if (_walletAddress.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_walletAddress.substring(0, 6)}…${_walletAddress.substring(_walletAddress.length - 4)}',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.4)),
              ),
            ],
          ]),
        ),
        const SizedBox(width: 16),
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isConnected
                ? const Color(0xFF10B981).withOpacity(0.1)
                : const Color(0xFF2563EB).withOpacity(0.08),
            border: Border.all(
              color: _isConnected
                  ? const Color(0xFF10B981).withOpacity(0.2)
                  : const Color(0xFF2563EB).withOpacity(0.15),
            ),
          ),
          child: Icon(
            _isConnected
                ? Icons.account_balance_wallet_rounded
                : Icons.wallet_outlined,
            size: 24,
            color: _isConnected
                ? const Color(0xFF10B981)
                : const Color(0xFF2563EB),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ALL TYPES BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _AllTypesSheet extends StatelessWidget {
  final List<MapEntry<String, Map<String, dynamic>>> sorted;
  final int   totalSize;
  final Widget Function(Map<String, dynamic>, int) typeRow;
  final String Function(int) fmtSize;

  const _AllTypesSheet({
    required this.sorted,
    required this.totalSize,
    required this.typeRow,
    required this.fmtSize,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: onSurface.withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.pie_chart_rounded,
                    size: 18, color: Color(0xFF2563EB)),
              ),
              const SizedBox(width: 12),
              Text('All File Types',
                  style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: onSurface,
                      letterSpacing: -0.3)),
              const Spacer(),
              Text('${sorted.length} types',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: onSurface.withOpacity(0.5))),
            ]),
          ),

          const SizedBox(height: 8),
          Divider(color: onSurface.withOpacity(0.07)),

          // Stacked progress bar — full width
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: sorted.map((e) {
                    final size = e.value['size'] as int;
                    final pct  = totalSize > 0 ? size / totalSize : 0.0;
                    return Expanded(
                      flex: (pct * 100).round().clamp(1, 100),
                      child: ColoredBox(color: e.value['color'] as Color),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // All rows, scrollable
          Expanded(
            child: ListView.builder(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
              itemCount: sorted.length,
              itemBuilder: (_, i) => typeRow(sorted[i].value, totalSize),
            ),
          ),
        ]),
      ),
    );
  }
}