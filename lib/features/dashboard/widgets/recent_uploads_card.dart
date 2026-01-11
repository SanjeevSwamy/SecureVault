import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_vault/services/filebase_service.dart';
import 'package:secure_vault/services/wallet_service.dart';
import 'package:secure_vault/features/access/screens/access_file_screen.dart';

class RecentUploadsCard extends StatefulWidget {
  const RecentUploadsCard({super.key});

  @override
  State<RecentUploadsCard> createState() => _RecentUploadsCardState();
}

class _RecentUploadsCardState extends State<RecentUploadsCard> {
  bool _isProcessing = false;
  List<Map<String, dynamic>> _userFiles = [];
  bool _hasLoadedOnce = false;
  String _walletAddress = '';

  @override
  void initState() {
    super.initState();
    _loadUserFiles();
  }

  Future<void> _loadUserFiles() async {
    try {
      final walletData = await SessionWalletService.getSessionWalletData();
      _walletAddress = walletData['address'] ?? '';
      
      if (_walletAddress.isNotEmpty) {
        final cachedFiles = FilebaseService.getCachedFiles(_walletAddress);
        if (cachedFiles != null && mounted) {
          setState(() {
            _userFiles = cachedFiles.take(4).toList();
            _hasLoadedOnce = true;
          });
        }
        
        final files = await FilebaseService.getUserFilesWithSync(_walletAddress);
        
        if (mounted) {
          setState(() {
            _userFiles = files.take(4).toList();
            _hasLoadedOnce = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _userFiles = [];
            _hasLoadedOnce = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userFiles = [];
          _hasLoadedOnce = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasLoadedOnce) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_userFiles.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: _userFiles.asMap().entries.map((entry) {
        final index = entry.key;
        final file = entry.value;
        return Padding(
          padding: EdgeInsets.only(bottom: index == _userFiles.length - 1 ? 0 : 12),
          child: _buildFileItem(context, file),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.08)),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_upload_rounded, color: Color(0xFF2563EB), size: 48),
          const SizedBox(height: 16),
          Text('No files uploaded yet', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildFileItem(BuildContext context, Map<String, dynamic> file) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.08)),
      ),
      child: ListTile(
        onTap: _isProcessing ? null : () => _openFileInAccessScreen(file),
        leading: Icon(_getAppleFileIcon(file['type'] ?? 'file'), color: const Color(0xFF2563EB)),
        title: Text(file['name'] ?? 'Unknown File', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(file['encryptionName'] ?? 'Encrypted'),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  void _openFileInAccessScreen(Map<String, dynamic> file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FileAccessScreen(prefillCid: file['cid']),
      ),
    );
  }

  IconData _getAppleFileIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf': return Icons.article_rounded;
      case 'jpg': case 'png': return Icons.image_rounded;
      case 'mp4': return Icons.video_file_rounded;
      default: return Icons.insert_drive_file_rounded;
    }
  }
}