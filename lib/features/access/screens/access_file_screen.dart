import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart'; // 📦 Add this
import 'package:secure_vault/services/filebase_service.dart';
import 'package:secure_vault/services/wallet_service.dart';
import 'package:secure_vault/features/dashboard/screens/dashboard_screen.dart';

class FileAccessScreen extends StatefulWidget {
  final String? prefillCid;
  
  const FileAccessScreen({super.key, this.prefillCid});

  @override
  State<FileAccessScreen> createState() => _FileAccessScreenState();
}

class _FileAccessScreenState extends State<FileAccessScreen> 
    with TickerProviderStateMixin {
  final TextEditingController _hashController = TextEditingController();
  late AnimationController _fadeController;
  late AnimationController _successController;
  
  bool _isDecrypting = false;
  bool _isDecrypted = false;
  String _statusMessage = '';
  String _fileName = '';
  String _fileSize = '';
  String _txHash = ''; // 🆕 Store TxHash
  
  Uint8List? _decryptedFileData;

  @override
  void initState() {
    super.initState();
    if (widget.prefillCid != null) {
      _hashController.text = widget.prefillCid!;
    }
    
    _fadeController = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    _successController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _hashController.dispose();
    _fadeController.dispose();
    _successController.dispose();
    super.dispose();
  }

  // 1. UPDATED DECRYPT LOGIC TO FIND METADATA
  void _decryptFile() async {
    final hash = _hashController.text.trim();
    if (hash.isEmpty) return;

    setState(() { _isDecrypting = true; _statusMessage = 'Fetching from IPFS...'; });

    try {
      final walletData = await SessionWalletService.getSessionWalletData();
      final walletAddress = walletData['address'] ?? '';
      
      if (walletAddress.isEmpty) throw Exception('No wallet connected');

      // Download & Decrypt
      _decryptedFileData = await FilebaseService.downloadDecryptedFile(
        cid: hash,
        walletAddress: walletAddress,
      );
      
      if (_decryptedFileData == null) throw Exception('Decryption failed');

      // 🔍 NEW: Look up local metadata to find the TxHash
      String foundTxHash = '';
      try {
        final files = await FilebaseService.getUserFiles(walletAddress);
        final fileMeta = files.firstWhere((f) => f['cid'] == hash, orElse: () => {});
        foundTxHash = fileMeta['txHash'] ?? '';
      } catch (e) {
        print('Metadata lookup failed: $e');
      }

      final fileName = _extractFileNameFromCID(hash);
      
      setState(() {
        _isDecrypting = false;
        _isDecrypted = true;
        _fileName = fileName;
        _fileSize = _formatFileSize(_decryptedFileData!.length);
        _txHash = foundTxHash; // 🆕 Save for UI
      });

      _successController.forward();

    } catch (e) {
      setState(() { _isDecrypting = false; _statusMessage = 'Error: $e'; });
    }
  }

  // 2. NEW WIDGET: Blockchain Proof Card
  Widget _buildBlockchainCard() {
    if (_txHash.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_rounded, color: Color(0xFFF59E0B)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notarized on Sepolia', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFFF59E0B))),
                Text('Proof of Integrity verified', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFF59E0B).withOpacity(0.8))),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
               final uri = Uri.parse('https://sepolia.etherscan.io/tx/$_txHash');
               if (await canLaunchUrl(uri)) await launchUrl(uri);
            },
            child: const Text('Verify'),
          )
        ],
      ),
    );
  }

  // ... [Keep helpers: _extractFileNameFromCID, _formatFileSize, _downloadFile, _shareFile] ...
  // (Assuming you have these from previous versions)

  String _extractFileNameFromCID(String cid) {
    try {
      final parts = cid.split('_');
      if (parts.length >= 3) return parts.sublist(1, parts.length - 1).join('_');
    } catch (_) {}
    return 'file';
  }
  
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  
  Future<void> _shareFile() async {
     // Your existing share logic
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$_fileName');
      await file.writeAsBytes(_decryptedFileData!);
      await Share.shareXFiles([XFile(file.path)]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _isDecrypted ? _buildDecryptedView() : _buildInputView(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
               MaterialPageRoute(builder: (context) => const DashboardScreen()), (route) => false
            ),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          const Spacer(),
          Text('Access File', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600)),
          const Spacer(),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildInputView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.lock_outline_rounded, size: 80, color: Color(0xFF2563EB)),
        const SizedBox(height: 40),
        TextField(
          controller: _hashController,
          decoration: InputDecoration(
            hintText: 'Paste File CID',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
          ),
        ),
        const SizedBox(height: 20),
        if (_isDecrypting)
          const CircularProgressIndicator()
        else
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _decryptFile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Decrypt', style: TextStyle(color: Colors.white)),
            ),
          ),
        if (_statusMessage.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(_statusMessage, style: const TextStyle(color: Colors.red)),
        ]
      ],
    );
  }

  Widget _buildDecryptedView() {
    return Column(
      children: [
        const Icon(Icons.check_circle_rounded, size: 80, color: Color(0xFF059669)),
        const SizedBox(height: 20),
        Text('Decryption Successful', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(_fileName, style: GoogleFonts.inter(fontSize: 16)),
        Text(_fileSize, style: GoogleFonts.inter(fontSize: 14, color: Colors.grey)),
        
        // 3. INSERT CARD HERE
        _buildBlockchainCard(),
        
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _shareFile,
            icon: const Icon(Icons.share_rounded),
            label: const Text('Share / Save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}