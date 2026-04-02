import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_vault/features/dashboard/screens/dashboard_screen.dart';
import 'package:secure_vault/core/route_observer.dart';              // 👈 added
import '../features/splash/screens/splash_screen.dart';
import '../features/dashboard/screens/macos_wallet_init_screen.dart';
import '../providers/theme_provider.dart';
import 'theme/app_theme.dart';

import 'package:flutter/foundation.dart';

class SecureVaultApp extends ConsumerWidget {
  const SecureVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    Widget getHomeScreen() {
      if (kIsWeb) return const SplashScreen();
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        return const MacOSWalletInitScreen();
      }
      return const SplashScreen();
    }

    return MaterialApp(
      title: 'SecureVault',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: getHomeScreen(),
      debugShowCheckedModeBanner: false,
      navigatorObservers: [appRouteObserver],                        // 👈 added
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/dashboard': (context) => const DashboardScreen(),
      },
    );
  }
}