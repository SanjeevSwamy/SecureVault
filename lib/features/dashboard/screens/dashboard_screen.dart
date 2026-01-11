import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_vault/services/wallet_service.dart';
import 'package:secure_vault/services/filebase_service.dart';
import 'package:reown_appkit/reown_appkit.dart';
import '../../../core/reown_session.dart';
import '../widgets/recent_uploads_card.dart';
import '../widgets/storage_summary_card.dart';
import '../../upload/screens/upload_screen.dart';
import '../../access/screens/access_file_screen.dart';
import '../../keys/screens/key_management_screen.dart';
import '../../settings/screens/settings_screen.dart';
import 'dart:ui';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  bool _isNavigating = false;

  final List<Widget> _screens = [
    const DashboardContent(),
    const FileAccessScreen(),
    const KeyManagementScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _ensureWalletConnection();
  }

  /// 🩹 Self-Healing: Wake up Wallet Engine & Verify Permissions
  Future<void> _ensureWalletConnection() async {
    // If already running, verify permissions
    if (ReownSession.modal != null) {
      _verifyPermissions(ReownSession.modal!);
      return;
    }

    debugPrint('🔌 Dashboard: Waking up Wallet Engine...');
    
    try {
      final modal = ReownAppKitModal(
        context: context,
        projectId: '517c51ad11e07624e35ac450faa98424',
        metadata: const PairingMetadata(
          name: 'SecureVault',
          description: 'Decentralized File Storage',
          url: 'https://securevault.app',
          icons: ['https://securevault.app/logo.png'],
          redirect: Redirect(
            native: 'securevault://', 
            universal: 'https://securevault.app'
          ),
        ),
        // 🔒 STRICT CONFIG: Must match ConnectWalletScreen
        requiredNamespaces: {
          'eip155': const RequiredNamespace(
            chains: ['eip155:11155111'], // Sepolia is Mandatory
            methods: ['personal_sign', 'eth_sendTransaction', 'eth_signTransaction'],
            events: ['chainChanged', 'accountsChanged'],
          ),
        },
        optionalNamespaces: {
          'eip155': const RequiredNamespace(
            chains: ['eip155:1'], // Mainnet is Optional
            methods: ['personal_sign', 'eth_sendTransaction', 'eth_signTransaction'],
            events: ['chainChanged', 'accountsChanged'],
          ),
        },
      );

      await modal.init();
      ReownSession.modal = modal;
      debugPrint('✅ Dashboard: Wallet Engine restored!');
      
      // Check permissions after init
      if (modal.isConnected) {
        _verifyPermissions(modal);
      }
      
    } catch (e) {
      debugPrint('❌ Dashboard: Wallet Error: $e');
    }
  }

  // 👮‍♂️ THE BOUNCER CHECK
 // 👮‍♂️ THE BOUNCER CHECK (RELAXED VERSION)
  void _verifyPermissions(ReownAppKitModal modal) {
    final session = modal.session;
    if (session == null) return;

    // Check if Sepolia is in the APPROVED namespaces (optional is fine)
    final namespaces = session.toJson()['namespaces'];
    final chains = namespaces?['eip155']?['chains'] as List?;
    final approvedChains = chains?.map((e) => e.toString()).toList() ?? [];
    
    // We check if 11155111 is *available* to switch to, not necessarily active right now
    if (!approvedChains.contains('eip155:11155111')) {
      debugPrint('⚠️ Sepolia not authorized. Requesting switch...');
      
      // Attempt to switch instead of logout
      modal.selectChain(
        ReownAppKitModalNetworkInfo(
          name: 'Sepolia',
          chainId: '11155111',
          currency: 'ETH',
          rpcUrl: 'https://ethereum-sepolia-rpc.publicnode.com',
          explorerUrl: 'https://sepolia.etherscan.io/',
          isTestNetwork: true,
        ),
      );
    } else {
      debugPrint('🛡️ Session verified: Sepolia access authorized.');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 115,
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned(
                bottom: 20,
                left: 12,
                right: 12,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutQuart,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(42.5),
                    border: Border.all(
                      color: const Color(0xFF2563EB).withOpacity(0.08),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(42.5),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildFloatingNavItem(0, Icons.apps_rounded, Icons.apps_outlined, 'Home'),
                            _buildFloatingNavItem(1, Icons.download_rounded, Icons.download_outlined, 'Access'),
                            _buildFloatingNavItem(2, Icons.key_rounded, Icons.key_outlined, 'Keys'),
                            _buildFloatingNavItem(3, Icons.settings_rounded, Icons.settings_outlined, 'Settings'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _selectedIndex == 0
          ? SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: FloatingActionButton(
                  onPressed: _isNavigating
                      ? null
                      : () async {
                          setState(() => _isNavigating = true);
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const UploadScreen()),
                          );
                          if (mounted) {
                            setState(() => _isNavigating = false);
                            // Refresh logic implicitly handled by child widgets
                          }
                        },
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: const Icon(Icons.add_rounded, size: 28),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildFloatingNavItem(int index, IconData selectedIcon, IconData unselectedIcon, String label) {
    final isSelected = _selectedIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (!_isNavigating && _selectedIndex != index) {
            setState(() {
              _isNavigating = true;
              _selectedIndex = index;
            });
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) setState(() => _isNavigating = false);
            });
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? selectedIcon : unselectedIcon,
              size: 26,
              color: isSelected ? const Color(0xFF2563EB) : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(height: 4),
            if (isSelected)
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2563EB),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DashboardContent extends StatefulWidget {
  const DashboardContent({super.key});

  @override
  State<DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<DashboardContent> with AutomaticKeepAliveClientMixin {
  String _userName = 'User';
  bool _hasLoadedUserData = false;
  String _walletAddress = '';

  @override
  void initState() {
    super.initState();
    if (!_hasLoadedUserData) {
      _loadUserData();
    }
  }

  Future<void> _loadUserData() async {
    if (_hasLoadedUserData) return;
    try {
      final data = await SessionWalletService.getSessionWalletData();
      final address = data['address'] ?? '';
      final username = data['username'] ?? 'Homosapien';
      
      if (mounted && address.isNotEmpty) {
        setState(() {
          _userName = username;
          _walletAddress = address;
          _hasLoadedUserData = true;
        });
        
        await FilebaseService.restoreFilesOnAppStart(address);
        if (mounted) setState(() {});
      } else if (mounted) {
        setState(() {
          _userName = 'Homosapien';
          _hasLoadedUserData = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userName = 'Homosapien';
          _hasLoadedUserData = true;
        });
      }
    }
  }

  Future<void> _refreshDashboard() async {
    try {
      if (_walletAddress.isNotEmpty) {
        FilebaseService.clearCache(_walletAddress);
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Dashboard refreshed'), backgroundColor: const Color(0xFF059669), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Refresh failed'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refreshDashboard,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    Text('Welcome back,', style: GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.w700)),
                    Text(_userName, style: GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.w300, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const StorageSummaryCard(),
                  const SizedBox(height: 40),
                  const Text('Recent Files', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 20),
                  const RecentUploadsCard(),
                  const SizedBox(height: 120),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}