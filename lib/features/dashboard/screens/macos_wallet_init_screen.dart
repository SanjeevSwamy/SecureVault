import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_vault/services/desktop_wallet_connector.dart';
import 'dart:async';
import '../../../services/wallet_service.dart';
import '../../../services/desktop_wallet_service.dart';
import '../../../services/connection_polling_service.dart';
import 'desktop_wallet_connection_screen.dart';
import 'dashboard_screen.dart';

class MacOSWalletInitScreen extends StatefulWidget {
  const MacOSWalletInitScreen({super.key});

  @override
  State<MacOSWalletInitScreen> createState() => _MacOSWalletInitScreenState();
}

class _MacOSWalletInitScreenState extends State<MacOSWalletInitScreen> {
  String _status = 'Initializing SecureVault...';
  bool _isConnected = false;
  String? _connectedAddress;
  Timer? _fakeConnectTimer;

  @override
  void initState() {
    super.initState();
DesktopWalletConnector.startListener();
    // ✅ Setup wallet service
    DesktopWalletService.initialize(
      onWalletConnected: (String? walletAddress) {
        if (walletAddress != null) {
          _handleWalletConnected(walletAddress);
        }
      },
    );

    // ✅ Start polling
    ConnectionPollingService.startPolling(
      onConnectionDetected: _handleWalletConnected,
    );

    // ✅ Begin platform init flow
    _initializeApp();

    // 🧪 For local dev / QA only: Fake wallet connection
    // _debugMockConnect(); // ← Uncomment to simulate successful wallet connect
  }

  @override
  void dispose() {
    ConnectionPollingService.dispose();
    DesktopWalletService.dispose();
    DesktopWalletConnector.stop();
    _fakeConnectTimer?.cancel();
    super.dispose();
  }


  Future<void> _initializeApp() async {
    try {
      setState(() => _status = 'Setting up services...');
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() => _status = 'Checking wallet connection...');
      final isConnected = await SessionWalletService.isDesktopWalletConnected();

      if (isConnected) {
        final data = await SessionWalletService.getSessionWalletData();
        final address = data['address'] ?? '';

        if (address.isNotEmpty) {
          setState(() {
            _isConnected = true;
            _connectedAddress = address;
            _status = 'Wallet connected! Loading dashboard...';
          });
          await Future.delayed(const Duration(milliseconds: 1000));
          _navigateToDashboard();
          return;
        }
      }

      setState(() => _status = 'Ready for wallet connection...');
      await Future.delayed(const Duration(milliseconds: 600));
      _navigateToWalletConnection();

    } catch (e) {
      print('❌ macOS initialization error: $e');
      setState(() => _status = 'Initialization failed. Tap to retry.');
    }
  }

  void _handleWalletConnected(String walletAddress) {
    debugPrint('🎉 Wallet connection detected: $walletAddress');

    if (!mounted) return;

    setState(() {
      _isConnected = true;
      _connectedAddress = walletAddress;
      _status = 'Wallet connected! Loading dashboard...';
    });

    Future.delayed(const Duration(milliseconds: 1500), _navigateToDashboard);
  }

  void _navigateToDashboard() {
    if (!mounted) return;

    debugPrint('🚀 Navigating to dashboard...');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const DashboardScreen(),
        settings: const RouteSettings(name: '/dashboard'),
      ),
    );
  }

  void _navigateToWalletConnection() {
    if (!mounted) return;

    debugPrint('🔗 Navigating to wallet connection...');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const DesktopWalletConnectionScreen(),
        settings: const RouteSettings(name: '/wallet-connection'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          if (_status.contains('failed')) {
            _initializeApp();
          }
        },
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildHeroIcon(),
              const SizedBox(height: 40),
              _buildTitle(),
              const SizedBox(height: 60),
              if (!_isConnected) _buildLoading(),
              if (_isConnected) _buildSuccess(),
              const SizedBox(height: 20),
              _buildStatusText(),
              if (_connectedAddress != null) _buildConnectedAddress(),
              if (_status.contains('failed')) _buildDebugButtons(),
              if (ConnectionPollingService.isPolling && !_isConnected)
                _buildPollingInfo(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroIcon() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF0891B2)],
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Icon(
        Icons.security_rounded,
        size: 60,
        color: Colors.white,
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        Text(
          'SecureVault',
          style: GoogleFonts.inter(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Desktop',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return Column(
      children: [
        const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
          strokeWidth: 3,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Icon(
            Icons.check,
            color: Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildStatusText() {
    return Text(
      _status,
      style: GoogleFonts.inter(
        fontSize: 14,
        color: _status.contains('failed')
            ? Colors.red.shade300
            : Colors.white.withOpacity(0.8),
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildConnectedAddress() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '${_connectedAddress!.substring(0, 6)}...${_connectedAddress!.substring(_connectedAddress!.length - 4)}',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildPollingInfo() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.2),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          '🔍 Polling... (${ConnectionPollingService.pollCount})',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Colors.blue.shade300,
          ),
        ),
      ),
    );
  }

  Widget _buildDebugButtons() {
    return Column(
      children: [
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: _initializeApp,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            'Retry Initialization',
            style: GoogleFonts.inter(),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _navigateToWalletConnection,
          child: Text(
            'Skip to Wallet Connection',
            style: GoogleFonts.inter(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
