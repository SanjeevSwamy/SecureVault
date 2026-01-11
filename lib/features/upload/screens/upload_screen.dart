import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart'; // 1. Add this to pubspec.yaml
import 'package:secure_vault/services/filebase_service.dart';
import 'package:secure_vault/services/encryption_service.dart';
import 'package:secure_vault/services/wallet_service.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> 
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _progressController;
  late AnimationController _successController;
  late AnimationController _floatController;
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late AnimationController _rotateController;
  
  // Real file data
  PlatformFile? _selectedFile;
  bool _isUploading = false;
  bool _isCompleted = false;
  
  // 2. NEW STATE VARIABLES
  String _generatedCID = '';
  String _txHash = ''; // Stores the blockchain transaction hash
  
  double _uploadProgress = 0.0;
  String _statusMessage = '';
  
  // Real encryption options
  EncryptionType _selectedEncryption = EncryptionType.aes256;
  bool _enableCompression = true;
  bool _enableVersioning = false;
  String _accessLevel = 'Private';
  
  final List<String> _uploadSteps = [
    'Reading file...',
    'Generating encryption key...',
    'Encrypting...',
    'Uploading to IPFS...',
    'Notarizing on Sepolia...', // Updated text
    'Finalizing upload...',
  ];

  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _progressController = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _successController = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    _floatController = AnimationController(duration: const Duration(seconds: 4), vsync: this);
    _pulseController = AnimationController(duration: const Duration(seconds: 2), vsync: this);
    _scaleController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _rotateController = AnimationController(duration: const Duration(seconds: 8), vsync: this);
    _startAnimations();
  }

  void _startAnimations() {
    _fadeController.forward();
    _scaleController.forward();
    _floatController.repeat(reverse: true);
    _pulseController.repeat(reverse: true);
    _rotateController.repeat();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _progressController.dispose();
    _successController.dispose();
    _floatController.dispose();
    _pulseController.dispose();
    _scaleController.dispose();
    _rotateController.dispose();
    super.dispose();
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
              child: FadeTransition(
                opacity: _fadeController,
                child: _isCompleted 
                    ? _buildSuccessView()
                    : _isUploading 
                        ? _buildUploadProgress()
                        : _selectedFile == null 
                            ? _buildFileSelector()
                            : _buildFileConfiguration(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, -0.5), end: Offset.zero).animate(
        CurvedAnimation(parent: _fadeController, curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic)),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.1), width: 1),
              ),
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.chevron_left_rounded, size: 20, color: Theme.of(context).colorScheme.onSurface),
                padding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'Upload File',
                  style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface, letterSpacing: -0.4),
                ),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFileSelector() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 30),
          Center(
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut)),
              child: AnimatedBuilder(
                animation: Listenable.merge([_floatController, _pulseController]),
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, -8 * _floatController.value),
                    child: GestureDetector(
                      onTap: _pickFile,
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 220, maxHeight: 300),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF2563EB).withOpacity(0.05 + 0.03 * _pulseController.value),
                              const Color(0xFF0891B2).withOpacity(0.03 + 0.02 * _pulseController.value),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFF2563EB).withOpacity(0.3 + 0.2 * _pulseController.value),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withOpacity(0.1 + 0.05 * _pulseController.value),
                              blurRadius: 16 + (8 * _pulseController.value),
                              spreadRadius: 0,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedBuilder(
                                animation: _rotateController,
                                builder: (context, child) {
                                  return Transform.rotate(
                                    angle: 0.1 * _rotateController.value,
                                    child: Container(
                                      width: 80, height: 80,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                                          colors: [const Color(0xFF2563EB).withOpacity(0.9), const Color(0xFF0891B2).withOpacity(0.8)],
                                        ),
                                        shape: BoxShape.circle,
                                        boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
                                      ),
                                      child: const Icon(Icons.cloud_upload_rounded, size: 40, color: Colors.white),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              Text('Drop files here or tap to browse', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface, letterSpacing: -0.4), textAlign: TextAlign.center),
                              const SizedBox(height: 8),
                              Text('Supports all file types • Max 100MB', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), letterSpacing: -0.1)),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF0891B2)]),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                                ),
                                child: Text('Choose File', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: -0.2)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 800),
            tween: Tween(begin: 0.0, end: 1.0),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 30 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildFeatureCard(Icons.security_rounded, 'Encrypted', '4 Algorithms', const Color(0xFF2563EB))),
                          const SizedBox(width: 16),
                          Expanded(child: _buildFeatureCard(Icons.cloud_rounded, 'IPFS Storage', 'Decentralized', const Color(0xFF0891B2))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildFeatureCard(Icons.account_balance_wallet_rounded, 'Wallet-Based', 'Your keys only', const Color(0xFF059669))),
                          const SizedBox(width: 16),
                          Expanded(child: _buildFeatureCard(Icons.speed_rounded, 'Fast Upload', 'Filebase CDN', const Color(0xFF7C3AED))),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildFileConfiguration() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.08), width: 1),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 16, spreadRadius: 0, offset: const Offset(0, 8))],
            ),
            child: Row(
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF2563EB).withOpacity(0.1), const Color(0xFF0891B2).withOpacity(0.1)]),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(_getFileIcon(_selectedFile!.name), size: 36, color: const Color(0xFF2563EB)),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_selectedFile!.name, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface, letterSpacing: -0.3, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Text('${_formatFileSize(_selectedFile!.size)} • ${_selectedFile!.extension?.toUpperCase() ?? 'FILE'}', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w400, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), letterSpacing: -0.1)),
                    ],
                  ),
                ),
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: const Color(0xFF2563EB).withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                  child: IconButton(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.edit_rounded, size: 20),
                    style: IconButton.styleFrom(foregroundColor: const Color(0xFF2563EB)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Text('Upload Settings', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface, letterSpacing: -0.6)),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.08), width: 1),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 12, spreadRadius: 0, offset: const Offset(0, 6))],
            ),
            child: Column(
              children: [
                _buildCleanSettingsTile(
                  icon: Icons.security_rounded,
                  iconColor: const Color(0xFF2563EB),
                  title: 'Encryption Method',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildChoicePill('${_selectedEncryption.emoji} ${_selectedEncryption.displayName}'),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right_rounded, size: 18, color: const Color(0xFF2563EB).withOpacity(0.6)),
                    ],
                  ),
                  onTap: () => _showEncryptionOptions(),
                ),
                _buildCleanSettingsTile(
                  icon: _accessLevel == 'Private' ? Icons.lock_rounded : _accessLevel == 'Shared' ? Icons.people_rounded : Icons.public_rounded,
                  iconColor: const Color(0xFF2563EB),
                  title: 'Access Level',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildChoicePill(_accessLevel),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right_rounded, size: 18, color: const Color(0xFF2563EB).withOpacity(0.6)),
                    ],
                  ),
                  onTap: () => _showAccessOptions(),
                ),
                _buildCleanSettingsTile(
                  icon: Icons.compress_rounded,
                  iconColor: const Color(0xFF2563EB),
                  title: 'Enable Compression',
                  trailing: Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: _enableCompression,
                      onChanged: (value) => setState(() => _enableCompression = value),
                      activeColor: const Color(0xFF2563EB),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  onTap: () => setState(() => _enableCompression = !_enableCompression),
                ),
                _buildCleanSettingsTile(
                  icon: Icons.history_rounded,
                  iconColor: const Color(0xFF2563EB),
                  title: 'Version Control',
                  trailing: Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: _enableVersioning,
                      onChanged: (value) => setState(() => _enableVersioning = value),
                      activeColor: const Color(0xFF2563EB),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  onTap: () => setState(() => _enableVersioning = !_enableVersioning),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Container(
            width: double.infinity, height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2563EB), Color(0xFF0891B2)]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withOpacity(0.3), blurRadius: 20, spreadRadius: 0, offset: const Offset(0, 8))],
            ),
            child: ElevatedButton.icon(
              onPressed: _startRealUpload,
              icon: const Icon(Icons.upload_rounded, size: 20),
              label: Text('Start Upload', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. UPDATED UPLOAD LOGIC TO HANDLE TX HASH
  // ---------------------------------------------------------------------------

Future<void> _startRealUpload() async {
    if (_selectedFile == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _currentStep = 0;
      _statusMessage = _uploadSteps[0];
    });

    try {
      final walletData = await SessionWalletService.getSessionWalletData();
      final walletAddress = walletData['address'] ?? '';
      
      if (walletAddress.isEmpty) throw Exception('No wallet connected');

      // ... (Keep your existing progress animation steps 0, 1, 2, 3) ...
      if (mounted) setState(() { _statusMessage = _uploadSteps[0]; _uploadProgress = 0.1; });
      await Future.delayed(const Duration(milliseconds: 500));

      final fileBytes = _selectedFile!.bytes!;
      
      if (mounted) setState(() { _currentStep = 1; _statusMessage = _uploadSteps[1]; _uploadProgress = 0.2; });
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (mounted) setState(() { _currentStep = 2; _statusMessage = _uploadSteps[2]; _uploadProgress = 0.4; });
      await Future.delayed(const Duration(milliseconds: 800));
      
      if (mounted) setState(() { _currentStep = 3; _statusMessage = _uploadSteps[3]; _uploadProgress = 0.6; });

      // 🚀 CALL SERVICE
      final result = await FilebaseService.uploadEncryptedFile(
        fileBytes: fileBytes,
        fileName: _selectedFile!.name,
        walletAddress: walletAddress,
        encryptionType: _selectedEncryption,
      );

      // ✅ CHECK RESULT
      if (result != null) {
        final cid = result['cid']!;
        final txHash = result['txHash'] ?? '';

        if (mounted) setState(() { _currentStep = 4; _statusMessage = _uploadSteps[4]; _uploadProgress = 0.8; });
        if (mounted) setState(() { _currentStep = 5; _statusMessage = _uploadSteps[5]; _uploadProgress = 1.0; });
        await Future.delayed(const Duration(milliseconds: 300));

        if (mounted) {
          setState(() {
            _isUploading = false;
            _isCompleted = true;
            _generatedCID = cid;
            _txHash = txHash;
          });
          _successController.forward();
        }
      } else {
        // 🛑 STOP: Logic for when user cancels
        throw Exception('Upload cancelled or failed');
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          // Reset UI
          _statusMessage = '';
          _uploadProgress = 0.0;
          _currentStep = 0;
        });

        // Show friendly error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().contains('cancelled') 
              ? 'Transaction cancelled' 
              : 'Upload failed'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }
  Widget _buildUploadProgress() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Center(
            child: SizedBox(
              width: 160, height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 160, height: 160,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF2563EB).withOpacity(0.06), boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withOpacity(0.1), blurRadius: 20, spreadRadius: 0)]),
                  ),
                  SizedBox(
                    width: 160, height: 160,
                    child: CircularProgressIndicator(value: _uploadProgress, strokeWidth: 3, backgroundColor: Colors.transparent, valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)), strokeCap: StrokeCap.round),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TweenAnimationBuilder<int>(duration: const Duration(milliseconds: 200), tween: IntTween(begin: 0, end: (_uploadProgress * 100).round()), builder: (context, value, child) {
                        return Text('$value%', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w600, color: const Color(0xFF2563EB), letterSpacing: -1.0));
                      }),
                      const SizedBox(height: 4),
                      AnimatedBuilder(animation: _pulseController, builder: (context, child) {
                        return Transform.scale(scale: 1.0 + (0.02 * _pulseController.value), child: Text('Uploading', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5 + (0.1 * _pulseController.value)), letterSpacing: -0.1)));
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(_statusMessage, key: ValueKey(_statusMessage), style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface, letterSpacing: -0.2), textAlign: TextAlign.center),
          ),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_uploadSteps.length, (index) { final isActive = index == _currentStep; final isCompleted = index < _currentStep; return AnimatedContainer(duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic, margin: const EdgeInsets.symmetric(horizontal: 2.5), width: isActive ? 20 : (isCompleted ? 16 : 6), height: 2.5, decoration: BoxDecoration(color: isCompleted || isActive ? const Color(0xFF2563EB) : const Color(0xFF2563EB).withOpacity(0.2), borderRadius: BorderRadius.circular(1.25))); })),
          const Spacer(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. UPDATED SUCCESS VIEW WITH BLOCKCHAIN RECEIPT
  // ---------------------------------------------------------------------------

  Widget _buildSuccessView() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 1200),
              curve: Curves.elasticOut,
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, scale, child) {
                return Transform.scale(scale: scale, child: Container(width: 120, height: 120, decoration: BoxDecoration(color: const Color(0xFF2563EB), shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withOpacity(0.25), blurRadius: 20, spreadRadius: 0, offset: const Offset(0, 8))]), child: AnimatedBuilder(animation: _successController, builder: (context, child) { return CustomPaint(painter: CheckmarkPainter(progress: _successController.value, color: Colors.white), size: const Size(120, 120)); })));
              },
            ),
            const SizedBox(height: 32),
            Text('Upload Complete!', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface, letterSpacing: -0.8), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Your file has been encrypted and\nstored on the decentralized network.', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w400, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), letterSpacing: -0.2, height: 1.4), textAlign: TextAlign.center),
            const SizedBox(height: 40),
            
            // IPFS CARD
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF0891B2).withOpacity(0.15), width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 12, offset: const Offset(0, 4))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF0891B2).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.cloud_done_rounded, size: 18, color: Color(0xFF0891B2))), const SizedBox(width: 12), Text('IPFS Storage', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface))]), const SizedBox(height: 12), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.background, borderRadius: BorderRadius.circular(12)), child: Row(children: [Expanded(child: Text(_generatedCID, style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8)), overflow: TextOverflow.ellipsis)), const SizedBox(width: 12), GestureDetector(onTap: _copyCID, child: const Icon(Icons.copy_rounded, size: 18, color: Color(0xFF0891B2)))]))]),
            ),

            // 6. BLOCKCHAIN RECEIPT CARD (Only shows if TxHash exists)
            if (_txHash.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.15), width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 12, offset: const Offset(0, 4))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFF59E0B).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.receipt_long_rounded, size: 18, color: Color(0xFFF59E0B))), const SizedBox(width: 12), Text('Blockchain Receipt (Sepolia)', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface))]), 
                  const SizedBox(height: 12), 
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.background, borderRadius: BorderRadius.circular(12)), child: Row(children: [
                    Expanded(child: Text(_txHash, style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8)), overflow: TextOverflow.ellipsis)), 
                    const SizedBox(width: 12), 
                    // VERIFY BUTTON
                    GestureDetector(
                      onTap: () async { 
                        final uri = Uri.parse('https://sepolia.etherscan.io/tx/$_txHash'); 
                        if (await canLaunchUrl(uri)) await launchUrl(uri); 
                      }, 
                      child: Row(children: [Text('Verify', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFF59E0B))), const SizedBox(width: 4), const Icon(Icons.open_in_new_rounded, size: 16, color: Color(0xFFF59E0B))])
                    )
                  ]))
                ]),
              ),
            ],

            const SizedBox(height: 40),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.check_rounded, size: 18), label: Text('Done', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🛠️ HELPER METHODS
  // ---------------------------------------------------------------------------

  Widget _buildFeatureCard(IconData icon, String title, String subtitle, Color color) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.1), width: 1),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(height: 8),
                Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface, letterSpacing: -0.2), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w400, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), letterSpacing: -0.1), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCleanSettingsTile({required IconData icon, required Color iconColor, required String title, required Widget trailing, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 20, color: iconColor)),
              const SizedBox(width: 16),
              Expanded(child: Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface, letterSpacing: -0.2))),
              const SizedBox(width: 16),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChoicePill(String text) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 100),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFF2563EB).withOpacity(0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.25), width: 1)),
      child: Text(text, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF2563EB), letterSpacing: -0.1), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
    );
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf': return Icons.picture_as_pdf_rounded;
      case 'doc': case 'docx': return Icons.description_rounded;
      case 'jpg': case 'jpeg': case 'png': return Icons.image_rounded;
      case 'mp4': case 'mov': return Icons.video_file_rounded;
      case 'mp3': case 'wav': return Icons.audio_file_rounded;
      default: return Icons.insert_drive_file_rounded;
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false, withData: true);
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.size > 100 * 1024 * 1024) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File too large. Max 100MB.'), backgroundColor: Colors.red));
          return;
        }
        setState(() => _selectedFile = file);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  
  void _copyCID() {
    Clipboard.setData(ClipboardData(text: _generatedCID));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CID copied!'), backgroundColor: Color(0xFF059669)));
  }

  void _showEncryptionOptions() {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (context) => Container(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))), child: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(width: 36, height: 5, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline.withOpacity(0.3), borderRadius: BorderRadius.circular(2.5))), const SizedBox(height: 32), Text('Encryption Method', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface, letterSpacing: -0.5)), const SizedBox(height: 32), Column(children: EncryptionType.values.map((type) => _buildEncryptionOption(type)).toList())])))));
  }
  
  Widget _buildEncryptionOption(EncryptionType type) {
    final isSelected = _selectedEncryption == type;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _selectedEncryption = type);
          Navigator.pop(context);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2563EB).withOpacity(0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? const Color(0xFF2563EB).withOpacity(0.2) : Colors.transparent),
          ),
          child: Row(
            children: [
              Text(type.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type.displayName, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                    Text("Secure encryption algorithm", style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                  ],
                ),
              ),
              if (isSelected) const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccessOptions() {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (context) => Container(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))), child: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(width: 36, height: 5, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline.withOpacity(0.3), borderRadius: BorderRadius.circular(2.5))), const SizedBox(height: 32), Text('Access Level', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface, letterSpacing: -0.5)), const SizedBox(height: 32), Column(children: [_buildAccessOption('Private', 'Only you', Icons.lock_rounded, true), _buildAccessOption('Shared', 'Link sharing', Icons.people_rounded, false), _buildAccessOption('Public', 'Anyone', Icons.public_rounded, false)])])))));
  }

  Widget _buildAccessOption(String title, String subtitle, IconData icon, bool isAvailable) {
    final isSelected = _accessLevel == title;
    final Color primaryColor = const Color(0xFF2563EB);
    return Opacity(
      opacity: isAvailable ? 1.0 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isAvailable ? () { setState(() => _accessLevel = title); Navigator.pop(context); } : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: isSelected ? primaryColor.withOpacity(0.05) : Colors.transparent, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSelected ? primaryColor.withOpacity(0.2) : Colors.transparent)),
            child: Row(
              children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: isSelected ? primaryColor.withOpacity(0.1) : Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 20, color: isSelected ? primaryColor : Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)), Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)))])),
                if (isSelected) Icon(Icons.check_circle_rounded, color: primaryColor, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CheckmarkPainter extends CustomPainter {
  final double progress;
  final Color color;
  CheckmarkPainter({required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 4.0..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path()..moveTo(center.dx - 12, center.dy)..lineTo(center.dx - 2, center.dy + 8)..lineTo(center.dx + 12, center.dy - 8);
    final metrics = path.computeMetrics();
    for (final metric in metrics) { canvas.drawPath(metric.extractPath(0.0, metric.length * progress), paint); }
  }
  @override
  bool shouldRepaint(CheckmarkPainter old) => old.progress != progress;
}