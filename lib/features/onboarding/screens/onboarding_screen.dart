import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_vault/features/auth/screens/connect_wallet_screen.dart';
import 'dart:math' as math;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _fadeController;
  late AnimationController _floatController;
  late AnimationController _bubbleController;
  late AnimationController _pageTransitionController;
  int _currentPage = 0;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      title: 'Secure\nVault',
      subtitle: 'Your files are protected with\nend-to-end encryption',
      icon: Icons.security_rounded,
      color: const Color(0xFF2563EB),
    ),
    OnboardingPage(
      title: 'Global\nAccess',
      subtitle: 'Access your files from anywhere\nin the world, anytime',
      icon: Icons.public_rounded,
      color: const Color(0xFF0891B2),
    ),
    OnboardingPage(
      title: 'Ready to\nStart',
      subtitle: 'Everything is set up and ready\nfor your secure storage',
      icon: Icons.rocket_launch_rounded,
      color: const Color(0xFF059669),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _floatController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );

    _bubbleController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    );

    _pageTransitionController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _startAnimations();
  }

  void _startAnimations() {
    _fadeController.forward();
    _floatController.repeat(reverse: true);
    _bubbleController.repeat();
    _pageTransitionController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    _floatController.dispose();
    _bubbleController.dispose();
    _pageTransitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Theme.of(context).scaffoldBackgroundColor, // Your dark background
      body: SafeArea(
        child: Stack(
          children: [
            // Animated background bubbles matching your theme
            _buildAnimatedBackground(),

            // Main content
            Column(
              children: [
                // Clean header with skip
                _buildHeader(),

                // Page content with smooth transitions
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: _onPageChanged,
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      return AnimatedBuilder(
                        animation: _pageTransitionController,
                        builder: (context, child) {
                          return _buildPage(_pages[index], index);
                        },
                      );
                    },
                  ),
                ),

                // Bottom navigation matching your theme
                _buildBottomNavigation(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _bubbleController,
        builder: (context, child) {
          return Stack(
            children: List.generate(10, (index) {
              final progress = (_bubbleController.value + (index * 0.15)) % 1.0;
              final size = 30.0 + (index % 3) * 15.0;
              final opacity = 0.02 + (index % 2) * 0.01;
              final speed = 0.3 + (index % 2) * 0.2;

              return Positioned(
                left: (index % 4) * (MediaQuery.of(context).size.width / 3) +
                    (math.sin(progress * 2 * math.pi) * 20),
                top: 80 +
                    (index * 90) +
                    (progress * speed * MediaQuery.of(context).size.height),
                child: Transform.rotate(
                  angle: progress * math.pi,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withOpacity(opacity),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return FadeTransition(
      opacity: _fadeController,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Progress indicator matching your theme
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color:
                    Theme.of(context).colorScheme.surface, // Your surface color
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF2563EB).withOpacity(0.1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                '${_currentPage + 1} / ${_pages.length}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2563EB),
                  letterSpacing: -0.1,
                ),
              ),
            ),

            // Skip button matching your theme
            TextButton(
              onPressed: _skipToAuth,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Skip',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(OnboardingPage page, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 80),

          // Floating icon matching your dashboard style
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.scale(
                scale: 0.8 + (0.2 * value),
                child: AnimatedBuilder(
                  animation: _floatController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, -8 * _floatController.value),
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              page.color,
                              page.color == const Color(0xFF2563EB)
                                  ? const Color(0xFF0891B2)
                                  : page.color == const Color(0xFF0891B2)
                                      ? const Color(0xFF059669)
                                      : const Color(0xFF2563EB),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: page.color.withOpacity(0.25),
                              blurRadius: 24,
                              spreadRadius: 0,
                              offset: const Offset(0, 12),
                            ),
                            BoxShadow(
                              color: page.color.withOpacity(0.1),
                              blurRadius: 48,
                              spreadRadius: 0,
                              offset: const Offset(0, 24),
                            ),
                          ],
                        ),
                        child: Icon(
                          page.icon,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),

          const SizedBox(height: 80),

          // Title matching your typography
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 1000),
            curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 30 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: Text(
                    page.title,
                    style: GoogleFonts.inter(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface, // Your text color
                      letterSpacing: -1.2,
                      height: 1.1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          // Subtitle matching your theme
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 1000),
            curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: Text(
                    page.subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6), // Your secondary text
                      letterSpacing: -0.2,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),

          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return FadeTransition(
      opacity: _fadeController,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
        child: Column(
          children: [
            // Page indicators matching your theme
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (index) {
                return GestureDetector(
                  onTap: () => _goToPage(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 32 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF2563EB).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 32),

            // Navigation buttons matching your dashboard style
            Row(
              children: [
                // Back button (only show after first page)
                if (_currentPage > 0) ...[
                  Expanded(
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF2563EB).withOpacity(0.1),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _previousPage,
                          borderRadius: BorderRadius.circular(14),
                          child: Center(
                            child: Text(
                              'Back',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF2563EB),
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],

                // Next/Get Started button matching your theme
                Expanded(
                  flex: _currentPage > 0 ? 2 : 1,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withOpacity(0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _currentPage == _pages.length - 1
                            ? _getStarted
                            : _nextPage,
                        borderRadius: BorderRadius.circular(14),
                        child: Center(
                          child: Text(
                            _currentPage == _pages.length - 1
                                ? 'Get Started'
                                : 'Continue',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);

    // Reset and restart page transition animation
    _pageTransitionController.reset();
    _pageTransitionController.forward();
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _skipToAuth() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ConnectWalletScreen(), // Updated
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  void _getStarted() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ConnectWalletScreen(), // Updated
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
            )),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }
}

class OnboardingPage {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}
