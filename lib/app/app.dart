import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_vault/features/dashboard/screens/dashboard_screen.dart';
import 'dart:io';
import '../features/splash/screens/splash_screen.dart';
import '../features/dashboard/screens/macos_wallet_init_screen.dart'; // Add this import
import '../providers/theme_provider.dart';
import 'theme/app_theme.dart';

class SecureVaultApp extends ConsumerWidget {
  const SecureVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'SecureVault',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      // Platform-specific home screen
      home: Platform.isMacOS 
          ? const MacOSWalletInitScreen()  // macOS-specific initialization
          : const SplashScreen(),          // Mobile splash screen
      debugShowCheckedModeBanner: false,
      // Add routes for navigation
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/dashboard': (context) => const DashboardScreen(), // Your existing dashboard
      },
    );
  }
}
