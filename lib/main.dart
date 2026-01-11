import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'services/filebase_service.dart'; // Add this import


void main() async {
  // Add these lines for proper initialization
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Filebase IPFS service
  await FilebaseService.initialize();
  
  runApp(
    const ProviderScope(
      child: SecureVaultApp(),
    ),
  );
}
