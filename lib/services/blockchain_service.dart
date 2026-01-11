import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart';
import 'package:reown_appkit/reown_appkit.dart';
import '../core/reown_session.dart';

class BlockchainService {
  // ✅ CONTRACT ADDRESS
  static const String _contractAddress = "0xaA4507Ef7dd66970f1fFA82A826A9C833198e8Ea";
  
  // ✅ SEPOLIA RPC (Using the stable public node)
  static const String _rpcUrl = "https://ethereum-sepolia-rpc.publicnode.com";
  
  // ✅ CHAIN IDs
  static const String _chainId = "eip155:11155111"; // Reown format
  static const String _hexChainId = "0xaa36a7";     // Hex format for switching (11155111)

  static const String _abiJson = '''[
    {
      "anonymous": false,
      "inputs": [
        {"indexed": true, "internalType": "address", "name": "owner", "type": "address"},
        {"indexed": false, "internalType": "string", "name": "fileHash", "type": "string"},
        {"indexed": false, "internalType": "string", "name": "cid", "type": "string"},
        {"indexed": false, "internalType": "uint256", "name": "timestamp", "type": "uint256"}
      ],
      "name": "FileNotarized",
      "type": "event"
    },
    {
      "inputs": [
        {"internalType": "string", "name": "_ipfsCid", "type": "string"},
        {"internalType": "string", "name": "_fileHash", "type": "string"},
        {"internalType": "string", "name": "_encryptionType", "type": "string"}
      ],
      "name": "notarizeFile",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [
        {"internalType": "string", "name": "_fileHash", "type": "string"}
      ],
      "name": "verifyFile",
      "outputs": [
        {"internalType": "bool", "name": "", "type": "bool"},
        {"internalType": "address", "name": "", "type": "address"},
        {"internalType": "string", "name": "", "type": "string"},
        {"internalType": "uint256", "name": "", "type": "uint256"}
      ],
      "stateMutability": "view",
      "type": "function"
    }
  ]''';

  late Web3Client _client;
  late DeployedContract _contract;

  BlockchainService() {
    _initialize();
  }

  void _initialize() {
    _client = Web3Client(_rpcUrl, Client());
    _contract = DeployedContract(
      ContractAbi.fromJson(_abiJson, 'SecureVaultNotary'),
      EthereumAddress.fromHex(_contractAddress),
    );
  }

  /// 🚀 WRITE: Notarize a file (Triggers Wallet Popup)
  Future<String?> notarizeFile({
    required String cid,
    required String fileHash,
    required String encryptionType,
    required String userAddress,
  }) async {
    try {
      print('🔗 Initiating Blockchain Notarization for Hash: ${fileHash.substring(0, 10)}...');
      
      // Safety Check: Ensure Wallet is Connected
      if (ReownSession.modal?.session == null) {
        print('⚠️ Wallet not connected. Skipping notarization.');
        return null;
      }

      final session = ReownSession.modal!.session!;

      // 1. 🔀 FORCE CHAIN SWITCH
      // This ensures the wallet is on Sepolia BEFORE we send the transaction.
      try {
        print('🔀 Requesting switch to Sepolia...');
        
        // We use the generic 'request' method to call wallet_switchEthereumChain
        await ReownSession.modal!.request(
          topic: session.topic,
          chainId: 'eip155:1', // Try sending via Mainnet channel if currently there
          request: SessionRequestParams(
            method: 'wallet_switchEthereumChain',
            params: [{'chainId': _hexChainId}], // 0xaa36a7
          ),
        );
        
        // ⏳ CRITICAL DELAY: 
        // Increased to 3 seconds to give the wallet app time to handle the UI switch
        // prevents the "White Flash / No Request" bug.
        print('⏳ Waiting for wallet to switch...');
        await Future.delayed(const Duration(seconds: 3));
        
      } catch (e) {
        // If the user is ALREADY on Sepolia, this might throw an error or be ignored.
        // We catch it and proceed, hoping the user is on the right chain.
        print('ℹ️ Chain switch skipped or failed (User might already be on Sepolia): $e');
      }

      // 2. Encode the function call (ABI Encoding)
      final function = _contract.function('notarizeFile');
      final encodedCall = function.encodeCall([cid, fileHash, encryptionType]);
      final dataHex = '0x${_bytesToHex(encodedCall)}';

      // 3. Construct Transaction Object
      final transaction = {
        'from': userAddress,
        'to': _contractAddress,
        'data': dataHex,
        // We let the wallet estimate gas limit and gas price
      };

      // 4. Send via Reown (WalletConnect)
      print('🚀 Sending Transaction Request...');
      final result = await ReownSession.modal!.request(
        topic: session.topic,
        chainId: _chainId, 
        request: SessionRequestParams(
          method: 'eth_sendTransaction',
          params: [transaction],
        ),
      );

      print('✅ Transaction Sent! Hash: $result');
      return result.toString();

    } catch (e) {
      print('❌ Blockchain Error: $e');
      return null;
    }
  }

  /// 🔍 READ: Verify file integrity (Free)
  Future<Map<String, dynamic>> verifyFile(String fileHash) async {
    try {
      final function = _contract.function('verifyFile');
      
      // Call static function on blockchain (Read-only)
      final result = await _client.call(
        contract: _contract,
        function: function,
        params: [fileHash],
      );

      // Result format from Solidity: [bool isValid, address owner, string cid, uint256 timestamp]
      return {
        'isValid': result[0] as bool,
        'owner': (result[1] as EthereumAddress).hex,
        'cid': result[2] as String,
        'timestamp': DateTime.fromMillisecondsSinceEpoch((result[3] as BigInt).toInt() * 1000),
      };

    } catch (e) {
      print('❌ Verification Failed (File likely not on chain): $e');
      return {'isValid': false};
    }
  }

  // Helper to convert bytes to hex string for Web3
  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}