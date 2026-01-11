import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web3dart/web3dart.dart'; 
import 'package:http/http.dart'; 

import '../../../services/wallet_service.dart';
import '../../../providers/theme_provider.dart';
import '../../auth/screens/connect_wallet_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> 
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  
  // 🟢 Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // 🔗 Blockchain Data
  Timer? _refreshTimer;
  int _currentBlock = 0;
  double _gasPriceGwei = 0.0;
  int _chainId = 0;
  int _latencyMs = 0; 
  bool _isSyncing = true;
  bool _isError = false;
  
  // RPC URL (Stable Public Node)
  final String _rpcUrl = "https://ethereum-sepolia-rpc.publicnode.com";

  @override
  void initState() {
    super.initState();
    // Observer to detect when app goes to background
    WidgetsBinding.instance.addObserver(this);
    
    _setupAnimation();
    _fetchLiveNetworkData();
    _startTimer();
  }

  void _setupAnimation() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    // Poll every 10 seconds to be gentle on network/battery
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchLiveNetworkData());
  }

  // 🛑 Stop polling when app is backgrounded to prevent "Failed host lookup" logs
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
      debugPrint('⏸️ App paused: Stopping blockchain polling');
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('▶️ App resumed: Restarting blockchain polling');
      _fetchLiveNetworkData();
      _startTimer();
    }
  }

  Future<void> _fetchLiveNetworkData() async {
    final client = Web3Client(_rpcUrl, Client());
    final stopwatch = Stopwatch()..start();

    try {
      final blockNumber = await client.getBlockNumber();
      final gasPrice = await client.getGasPrice();
      
      // Only fetch Chain ID once to save bandwidth
      if (_chainId == 0) {
        final netId = await client.getNetworkId();
        _chainId = netId;
      }

      stopwatch.stop();

      if (mounted) {
        setState(() {
          _currentBlock = blockNumber;
          _gasPriceGwei = gasPrice.getValueInUnit(EtherUnit.gwei);
          _latencyMs = stopwatch.elapsedMilliseconds;
          _isSyncing = false;
          _isError = false;
        });
      }
    } catch (e) {
      // Don't clutter logs if it's just a connectivity blip
      // debugPrint('⚠️ Blockchain Sync Error: $e'); 
      if (mounted) setState(() => _isError = true);
    } finally {
      await client.dispose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /*────────────────────────────  UI  ────────────────────────────*/
  @override
  Widget build(BuildContext context) {
    final isLight = ref.watch(themeProvider) == ThemeMode.light;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _header('Settings'),

            // 🚀 LIVE NETWORK CARD
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: _buildLiveNetworkCard(),
              ),
            ),

            _spacer(),

            _tile(
              icon: Icons.brightness_6_rounded,
              title: 'Appearance',
              subtitle: isLight ? 'Light mode' : 'Dark mode',
              trailing: Switch(
                value: isLight,
                onChanged: (_) => ref.read(themeProvider.notifier).toggle(),
                activeColor: const Color(0xFF2563EB),
              ),
              onTap: () => ref.read(themeProvider.notifier).toggle(),
            ),

            _spacer(),

            _tile(
              icon: Icons.developer_mode_rounded,
              title: 'IPFS Node',
              subtitle: 'Storage node details',
              trailing: const Icon(Icons.chevron_right_rounded, size: 18),
              onTap: _openDevTools,
            ),

            _spacer(),

            _tile(
              icon: Icons.logout_rounded,
              title: 'Disconnect',
              subtitle: 'End session & clear cache',
              iconColor: Colors.red,
              trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.red),
              onTap: _confirmLogout,
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveNetworkCard() {
    Color statusColor = const Color(0xFF10B981);
    String statusText = 'Excellent';
    
    if (_latencyMs > 300) {
      statusColor = Colors.orange;
      statusText = 'Fair';
    }
    if (_latencyMs > 800 || _isError) {
      statusColor = Colors.red;
      statusText = _isError ? 'Error' : 'Slow';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF2563EB).withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.hub_rounded, size: 20, color: Color(0xFF2563EB)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sepolia Network',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Row(
                        children: [
                          FadeTransition(
                            opacity: _pulseAnimation,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isSyncing ? 'Syncing...' : '$statusText • $_latencyMs ms',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              if (_chainId != 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.background,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Text(
                    'ID: $_chainId',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.background,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LATEST BLOCK',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isSyncing ? '-------' : '#$_currentBlock',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 30, color: Theme.of(context).dividerColor),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GAS PRICE',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isSyncing ? '--' : '${_gasPriceGwei.toStringAsFixed(2)} Gwei',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.dns_rounded, size: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
              const SizedBox(width: 6),
              Text(
                'Node: ${_rpcUrl.replaceFirst('https://', '')}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  SliverToBoxAdapter _spacer() => const SliverToBoxAdapter(child: SizedBox(height: 8));

  SliverToBoxAdapter _header(String txt) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
          child: Text(txt,
              style: GoogleFonts.inter(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                  color: Theme.of(context).colorScheme.onSurface)),
        ),
      );

  SliverToBoxAdapter _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    Color? iconColor,
    VoidCallback? onTap,
  }) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: (iconColor ?? const Color(0xFF2563EB)).withOpacity(.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: iconColor ?? const Color(0xFF2563EB), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.2,
                                color: Theme.of(context).colorScheme.onSurface)),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(.6))),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 12), trailing]
                ]),
              ),
            ),
          ),
        ),
      );

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: Colors.red.withOpacity(.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.logout, color: Colors.red, size: 20),
              ),
              const SizedBox(width: 12),
              Text('Disconnect', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ]),
            content: Text(
              'Are you sure you want to disconnect? This will clear your local cache.',
              style: GoogleFonts.inter(fontSize: 14, height: 1.5),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Disconnect'),
              ),
            ],
          ),
        ) ?? false;

    if (!ok || !mounted) return;

    await SessionWalletService.disconnect();

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ConnectWalletScreen()),
        (_) => false,
      );
    }
  }

  void _openDevTools() {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (_) => _DevToolsSheet());
  }
}

class _DevToolsSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 36, height: 5, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline.withOpacity(.3), borderRadius: BorderRadius.circular(2.5))),
              const SizedBox(height: 24),
              Text('Node Information', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              _infoRow(context, 'Gateway', 'Filebase IPFS'),
              _infoRow(context, 'Network', 'Sepolia Testnet'),
              _infoRow(context, 'Contract', '0xaA45...e8Ea'),
              _infoRow(context, 'Status', 'Online 🟢'),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      );

  Widget _infoRow(BuildContext ctx, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(k, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: Theme.of(ctx).colorScheme.onSurface))),
          Text(v, style: GoogleFonts.inter(fontSize: 14, color: Theme.of(ctx).colorScheme.onSurface.withOpacity(.7))),
        ]),
      );
}