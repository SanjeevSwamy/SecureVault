import 'dart:convert';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/reown_session.dart';
import 'filebase_service.dart';

class SessionWalletService {
  static const _storage = FlutterSecureStorage();

  // 🔒 Cached session info (shared across app state)
  static Map<String, dynamic>? _cachedData;
  static bool _isInitialized = false;

  // ✅ Get wallet data (with in-memory cache prioritization)
  static Future<Map<String, dynamic>> getSessionWalletData() async {
    if (_cachedData != null && _isInitialized) {
      return Map<String, dynamic>.from(_cachedData!);
    }

    await _initializeCache();
    return Map<String, dynamic>.from(_cachedData!);
  }

  /// 🧠 Initialize and populate cache
  static Future<void> _initializeCache() async {
    if (_isInitialized && _cachedData != null) return;

    try {
      final modal = ReownSession.modal;
      final storedAddress = await _storage.read(key: 'wallet_address');

      Map<String, dynamic> result;

      if (modal != null && modal.isConnected) {
        // ✅ FIXED: Safely extract address using dynamic casting/JSON to avoid NoSuchMethodError
        final session = modal.session;
        final address = _safeGetAddress(session) ?? storedAddress ?? '';

        result = {
          'address': address,
          'username': _generateSimpleUsername(address),
          'chainId': _getChainIdFromModal(),
          'network': _getNetworkNameFromModal(),
          'isConnected': true,
          'accounts': [address],
        };
      } else {
        final sessionData = await _storage.read(key: 'wallet_session');
        Map<String, dynamic> fallbackData = {};

        if (sessionData != null) {
          fallbackData = json.decode(sessionData);
        }

        final address = storedAddress ?? fallbackData['address'] ?? '';

        result = {
          'address': address,
          'username': address.isNotEmpty
              ? _generateSimpleUsername(address)
              : 'StarWanderer',
          'chainId': fallbackData['chainId'] ?? '1',
          'network': fallbackData['network'] ?? 'Ethereum',
          'isConnected': address.isNotEmpty,
          'accounts': fallbackData['accounts'] ?? [],
        };
      }

      _cachedData = result;
      _isInitialized = true;

      if (result['isConnected'] == true &&
          (result['address'] as String).isNotEmpty) {
        autoRestoreFiles();
      }
    } catch (e) {
      debugPrint('Error initializing cache: $e');
      _cachedData = {
        'address': '',
        'username': 'StarWanderer',
        'chainId': '1',
        'network': 'Ethereum',
        'isConnected': false,
        'accounts': [],
      };
      _isInitialized = true;
    }
  }

  // ✅ Helper to safely extract address from Session object
  static String? _safeGetAddress(dynamic session) {
    try {
      // Try direct property first (if available in future versions)
      // if (session.address != null) return session.address; 
      
      // Fallback: Convert to JSON map to access 'namespaces' safely
      // This bypasses the "NoSuchMethodError" on the class getter
      final data = session?.toJson(); 
      if (data != null && data['namespaces'] != null) {
        final eip155 = data['namespaces']['eip155'];
        if (eip155 != null && eip155['accounts'] != null) {
          final accounts = List.from(eip155['accounts']);
          if (accounts.isNotEmpty) {
            return accounts.first.toString().split(':').last;
          }
        }
      }
    } catch (e) {
      debugPrint('Error parsing session address: $e');
    }
    return null;
  }

  // ✅ Safe Chain ID getter using Reown API
  static String _getChainIdFromModal() {
    try {
      final chainId = ReownSession.modal?.selectedChain?.chainId;
      return chainId ?? '1';
    } catch (e) {
      return '1';
    }
  }

  // ✅ Safe Network Name getter
  static String _getNetworkNameFromModal() {
    try {
      final name = ReownSession.modal?.selectedChain?.name;
      return name ?? 'Ethereum';
    } catch (e) {
      return 'Ethereum';
    }
  }

  /// 🔁 Auto restore IPFS-backed files (desktop/mobile)
  static Future<void> autoRestoreFiles() async {
    try {
      final data = await getSessionWalletData();
      final address = data['address'] ?? '';
      if (address.isNotEmpty && data['isConnected'] == true) {
        debugPrint('🔄 Auto-restoring files for: $address');

        await FilebaseService.restoreFromCloud(address);
        Future.delayed(const Duration(milliseconds: 500), () async {
          await FilebaseService.recoverLostFiles(address);
        });
      }
    } catch (e) {
      debugPrint('❌ Auto-restore files failed: $e');
    }
  }

  /// 💾 Save desktop wallet connection via polling flow
  static Future<void> saveDesktopWalletConnection(
      String address, String token) async {
    try {
      final walletData = {
        'address': address,
        'username': _generateSimpleUsername(address),
        'chainId': '1',
        'network': 'Ethereum',
        'isConnected': true,
        'connectionType': 'desktop',
        'token': token,
        'connectedAt': DateTime.now().toIso8601String(),
      };

      await _storage.write(
          key: 'wallet_session', value: json.encode(walletData));
      await _storage.write(key: 'wallet_address', value: address);

      _cachedData = walletData;
      _isInitialized = true;

      debugPrint('💾 Desktop wallet connection saved ✅');
    } catch (e) {
      debugPrint('❌ Failed to save desktop wallet connection: $e');
    }
  }

  /// 🔍 Check if user is connected on macOS
  static Future<bool> isDesktopWalletConnected() async {
    try {
      final data = await getSessionWalletData();
      return data['isConnected'] == true &&
          data['address']?.toString().isNotEmpty == true;
    } catch (e) {
      debugPrint('⚠️ isDesktopWalletConnected failed: $e');
      return false;
    }
  }

  /// 🧹 Clean Disconnect
  static Future<void> disconnect() async {
    try {
      debugPrint('👋 Disconnecting session...');
      
      final data = await getSessionWalletData();
      final address = data['address'];
      
      if (ReownSession.modal != null) {
        await ReownSession.modal!.disconnect();
      }
      
      await _storage.delete(key: 'wallet_session');
      await _storage.delete(key: 'wallet_address'); 
      
      _cachedData = null;
      _isInitialized = false;
      
      if (address != null && address.toString().isNotEmpty) {
        FilebaseService.clearCache(address);
      }
      
      debugPrint('✅ Disconnected and caches cleared');
    } catch (e) {
      debugPrint('❌ Error disconnecting: $e');
    }
  }

  static Map<String, dynamic> getCachedData() {
    if (_cachedData != null) {
      return Map<String, dynamic>.from(_cachedData!);
    }
    return {
      'address': '',
      'username': 'StarWanderer',
      'chainId': '1',
      'network': 'Ethereum',
      'isConnected': false,
      'accounts': [],
    };
  }

  static void clearCache() {
    _cachedData = null;
    _isInitialized = false;
  }

  static String _generateSimpleUsername(String walletAddress) {
    if (walletAddress.isEmpty || walletAddress.length < 8) {
      return 'StarWanderer';
    }

    final clean = walletAddress.startsWith('0x')
        ? walletAddress.substring(2)
        : walletAddress;

    final chunk1 = int.parse(clean.substring(0, 4), radix: 16);
    final chunk2 = int.parse(clean.substring(4, 8), radix: 16);

    final star = _starNames[chunk1 % _starNames.length];
    final word = _coolWords[chunk2 % _coolWords.length];

    return '$star$word';
  }

  static const List<String> _starNames = [
    'Vega', 'Altair', 'Sirius', 'Rigel', 'Spica', 'Deneb', 'Polaris', 'Castor',
    'Pollux', 'Regulus', 'Capella', 'Procyon', 'Canopus', 'Arcturus', 'Antares',
    'Aldebaran', 'Betelgeuse', 'Bellatrix', 'Elnath', 'Alnilam', 'Alnitak',
    'Mintaka', 'Saiph', 'Hadar', 'Shaula', 'Sargas', 'Kaus', 'Nunki',
    'Ascella', 'Dabih', 'Nashira', 'Deneb', 'Sadr', 'Gienah', 'Epsilon',
    'Albireo', 'Vega', 'Sheliak', 'Sulafat', 'Delta', 'Gamma', 'Theta',
    'Iota', 'Kappa', 'Lambda', 'Mu', 'Nu', 'Omicron', 'Pi', 'Rho', 'Sigma',
    'Tau', 'Upsilon', 'Phi', 'Chi', 'Psi', 'Omega', 'Alpha', 'Beta', 'Martian',
    'Sonald', 'Larack', 'Ligma', 'MrLeast', 'Bruce', 'Jhon'
  ];

  static const List<String> _coolWords = [
    'Walker', 'Rider', 'Seeker', 'Finder', 'Keeper', 'Guard', 'Scout', 'Hunter',
    'Sage', 'Mage', 'Seer', 'Oracle', 'Spirit', 'Soul', 'Heart', 'Mind',
    'Dream', 'Vision', 'Echo', 'Whisper', 'Shadow', 'Light', 'Flame', 'Frost',
    'Storm', 'Wind', 'Rain', 'Snow', 'Dawn', 'Dusk', 'Moon', 'Star',
    'Void', 'Aether', 'Cosmos', 'Galaxy', 'Nebula', 'Nova', 'Quasar', 'Pulsar',
    'Comet', 'Meteor', 'Asteroid', 'Planet', 'Orbit', 'Eclipse', 'Corona',
    'Flare', 'Burst', 'Wave', 'Field', 'Force', 'Energy', 'Power', 'Spark',
    'Glow', 'Shine', 'Beam', 'Ray', 'Flash', 'Bolt', 'Strike', 'Surge', 'Vigilante',
    'Frump', 'Babama', 'Balls', 'Wayne', 'Pork'
  ];
}