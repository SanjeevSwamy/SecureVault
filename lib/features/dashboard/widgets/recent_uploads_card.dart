import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_vault/services/filebase_service.dart';
import 'package:secure_vault/services/wallet_service.dart';
import 'package:secure_vault/features/access/screens/access_file_screen.dart';
import 'package:secure_vault/core/route_observer.dart';

class RecentUploadsCard extends StatefulWidget {
  const RecentUploadsCard({super.key});

  @override
  State<RecentUploadsCard> createState() => _RecentUploadsCardState();
}

class _RecentUploadsCardState extends State<RecentUploadsCard> with RouteAware {
  List<Map<String, dynamic>> _userFiles     = [];
  bool                       _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    _loadInstant();
    _loadFresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route events — fires every time dependencies change,
    // so we guard with ModalRoute.of check.
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

  /// Called when a route above this one is popped — e.g. upload screen closes.
  @override
  void didPopNext() {
    _loadFresh();
  }

  // ── Step 1: paint from cache immediately ──────────────────────────────────

  Future<void> _loadInstant() async {
    try {
      final data    = await SessionWalletService.getSessionWalletData();
      final address = data['address'] ?? '';
      if (address.isEmpty || !mounted) {
        setState(() => _hasLoadedOnce = true);
        return;
      }

      final cached = FilebaseService.getCachedFiles(address);
      if (cached != null && mounted) {
        setState(() {
          _userFiles     = cached.take(4).toList();
          _hasLoadedOnce = true;
        });
      } else if (mounted) {
        setState(() => _hasLoadedOnce = true);
      }
    } catch (_) {
      if (mounted) setState(() => _hasLoadedOnce = true);
    }
  }

  // ── Step 2: fetch fresh data — retries if wallet not written to storage yet ─

  Future<void> _loadFresh() async {
    const maxRetries = 5;
    const retryDelay = Duration(milliseconds: 800);

    String address = '';

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      if (!mounted) return;
      final data = await SessionWalletService.getSessionWalletData();
      address = data['address'] ?? '';
      if (address.isNotEmpty) break;

      debugPrint('RecentUploadsCard: wallet address empty, retry ${attempt + 1}/$maxRetries');
      await Future.delayed(retryDelay);
    }

    if (address.isEmpty || !mounted) {
      setState(() => _hasLoadedOnce = true);
      return;
    }

    try {
      final files = await FilebaseService.getUserFilesWithSync(address);
      if (mounted) {
        setState(() {
          _userFiles     = files.take(4).toList();
          _hasLoadedOnce = true;
        });
      }
    } catch (e) {
      debugPrint('RecentUploadsCard _loadFresh error: $e');
      if (mounted) setState(() => _hasLoadedOnce = true);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_hasLoadedOnce) {
      return _buildSkeleton();
    }

    if (_userFiles.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: _userFiles.asMap().entries.map((entry) {
        final isLast = entry.key == _userFiles.length - 1;
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
          child: _buildFileItem(entry.value),
        );
      }).toList(),
    );
  }

  // 3-row skeleton shown only when there is literally nothing cached at all
  Widget _buildSkeleton() {
    return Column(
      children: List.generate(3, (i) => Padding(
        padding: EdgeInsets.only(bottom: i == 2 ? 0 : 12),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFF2563EB).withOpacity(0.08)),
          ),
          child: Row(children: [
            const SizedBox(width: 16),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Container(
                  height: 13,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.07),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 11,
                  width: 100,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.04),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 16),
          ]),
        ),
      )),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF2563EB).withOpacity(0.08)),
      ),
      child: Column(children: [
        const Icon(Icons.cloud_upload_rounded,
            color: Color(0xFF2563EB), size: 48),
        const SizedBox(height: 16),
        Text('No files uploaded yet',
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildFileItem(Map<String, dynamic> file) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF2563EB).withOpacity(0.08)),
      ),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                FileAccessScreen(prefillCid: file['cid']),
          ),
        ),
        leading: Icon(
          _fileIcon(file['type'] ?? 'file'),
          color: const Color(0xFF2563EB),
        ),
        title: Text(
          file['name'] ?? 'Unknown File',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(file['encryptionName'] ?? 'Encrypted'),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  IconData _fileIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':          return Icons.picture_as_pdf_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
      case 'gif':          return Icons.image_rounded;
      case 'mp4':
      case 'mov':
      case 'avi':          return Icons.video_file_rounded;
      case 'mp3':
      case 'wav':          return Icons.audio_file_rounded;
      case 'doc':
      case 'docx':         return Icons.description_rounded;
      case 'xls':
      case 'xlsx':         return Icons.table_chart_rounded;
      case 'zip':
      case 'rar':          return Icons.folder_zip_rounded;
      default:             return Icons.insert_drive_file_rounded;
    }
  }
}