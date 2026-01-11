import 'dart:async';
import 'wallet_service.dart';

class ConnectionPollingService {
  static Timer? _pollingTimer;
  static Function(String)? _onConnectionDetected;
  static bool _isPolling = false;
  static int _pollCount = 0;
  static const int _maxPolls = 60; // 2 minutes polling at 2s intervals

  // ✅ Getters to use in UI
  static bool get isPolling => _isPolling;
  static int get pollCount => _pollCount;

  /// ✅ Start polling for a connected wallet (desktop flow)
  static void startPolling({Function(String)? onConnectionDetected}) {
    if (_isPolling) return; // Prevent multiple simultaneous timers

    _onConnectionDetected = onConnectionDetected;
    _isPolling = true;
    _pollCount = 0;

    print('🔄 Starting wallet connection polling...');

    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      _pollCount++;

      if (_pollCount > _maxPolls) {
        print('⏰ Polling timeout reached. Stopping...');
        stopPolling();
        return;
      }

      await _checkForConnection();
    });

    /// 🧪 Optional: Temporary debug override to auto-connect after 5s
    // Future.delayed(Duration(seconds: 5), () async {
    //   print('[🧪 DEBUG] Mock wallet connection injected.');
    //   await SessionWalletService.saveDesktopWalletConnection(
    //     '0xF4KE1234567890ABCDE',
    //     'mock-desktop-token',
    //   );
    // });
  }

  /// ✅ Check for a connected desktop wallet
  static Future<void> _checkForConnection() async {
    try {
      final isConnected = await SessionWalletService.isDesktopWalletConnected();
      print('👀 Polling check: isConnected = $isConnected');

      if (isConnected) {
        final walletData = await SessionWalletService.getSessionWalletData();
        final walletAddress = walletData['address'];
        print('🔐 Wallet data: ${walletData.toString()}');

        if (walletAddress != null && walletAddress.isNotEmpty) {
          print('✅ Wallet detected: $walletAddress');
          stopPolling();
          _onConnectionDetected?.call(walletAddress);
        }
      } else {
        print('🕵️ No wallet connected yet...');
      }
    } catch (e) {
      print('⚠️ Polling error: $e');
    }
  }

  /// ✅ Stop the polling safely
  static void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isPolling = false;
    _pollCount = 0;
    print('🛑 Stopped polling for wallet connection.');
  }

  /// ✅ Dispose polling service
  static void dispose() {
    stopPolling();
    _onConnectionDetected = null;
  }
}
