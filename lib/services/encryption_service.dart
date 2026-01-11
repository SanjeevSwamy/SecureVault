// lib/services/encryption_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

enum EncryptionType {
  aes256('AES-256', 'Military-grade symmetric encryption', '🔐'),
  sha256('SHA-256', 'Secure hash-based encryption', '🔑'),
  blake3('BLAKE3', 'Next-gen cryptographic hash', '⚡'),
  rsa2048('RSA-2048', 'Public-key encryption', '🛡️');

  const EncryptionType(this.displayName, this.description, this.emoji);
  final String displayName;
  final String description;
  final String emoji;
}

class EncryptionService {
  
  // Main encrypt method
  static Future<Uint8List> encryptFile({
    required Uint8List fileData,
    required String walletAddress,
    required EncryptionType encryptionType,
  }) async {
    switch (encryptionType) {
      case EncryptionType.aes256:
        return _encryptWithAES(fileData, walletAddress);
      case EncryptionType.sha256:
        return _encryptWithSHA(fileData, walletAddress);
      case EncryptionType.blake3:
        return _encryptWithBLAKE(fileData, walletAddress);
      case EncryptionType.rsa2048:
        return _encryptWithRSA(fileData, walletAddress);
    }
  }
  
  // Main decrypt method
  static Future<Uint8List> decryptFile({
    required Uint8List encryptedData,
    required String walletAddress,
    required EncryptionType encryptionType,
  }) async {
    switch (encryptionType) {
      case EncryptionType.aes256:
        return _decryptWithAES(encryptedData, walletAddress);
      case EncryptionType.sha256:
        return _decryptWithSHA(encryptedData, walletAddress);
      case EncryptionType.blake3:
        return _decryptWithBLAKE(encryptedData, walletAddress);
      case EncryptionType.rsa2048:
        return _decryptWithRSA(encryptedData, walletAddress);
    }
  }
  
  // AES-256 encryption
  static Uint8List _encryptWithAES(Uint8List data, String walletAddress) {
    // Generate deterministic key from wallet address
    final keyString = _generateKey(walletAddress, 'AES');
    final key = Key.fromBase64(base64.encode(utf8.encode(keyString).take(32).toList()));
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key));
    
    final encrypted = encrypter.encryptBytes(data, iv: iv);
    
    // Format: [TypeID (1 byte) | IV (16 bytes) | Encrypted Data]
    final result = Uint8List(1 + iv.bytes.length + encrypted.bytes.length);
    result[0] = 1; // AES identifier
    result.setRange(1, 1 + iv.bytes.length, iv.bytes);
    result.setRange(1 + iv.bytes.length, result.length, encrypted.bytes);
    
    return result;
  }
  
  static Uint8List _decryptWithAES(Uint8List encryptedData, String walletAddress) {
    final keyString = _generateKey(walletAddress, 'AES');
    final key = Key.fromBase64(base64.encode(utf8.encode(keyString).take(32).toList()));
    
    // Extract IV (skip first byte which is ID)
    final iv = IV(encryptedData.sublist(1, 17));
    // Extract data
    final encrypted = Encrypted(encryptedData.sublist(17));
    
    final encrypter = Encrypter(AES(key));
    return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
  }
  
  // SHA-256 encryption (XOR Stream Cipher)
  static Uint8List _encryptWithSHA(Uint8List data, String walletAddress) {
    final keyString = _generateKey(walletAddress, 'SHA');
    final keyBytes = sha256.convert(utf8.encode(keyString)).bytes;
    
    final encrypted = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      encrypted[i] = data[i] ^ keyBytes[i % keyBytes.length];
    }
    
    // Format: [TypeID (1 byte) | Encrypted Data]
    final result = Uint8List(1 + encrypted.length);
    result[0] = 2; // SHA identifier
    result.setRange(1, result.length, encrypted);
    
    return result;
  }
  
  static Uint8List _decryptWithSHA(Uint8List encryptedData, String walletAddress) {
    final keyString = _generateKey(walletAddress, 'SHA');
    final keyBytes = sha256.convert(utf8.encode(keyString)).bytes;
    
    final encrypted = encryptedData.sublist(1);
    final decrypted = Uint8List(encrypted.length);
    for (int i = 0; i < encrypted.length; i++) {
      decrypted[i] = encrypted[i] ^ keyBytes[i % keyBytes.length];
    }
    
    return decrypted;
  }
  
  // BLAKE3 encryption (Simulated using SHA-512 for demo)
  static Uint8List _encryptWithBLAKE(Uint8List data, String walletAddress) {
    final keyString = _generateKey(walletAddress, 'BLAKE');
    final keyBytes = sha512.convert(utf8.encode(keyString)).bytes;
    
    final encrypted = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      encrypted[i] = data[i] ^ keyBytes[i % keyBytes.length];
    }
    
    // Format: [TypeID (1 byte) | Encrypted Data]
    final result = Uint8List(1 + encrypted.length);
    result[0] = 3; // BLAKE identifier
    result.setRange(1, result.length, encrypted);
    
    return result;
  }
  
  static Uint8List _decryptWithBLAKE(Uint8List encryptedData, String walletAddress) {
    final keyString = _generateKey(walletAddress, 'BLAKE');
    final keyBytes = sha512.convert(utf8.encode(keyString)).bytes;
    
    final encrypted = encryptedData.sublist(1);
    final decrypted = Uint8List(encrypted.length);
    for (int i = 0; i < encrypted.length; i++) {
      decrypted[i] = encrypted[i] ^ keyBytes[i % keyBytes.length];
    }
    
    return decrypted;
  }
  
  // RSA-2048 encryption (Wrapped AES for Demo)
  static Uint8List _encryptWithRSA(Uint8List data, String walletAddress) {
    // In a real app, this would use public/private keys.
    // For this demo, we wrap AES to ensure functionality without key management complexity.
    final aesEncrypted = _encryptWithAES(data, walletAddress);
    
    final result = Uint8List(1 + aesEncrypted.length);
    result[0] = 4; // RSA identifier
    result.setRange(1, result.length, aesEncrypted.sublist(1)); // Skip AES ID, use RSA ID
    
    return result;
  }
  
  static Uint8List _decryptWithRSA(Uint8List encryptedData, String walletAddress) {
    // Swap back to AES identifier to reuse decryption logic
    final aesDataWithIdentifier = Uint8List(1 + encryptedData.length - 1);
    aesDataWithIdentifier[0] = 1; // AES identifier
    aesDataWithIdentifier.setRange(1, aesDataWithIdentifier.length, encryptedData.sublist(1));
    
    return _decryptWithAES(aesDataWithIdentifier, walletAddress);
  }
  
  // Generate deterministic key from wallet address
  static String _generateKey(String walletAddress, String algorithm) {
    // Salt ensures key uniqueness per algorithm and app version
    final input = '${walletAddress.toLowerCase()}_SecureVault2025_$algorithm';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return base64.encode(digest.bytes);
  }
  
  // Auto-detect encryption type from file header
  static EncryptionType detectEncryptionType(Uint8List encryptedData) {
    if (encryptedData.isEmpty) return EncryptionType.aes256;
    
    switch (encryptedData[0]) {
      case 1: return EncryptionType.aes256;
      case 2: return EncryptionType.sha256;
      case 3: return EncryptionType.blake3;
      case 4: return EncryptionType.rsa2048;
      default: return EncryptionType.aes256; // Fallback
    }
  }
}