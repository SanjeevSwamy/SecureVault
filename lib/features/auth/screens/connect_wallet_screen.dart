import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:reown_appkit/reown_appkit.dart';
import '../../../core/reown_session.dart';
import '../../dashboard/screens/dashboard_screen.dart';

/*────────────────────────  Screen  ────────────────────────*/
class ConnectWalletScreen extends StatefulWidget {
  const ConnectWalletScreen({super.key});

  @override
  State<ConnectWalletScreen> createState() => _ConnectWalletScreenState();
}

class _ConnectWalletScreenState extends State<ConnectWalletScreen>
    with TickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  ReownAppKitModal? _modal;

  /* Apple-style entrance animations */
  late final AnimationController _logoCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));

  late final AnimationController _btnCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800));

  /* Apple-style success animation */
  late final AnimationController _successCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000));

  late final Animation<double> _logoFade =
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic);

  late final Animation<double> _logoScale =
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack);

  late final Animation<double> _btnSlide = Tween<double>(begin: 40.0, end: 0.0)
      .animate(CurvedAnimation(parent: _btnCtrl, curve: Curves.easeOutCubic));

  // Apple-style success animations
  late final Animation<double> _successFade = CurvedAnimation(
    parent: _successCtrl,
    curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
  );

  late final Animation<double> _successScale = CurvedAnimation(
    parent: _successCtrl,
    curve: const Interval(0.2, 0.8, curve: Curves.elasticOut),
  );

  late final Animation<double> _checkProgress = CurvedAnimation(
    parent: _successCtrl,
    curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _textFade = CurvedAnimation(
    parent: _successCtrl,
    curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
  );

  bool _ready = false;
  bool _navigated = false;
  bool _showSuccess = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startEntranceAnimations();
    _initReown();
  }

  void _startEntranceAnimations() {
    _logoCtrl.forward();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _btnCtrl.forward();
    });
  }

 Future<void> _initReown() async {
    try {
      _modal = ReownAppKitModal(
        context: context,
        projectId: '517c51ad11e07624e35ac450faa98424',
        metadata: const PairingMetadata(
          name: 'SecureVault',
          description: 'Decentralized File Storage',
          url: 'https://securevault.app',
          icons: ['https://securevault.app/logo.png'],
          redirect: Redirect(
            native: 'securevault://', 
            universal: 'https://securevault.app'
          ),
        ),
        // ⚠️ CRITICAL CHANGE: Leave requiredNamespaces EMPTY to allow connection regardless of current chain
        requiredNamespaces: {},
        
        // 2. Put EVERYTHING in Optional Namespaces
        optionalNamespaces: {
          'eip155': const RequiredNamespace(
            chains: [
              'eip155:1',          // Ethereum Mainnet
              'eip155:11155111'    // Sepolia Testnet
            ],
            methods: [
              'personal_sign', 
              'eth_sendTransaction', 
              'eth_signTransaction',
              'wallet_switchEthereumChain', // Allow switching
              'wallet_addEthereumChain'     // Allow adding chain
            ],
            events: ['chainChanged', 'accountsChanged'],
          ),
        },
      );

      await _modal!.init();

      _modal!.addListener(_onModalUpdate);
      ReownSession.modal = _modal;
      
      if (_modal!.isConnected) {
        await _checkAndSwitchChain(); // New helper to handle logic
        await _persistAuth();
        _goToDashboard();
        return; 
      }

      setState(() => _ready = true);
    } catch (e) {
      print('Wallet init error: $e');
      setState(() => _error = 'Wallet init failed: $e');
    }
  }

  // 🆕 Helper to switch network if needed
  Future<void> _checkAndSwitchChain() async {
    final session = _modal?.session;
    if (session == null) return;

    final currentChain = _modal?.selectedChain?.chainId;
    
    // If not on Sepolia (11155111)
    if (currentChain != '11155111') {
      print('⚠️ Wrong network detected ($currentChain). Requesting switch to Sepolia...');
      try {
        await _modal?.selectChain(
          ReownAppKitModalNetworkInfo(
            name: 'Sepolia',
            chainId: '11155111',
            currency: 'ETH',
            rpcUrl: 'https://ethereum-sepolia-rpc.publicnode.com',
            explorerUrl: 'https://sepolia.etherscan.io/',
            isTestNetwork: true,
          ),
        );
      } catch (e) {
        print('Chain switch error: $e');
        // We don't disconnect here; we let them in but they might need to switch later
      }
    }
  }

  void _onModalUpdate() {
    if (_modal?.isConnected == true && !_navigated && !_showSuccess) {
      _playAppleStyleSuccess();
    }
  }

  /*──────────── Apple-style success animation ────────────*/
  Future<void> _playAppleStyleSuccess() async {
    if (_showSuccess || _navigated) return;

    setState(() => _showSuccess = true);

    _successCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 2200));

    if (!mounted || _navigated) return;

    await _persistAuth();
    _goToDashboard();
  }

  Future<void> _persistAuth() async {
    final addr = _walletAddr(_modal?.session);
    if (addr == null) return;
    await _storage.write(key: 'auth_token', value: _fakeJwt(addr));
    await _storage.write(key: 'wallet_address', value: addr);
  }

  void _goToDashboard() {
    if (_navigated) return;
    _navigated = true;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const DashboardScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: anim,
            curve: Curves.easeInOutCubic,
          ),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  /*──────────────────  HELPERS  ──────────────────*/
  
  // ✅ FIXED: Robust address extraction using JSON to bypass getter errors
  String? _walletAddr(dynamic session) {
    if (session == null) return null;
    
    try {
      // 1. Convert session to Map to inspect structure
      final data = session.toJson();
      
      // 2. Look for namespaces -> eip155 -> accounts
      if (data.containsKey('namespaces')) {
        final namespaces = data['namespaces'];
        if (namespaces != null && namespaces['eip155'] != null) {
          final accounts = namespaces['eip155']['accounts'];
          if (accounts != null && (accounts as List).isNotEmpty) {
            // Account format is usually "eip155:1:0xAddress..."
            return accounts.first.toString().split(':').last;
          }
        }
      }
      
      // 3. Fallback: requiredNamespaces (sometimes data hides here)
      if (data.containsKey('requiredNamespaces')) {
         // Logic similar to above if needed, but namespaces is standard
      }
      
    } catch (e) {
      print('Error extraction address: $e');
    }
    return null;
  }

  String _fakeJwt(String addr) {
    final h = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
    final p = base64Url.encode(utf8.encode(
        '{"address":"$addr","exp":${DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000}}'));
    return '$h.$p.reown_signature';
  }

  /*──────────────────  UI  ──────────────────*/
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
      body: SafeArea(
        child: Stack(
          children: [
            _mainContent(),
            if (_showSuccess) _appleStyleSuccessOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _mainContent() {
    final addr = _walletAddr(_modal?.session);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: _logoFade,
              child: ScaleTransition(
                scale: _logoScale,
                child: Column(
                  children: [
                    _AppleLogo(),
                    const SizedBox(height: 32),
                    Text(
                      'SecureVault',
                      style: GoogleFonts.inter(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _ready
                          ? 'Connect your wallet to continue'
                          : _error != null
                              ? 'Error: $_error'
                              : 'Initializing wallet…',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.7),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 48),

            if (_modal?.isConnected == true && addr != null && !_showSuccess)
              _AppleConnectedCard(addr: addr),

            if (_error != null) ...[
              const SizedBox(height: 24),
              _AppleErrorBanner(msg: _error!)
            ],
            const SizedBox(height: 32),

            if (_ready && _modal != null && !_showSuccess)
              AnimatedBuilder(
                animation: _btnSlide,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, _btnSlide.value),
                    child: _appleConnectButton(), // ✅ Renamed
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ✅ Renamed to camelCase
  Widget _appleConnectButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _modal!.isConnected
            ? AppKitModalAccountButton(appKitModal: _modal!, context: context)
            : AppKitModalConnectButton(appKit: _modal!, context: context),
      ),
    );
  }

  Widget _appleStyleSuccessOverlay() {
    return AnimatedBuilder(
      animation: _successCtrl,
      builder: (context, child) {
        return FadeTransition(
          opacity: _successFade,
          child: Container(
            color: const Color(0xFF181A20).withOpacity(0.98),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: _successScale,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2563EB), Color(0xFF0891B2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2563EB).withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        painter: AppleCheckmarkPainter(
                          progress: _checkProgress.value,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  FadeTransition(
                    opacity: _textFade,
                    child: Column(
                      children: [
                        Text(
                          'Wallet Connected!',
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Taking you to your vault...',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.7),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    // ✅ Fixed cascade operator
    _modal?.removeListener(_onModalUpdate);
    _logoCtrl.dispose();
    _btnCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }
}

/*──────────────  Apple-style components  ─────────────*/
// ... [Keep _AppleLogo, _AppleConnectedCard, _AppleErrorBanner, AppleCheckmarkPainter as they were] ...
class _AppleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF0891B2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.3),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: const Icon(
        Icons.account_balance_wallet_rounded,
        size: 60,
        color: Colors.white,
      ),
    );
  }
}

class _AppleConnectedCard extends StatelessWidget {
  final String addr;
  const _AppleConnectedCard({required this.addr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF23262F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF10B981).withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}',
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white.withOpacity(0.9),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppleErrorBanner extends StatelessWidget {
  final String msg;
  const _AppleErrorBanner({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red[400], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              msg,
              style: GoogleFonts.inter(
                color: Colors.red.shade300,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppleCheckmarkPainter extends CustomPainter {
  final double progress;
  final Color color;

  AppleCheckmarkPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final checkSize = size.width * 0.25;

    final path = Path()
      ..moveTo(center.dx - checkSize, center.dy)
      ..lineTo(center.dx - checkSize * 0.2, center.dy + checkSize * 0.6)
      ..lineTo(center.dx + checkSize, center.dy - checkSize * 0.6);

    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      final extractedPath = metric.extractPath(0, metric.length * progress);
      canvas.drawPath(extractedPath, paint);
    }
  }

  @override
  bool shouldRepaint(AppleCheckmarkPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}