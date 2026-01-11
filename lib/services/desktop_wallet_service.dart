import 'dart:io';
import 'dart:async';
import 'package:secure_vault/services/wallet_service.dart';
import 'package:url_launcher/url_launcher.dart';

class DesktopWalletService {
  static Function(String?)? _onWalletConnected;

  /// ✅ Initialize the service for desktop
  static void initialize({Function(String?)? onWalletConnected}) {
    _onWalletConnected = onWalletConnected;
    print('✅ Desktop wallet service initialized (polling mode)');
  }

  /// ✅ Open user-browser to connect wallet via Vercel dApp page
  static Future<void> connectWallet() async {
    final url = 'https://secure-vault-sandy.vercel.app';

    try {
      if (Platform.isMacOS) {
        // List browsers in priority order
        final browsers = ['Google Chrome', 'Brave Browser', 'Firefox'];
        bool opened = false;

        for (final browser in browsers) {
          try {
            await Process.run('open', ['-a', browser, url]);
            print('🌐 Opened in $browser for wallet connection');
            opened = true;
            break;
          } catch (e) {
            print('⚠️ $browser not found. Trying next...');
          }
        }

        if (!opened) {
          final uri = Uri.parse(url);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          print('🌐 Fallback to default browser');
        }
      } else {
        // On Windows/Linux or other, use default
        final uri = Uri.parse(url);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        print('🌐 Opened URL in default browser');
      }
    } catch (e) {
      print('❌ Failed to open browser: $e');
      rethrow;
    }
  }

  /// ✅ Used to manually trigger wallet connection detection
  /// Useful in browser bridge call or DevTools testing
  static void triggerWalletConnected(String walletAddress) {
    print('🎉 Triggered wallet connect manually: $walletAddress');
    _onWalletConnected?.call(walletAddress);
  }

  /// ✅ Save a wallet connection (to secure storage for polling)
  static Future<void> saveWalletConnection(String address, String token) async {
    try {
      await SessionWalletService.saveDesktopWalletConnection(address, token);
      print('💾 Wallet connection saved: $address');
    } catch (e) {
      print('❌ Failed to save wallet connection: $e');
    }
  }

  /// ✅ Dispose the service and clear listeners
  static void dispose() {
    _onWalletConnected = null;
    print('🧹 Desktop wallet service disposed');
  }
}
