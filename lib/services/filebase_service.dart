import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:minio/minio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart'; 
import 'encryption_service.dart';
import 'blockchain_service.dart'; 

class FilebaseService {
  // Credentials
  static const String _accessKey = 'D70E1604273764FF9D11';
  static const String _secretKey = 'ZQaXHL4AdDFjA0IDeUIT27RIK7MEL7Ii8FHPNu8w';
  static const String _bucketName = 'secure-vault-sapiens';
  static const _storage = FlutterSecureStorage();
  
  static late Minio _minio;
  static final _blockchainService = BlockchainService();
  
  // 💾 Memory Cache
  static final Map<String, List<Map<String, dynamic>>> _fileCache = {};
  static final Map<String, Map<String, dynamic>> _statsCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);

  // Initialize Filebase connection
  static Future<void> initialize() async {
    debugPrint('🚀 Initializing Filebase...');
    _minio = Minio(
      endPoint: 's3.filebase.com',
      accessKey: _accessKey,
      secretKey: _secretKey,
      useSSL: true,
    );
    debugPrint('✅ Filebase client created');
  }

  // ---------------------------------------------------------------------------
  // 📦 CACHE MANAGEMENT
  // ---------------------------------------------------------------------------

  static List<Map<String, dynamic>>? getCachedFiles(String walletAddress) {
    final cacheKey = 'files_$walletAddress';
    final timestamp = _cacheTimestamps[cacheKey];
    
    if (timestamp != null && 
        DateTime.now().difference(timestamp) < _cacheExpiry && 
        _fileCache.containsKey(cacheKey)) {
      return _fileCache[cacheKey];
    }
    return null;
  }
  
  static Map<String, dynamic>? getCachedStats(String walletAddress) {
    final cacheKey = 'stats_$walletAddress';
    final timestamp = _cacheTimestamps[cacheKey];
    
    if (timestamp != null && 
        DateTime.now().difference(timestamp) < _cacheExpiry && 
        _statsCache.containsKey(cacheKey)) {
      return _statsCache[cacheKey];
    }
    return null;
  }
  
  static void _cacheFiles(String walletAddress, List<Map<String, dynamic>> files) {
    final cacheKey = 'files_$walletAddress';
    _fileCache[cacheKey] = files;
    _cacheTimestamps[cacheKey] = DateTime.now();
    
    int totalSize = files.fold(0, (sum, file) => sum + (file['size'] as int? ?? 0));
    _statsCache['stats_$walletAddress'] = {
      'totalFiles': files.length,
      'totalSize': totalSize,
    };
  }
  
  static Future<void> manuallyAddFileToCache(Map<String, dynamic> newFile, String walletAddress) async {
    List<Map<String, dynamic>> currentFiles = getCachedFiles(walletAddress) ?? [];
    if (currentFiles.isEmpty) {
      currentFiles = await getUserFiles(walletAddress);
    }
    
    currentFiles.insert(0, newFile);
    _cacheFiles(walletAddress, currentFiles);
    
    await _storage.write(key: 'files_$walletAddress', value: json.encode(currentFiles));
    debugPrint('🚀 Manually updated local cache with: ${newFile['name']}');
  }
  
  static void clearCache(String walletAddress) {
    final fileKey = 'files_$walletAddress';
    final statsKey = 'stats_$walletAddress';
    _fileCache.remove(fileKey);
    _statsCache.remove(statsKey);
    _cacheTimestamps.remove(fileKey);
    _cacheTimestamps.remove(statsKey);
  }

  // ---------------------------------------------------------------------------
  // 🚀 UPLOAD LOGIC (STRICT / ATOMIC)
  // ---------------------------------------------------------------------------

  static Future<Map<String, String>?> uploadEncryptedFile({
    required Uint8List fileBytes,
    required String fileName,
    required String walletAddress,
    required EncryptionType encryptionType,
      required String rawHash, // 🔥 ADD HERE

  }) async {
    String? uploadedObjectKey; // Track for rollback

    try {
      debugPrint('🔍 === FILE UPLOAD DEBUG ===');
      
      if (walletAddress.isEmpty || !walletAddress.startsWith('0x')) throw Exception('Invalid wallet');
      if (fileBytes.isEmpty) throw Exception('File is empty');
      
      String sanitizedFileName = fileName.replaceAll(RegExp(r'[^\w\.]'), '_');

      // 1. Encrypt
      debugPrint('🔐 Encrypting...');
      final encryptedData = await EncryptionService.encryptFile(
        fileData: fileBytes,
        walletAddress: walletAddress,
        encryptionType: encryptionType,
      );
      final integrityHash = sha256.convert(encryptedData).toString();

      // 2. Upload to IPFS
      debugPrint('📤 Uploading to IPFS...');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final objectKey = '${timestamp}_${sanitizedFileName}_${encryptionType.name}';
      uploadedObjectKey = objectKey; 

      await _minio.putObject(
        _bucketName,
        objectKey,
        Stream.fromIterable([encryptedData]),
        size: encryptedData.length,
        metadata: {
          'original-name': fileName,
          'encryption-type': encryptionType.name,
          'encrypted-by': walletAddress,
          'integrity-hash': integrityHash,
        },
      );
      debugPrint('✅ Uploaded to IPFS: $objectKey');

      // 3. Notarize
      debugPrint('⛓️ Notarizing on Sepolia Network...');
      final txHash = await _blockchainService.notarizeFile(
        cid: objectKey,
        fileHash: integrityHash,
        encryptionType: encryptionType.name,
        userAddress: walletAddress,
      );

      // 🛑 ROLLBACK CHECK
      if (txHash == null || txHash.isEmpty) {
        throw Exception('Transaction rejected by user');
      }
      debugPrint('🎉 Notarization Tx: $txHash');
      
      // 4. Save Metadata (Only if Tx succeeded)
     await _saveFileMetadata(
  objectKey, 
  fileName, 
  walletAddress, 
  fileBytes.length, 
  encryptionType,
  integrityHash,
  txHash,
  rawHash,
);

      await syncMetadataToCloud(walletAddress);
      
      return {
        'cid': objectKey,
        'txHash': txHash,
      };
      
    } catch (e) {
      debugPrint('❌ Upload Process Failed: $e');
      
      // 🗑️ ROLLBACK LOGIC
      if (uploadedObjectKey != null) {
        debugPrint('🧹 Rolling back: Deleting orphaned file from IPFS...');
        try {
          await _minio.removeObject(_bucketName, uploadedObjectKey);
          debugPrint('✅ Rollback successful.');
        } catch (cleanupError) {
          debugPrint('⚠️ Cleanup failed: $cleanupError');
        }
      }
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // 📥 DOWNLOAD LOGIC
  // ---------------------------------------------------------------------------

  static Future<Uint8List?> downloadDecryptedFile({
    required String cid,
    required String walletAddress,
  }) async {
    try {
      debugPrint('📥 Downloading: $cid');
      final minioStream = await _minio.getObject(_bucketName, cid);
      final encryptedData = await _readMinioStreamToBytes(minioStream);
      
      final encryptionType = EncryptionService.detectEncryptionType(encryptedData);
      
      return await EncryptionService.decryptFile(
        encryptedData: encryptedData,
        walletAddress: walletAddress,
        encryptionType: encryptionType,
      );
    } catch (e) {
      debugPrint('❌ Download error: $e');
      return null;
    }
  }

  static Future<Uint8List> _readMinioStreamToBytes(dynamic minioStream) async {
    final chunks = <int>[];
    await for (final chunk in minioStream) {
      if (chunk is List<int>) chunks.addAll(chunk);
      else if (chunk is Uint8List) chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }

  // ---------------------------------------------------------------------------
  // 🔄 SYNC & RECOVERY
  // ---------------------------------------------------------------------------

  static Future<void> saveFileListToIPFS(String walletAddress, List<Map<String, dynamic>> files) async {
    try {
      final fileListJson = json.encode({
        'walletAddress': walletAddress,
        'files': files,
        'lastUpdated': DateTime.now().toIso8601String(),
        'version': '1.0',
      });
      final fileListBytes = utf8.encode(fileListJson);
      final metadataKey = '${walletAddress}_METADATA.json';
      
      await _minio.putObject(
        _bucketName,
        metadataKey,
        Stream.fromIterable([fileListBytes]),
        size: fileListBytes.length,
        metadata: {'content-type': 'application/json', 'wallet-address': walletAddress},
      );
    } catch (e) { 
      debugPrint('Failed to save file list: $e'); 
    }
  }

  static Future<List<Map<String, dynamic>>> getFileListFromIPFS(String walletAddress) async {
    try {
      final metadataKey = '${walletAddress}_METADATA.json';
      final stream = await _minio.getObject(_bucketName, metadataKey);
      final bytes = await _readMinioStreamToBytes(stream);
      final data = json.decode(utf8.decode(bytes));
      return List<Map<String, dynamic>>.from(data['files'] ?? []);
    } catch (e) { 
      return []; 
    }
  }

  static Future<void> syncMetadataToCloud(String walletAddress) async {
    try {
      final localFiles = await getUserFiles(walletAddress);
      await saveFileListToIPFS(walletAddress, localFiles);
    } catch (e) { 
      debugPrint('Metadata sync failed: $e'); 
    }
  }

  static Future<void> restoreFromCloud(String walletAddress) async {
    try {
      debugPrint('☁️ Attempting to restore metadata from IPFS...');
      final cloudFiles = await getFileListFromIPFS(walletAddress);
      
      if (cloudFiles.isNotEmpty) {
        await _storage.write(key: 'files_$walletAddress', value: json.encode(cloudFiles));
        _cacheFiles(walletAddress, cloudFiles);
        debugPrint('✅ Restored ${cloudFiles.length} files from cloud metadata.');
      } else {
        debugPrint('⚠️ No cloud metadata found.');
      }
    } catch (e) { 
      debugPrint('Cloud restore failed: $e'); 
    }
  }

  static Future<void> recoverLostFiles(String walletAddress) async {
    debugPrint('🕵️‍♂️ Starting deep recovery scan for $walletAddress...');
    try {
      final localFiles = await getUserFiles(walletAddress);
      final localCids = localFiles.map((f) => f['cid']).toSet();
      bool foundNew = false;

      final objectsStream = _minio.listObjectsV2(_bucketName, prefix: '');
      
      await for (var result in objectsStream) {
        for (var obj in result.objects) {
          final key = obj.key;
          
          if (key != null && !localCids.contains(key) && !key.contains('_METADATA')) {
             try {
               final stat = await _minio.statObject(_bucketName, key);
               final metadata = stat.metaData;
               
               if (metadata != null && 
                   metadata['encrypted-by']?.toLowerCase() == walletAddress.toLowerCase()) {
                 
                 debugPrint('♻️ Found lost file: $key');
                 
                 final encryptionTypeStr = metadata['encryption-type'] ?? 'aes256';
                 final recoveredFile = {
                    'cid': key,
                    'name': metadata['original-name'] ?? 'Recovered File',
                    'size': stat.size,
                    'encryptionType': encryptionTypeStr,
                    'encryptionName': 'Recovered',
                    'encryptionEmoji': '📦',
                    'uploadedAt': stat.lastModified?.toIso8601String() ?? DateTime.now().toIso8601String(),
                    'type': (metadata['original-name'] ?? '').split('.').last,
                    'walletAddress': walletAddress,
                    'integrityHash': metadata['integrity-hash'],
                    'isVerified': false, 
                 };
                 
                 localFiles.add(recoveredFile);
                 localCids.add(key); 
                 foundNew = true; 
               }
             } catch (e) {
               // Skip unauthorized objects
             }
          }
        }
      }
      
      if (foundNew) {
        localFiles.sort((a, b) => b['uploadedAt'].compareTo(a['uploadedAt']));
        await _storage.write(key: 'files_$walletAddress', value: json.encode(localFiles));
        _cacheFiles(walletAddress, localFiles); 
        await syncMetadataToCloud(walletAddress);
        debugPrint('✅ Recovery complete. Synced new files.');
      } else {
        debugPrint('✅ Recovery scan complete. No missing files found.');
      }
    } catch (e) {
      debugPrint('Recovery scan error: $e');
    }
  }

  static Future<void> restoreFilesOnAppStart(String walletAddress) async {
    await restoreFromCloud(walletAddress);
  }

  static void _backgroundSync(String walletAddress) {
    restoreFromCloud(walletAddress);
  }

  // ---------------------------------------------------------------------------
  // 💾 LOCAL STORAGE
  // ---------------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> getUserFiles(String w) async {
    final s = await _storage.read(key: 'files_$w') ?? '[]';
    return List<Map<String, dynamic>>.from(json.decode(s));
  }
  
  static Future<List<Map<String, dynamic>>> getUserFilesWithSync(String w) async {
    final c = getCachedFiles(w);
    if (c != null) { 
      _backgroundSync(w); 
      return c; 
    }
    
    final f = await getUserFiles(w);
    _cacheFiles(w, f);
    return f;
  }

  static Future<bool> deleteFile({required String cid, required String walletAddress}) async {
     try {
       await _minio.removeObject(_bucketName, cid);
       final files = await getUserFiles(walletAddress);
       files.removeWhere((f) => f['cid'] == cid);
       await _storage.write(key: 'files_$walletAddress', value: json.encode(files));
       await syncMetadataToCloud(walletAddress);
       clearCache(walletAddress);
       return true;
     } catch (e) { 
       return false; 
     }
  }

  static Future<Map<String, dynamic>> getStorageStats(String w) async { 
    final files = await getUserFiles(w);
    int totalSize = files.fold(0, (sum, file) => sum + (file['size'] as int? ?? 0));
    return {
      'totalFiles': files.length,
      'totalSize': totalSize,
    };
  }

  // ✅ THIS WAS MISSING
  static Future<void> _saveFileMetadata(
    String cid, 
    String fileName, 
    String walletAddress, 
    int fileSize,
    EncryptionType encryptionType,
    String? integrityHash, 
    String? txHash,   
      String rawHash,

    
         
  ) async {
    try {
      final filesJson = await _storage.read(key: 'files_$walletAddress') ?? '[]';
      final existingFiles = List<Map<String, dynamic>>.from(json.decode(filesJson));
      
    final newFile = {
  'cid': cid,
  'name': fileName,
  'size': fileSize,
  'encryptionType': encryptionType.name,
  'encryptionName': encryptionType.displayName,
  'encryptionEmoji': encryptionType.emoji,
  'uploadedAt': DateTime.now().toIso8601String(),
  'type': fileName.split('.').last.toLowerCase(),
  'walletAddress': walletAddress,
  'integrityHash': integrityHash,
  'txHash': txHash,
  'isVerified': txHash != null,
  'rawHash': rawHash,
};
      
      existingFiles.insert(0, newFile);
      if (existingFiles.length > 100) existingFiles.removeRange(100, existingFiles.length);
      
      await _storage.write(key: 'files_$walletAddress', value: json.encode(existingFiles));
      
      // Update cache instantly
      manuallyAddFileToCache(newFile, walletAddress);
      
      debugPrint('💾 File metadata saved locally');
    } catch (e) {
      debugPrint('Error saving file metadata: $e');
    }
  }
}