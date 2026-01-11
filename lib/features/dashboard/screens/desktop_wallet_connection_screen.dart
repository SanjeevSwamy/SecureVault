import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_vault/services/desktop_wallet_service.dart';
import 'package:secure_vault/services/connection_polling_service.dart';

class DesktopWalletConnectionScreen extends StatefulWidget {
  const DesktopWalletConnectionScreen({super.key});

  @override
  State<DesktopWalletConnectionScreen> createState() =>
      _DesktopWalletConnectionScreenState();
}

class _DesktopWalletConnectionScreenState
    extends State<DesktopWalletConnectionScreen> {
  bool _isConnecting = false;
  String _status = '';

  @override
  void initState() {
    super.initState();

    /// Initialize wallet service with polling
    DesktopWalletService.initialize(
      onWalletConnected: _onWalletConnected,
    );

    ConnectionPollingService.startPolling(
      onConnectionDetected: (walletAddress) {
        _onWalletConnected(walletAddress);
      },
    );

    // TEMP: Simulated fake connection for testing
    // Future.delayed(Duration(seconds: 5), () async {
    //   await DesktopWalletService.saveWalletConnection(
    //     '0xF4KE123456789',
    //     'test-token-987654321',
    //   );
    // });
  }

  @override
  void dispose() {
    ConnectionPollingService.dispose();
    DesktopWalletService.dispose();
    super.dispose();
  }

  void _onWalletConnected(String? walletAddress) {
    if (walletAddress != null && mounted) {
      setState(() {
        _isConnecting = false;
        _status = '✅ Connected: $walletAddress';
      });

      // Navigate to dashboard after short success
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/dashboard');
        }
      });
    }
  }

  // Custom font handler (macOS-safe)
  TextStyle _safeTextStyle({
    required double fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    if (Platform.isMacOS) {
      return TextStyle(
        fontFamily: 'SF Pro Display',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );
    } else {
      return GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
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
              ),

              const SizedBox(height: 40),

              Text(
                'SecureVault Desktop',
                style: _safeTextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Connect your wallet to access your encrypted files',
                textAlign: TextAlign.center,
                style: _safeTextStyle(
                  fontSize: 16,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 32),

              Platform.isMacOS
                  ? _buildMacRequirements()
                  : const SizedBox.shrink(),

              _isConnecting
                  ? _buildLoadingStatus()
                  : _buildConnectButton(context),

              const SizedBox(height: 24),
              _buildHowItWorksSection()
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingStatus() {
    return Column(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          _status.isEmpty
              ? 'Opening browser to connect wallet...'
              : _status,
          textAlign: TextAlign.center,
          style: _safeTextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
        if (ConnectionPollingService.isPolling) ...[
          const SizedBox(height: 16),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              '🔍 Checking for connection... (${ConnectionPollingService.pollCount})',
              style: _safeTextStyle(
                fontSize: 12,
                color: Colors.green,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMacRequirements() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Text(
                'macOS Setup Required:',
                style: _safeTextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRequirement('✓', 'Install Chrome, Brave, or Firefox'),
          _buildRequirement('✓', 'Add MetaMask extension to your browser'),
          _buildRequirement('✓', 'Import your existing wallet'),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.warning_amber,
                  color: Colors.orange, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Safari doesn\'t support MetaMask extension',
                  style: _safeTextStyle(
                    fontSize: 12,
                    color: Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConnectButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () {
          if (Platform.isMacOS) {
            _showBrowserSelection(); // Pick browser
          } else {
            _connectWallet(); // Default on mobile
          }
        },
        icon: const Icon(Icons.account_balance_wallet_rounded, size: 24),
        label: Text(
          Platform.isMacOS ? 'Choose Browser & Connect' : 'Connect Wallet',
          style: _safeTextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildRequirement(String check, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            check,
            style: _safeTextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: _safeTextStyle(
                fontSize: 13,
                color: Colors.blue.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF2563EB).withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works:',
            style: _safeTextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _buildStep('1',
              Platform.isMacOS ? 'Choose compatible browser' : 'Opens browser'),
          _buildStep('2', 'Connect MetaMask or Trust Wallet'),
          _buildStep('3', 'Return to app — it detects connection'),
        ],
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                number,
                style: _safeTextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2563EB),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: _safeTextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showBrowserSelection() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Choose Browser',
          style: _safeTextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildBrowserOption('Google Chrome', 'Most reliable',
                Icons.web, Colors.blue, 'Google Chrome'),
            _buildBrowserOption('Brave Browser', 'Built-in privacy',
                Icons.security, Colors.orange, 'Brave Browser'),
            _buildBrowserOption('Firefox', 'Open-source choice',
                Icons.public, Colors.deepOrange, 'Firefox'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: _safeTextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowserOption(String name, String subtitle, IconData icon,
      Color color, String browserAppName) {
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      leading: Icon(icon, color: color),
      title: Text(name, style: _safeTextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: _safeTextStyle(fontSize: 12, color: Colors.grey.shade600)),
      onTap: () => _openInBrowser(browserAppName),
    );
  }

  Future<void> _openInBrowser(String browserName) async {
    Navigator.pop(context);
    setState(() {
      _isConnecting = true;
      _status = 'Opening $browserName...';
    });

    try {
      final result = await Process.run('open', [
        '-a',
        browserName,
        'https://secure-vault-sandy.vercel.app'
      ]);
      print('🌐 Opened in $browserName → ${result.exitCode}');

      setState(() {
        _status = '✅ Connected in $browserName. Return here.';
      });
    } catch (e) {
      print('❌ Failed to open $browserName: $e');

      setState(() {
        _isConnecting = false;
        _status = '';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$browserName not found. Try installing it.'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Download',
            textColor: Colors.white,
            onPressed: () => _showDownloadInstructions(browserName),
          ),
        ),
      );
    }
  }

  void _showDownloadInstructions(String browserName) {
    String downloadUrl = '';
    switch (browserName) {
      case 'Google Chrome':
        downloadUrl = 'https://www.google.com/chrome/';
        break;
      case 'Brave Browser':
        downloadUrl = 'https://brave.com/download/';
        break;
      case 'Firefox':
        downloadUrl = 'https://www.mozilla.org/firefox/download/';
        break;
      default:
        downloadUrl = 'https://www.google.com/chrome/';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Download $browserName',
            style: _safeTextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: Text(downloadUrl, style: TextStyle(color: Colors.blue)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _connectWallet() async {
    setState(() {
      _isConnecting = true;
      _status = 'Opening browser...';
    });

    try {
      await DesktopWalletService.connectWallet();

      setState(() {
        _status = 'Waiting for connection...';
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _status = 'Failed to open browser.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
