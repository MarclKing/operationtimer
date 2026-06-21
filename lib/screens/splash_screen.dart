import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:OpTimes/main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late AnimationController _trailCtrl;
  late AnimationController _trailFadeCtrl;

  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _trailFadeAnim;

  @override
  void initState() {
    super.initState();

    // ── Logo fade + scale ────────────────────────────────────────────
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutBack),
    );

    // ── Trail loop ───────────────────────────────────────────────────
    _trailCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    // ── Trail verzögert einblenden ───────────────────────────────────
    _trailFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _trailFadeAnim = CurvedAnimation(
      parent: _trailFadeCtrl,
      curve: Curves.easeIn,
    );

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _trailFadeCtrl.forward();
    });

    // ── Navigation ───────────────────────────────────────────────────
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => MainScreen(key: MyApp.mainScreenKey),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _trailCtrl.dispose();
    _trailFadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final logoSize = screenWidth * 0.65;

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Stack(
            children: [
              // ── Logo ─────────────────────────────────────────────────
              Positioned(
                top: screenHeight * 0.5 - (logoSize / 2),
                left: 0,
                right: 0,
                child: Center(
                  child: Image.asset(
  skin.isLight ? 'assets/logo_trans_rev.png' : 'assets/logo_trans.png',
  width: logoSize,
  fit: BoxFit.contain,
),
                ),
              ),

              // ── Dot Trail ────────────────────────────────────────────
              Positioned(
                top: screenHeight * 0.72 - 18,
                left: 0,
                right: 0,
                child: Center(
                  child: FadeTransition(
                    opacity: _trailFadeAnim,
                    child: _DotTrail(
                      controller: _trailCtrl,
                      color: skin.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dot Trail ────────────────────────────────────────────────────────────────
//
// 5 Dots gleichmäßig auf einem Kreispfad (r = 14).
// Die Gesamtgruppe rotiert — jeder Dot hat eine feste Opacity die von
// voll (Kopf) bis fast unsichtbar (Schwanz) abnimmt.
// Kein CustomPainter: jeder Dot ist ein positionierter Container.
//
class _DotTrail extends StatelessWidget {
  final AnimationController controller;
  final Color color;

  // 5 Dots, Opacities von Kopf → Schwanz
  static const int _count = 5;
  static const List<double> _opacities = [1.0, 0.72, 0.45, 0.2, 0.07];
  static const double _radius = 14.0;
  static const double _dotSize = 5.0;
  static const double _canvasSize = _radius * 2 + _dotSize + 4;

  const _DotTrail({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Aktuelle Rotation in Radians (0 → 2π)
        final double rotation = controller.value * 2 * pi;

        return SizedBox(
          width: _canvasSize,
          height: _canvasSize,
          child: Stack(
            alignment: Alignment.center,
            children: List.generate(_count, (i) {
              // Gleichmäßiger Winkelversatz zwischen den Dots (72° = 2π/5)
              final double angle = rotation + i * (2 * pi / _count);
              final double dx = _radius * sin(angle);
              final double dy = -_radius * cos(angle);

              return Positioned(
                left: _canvasSize / 2 + dx - _dotSize / 2,
                top:  _canvasSize / 2 + dy - _dotSize / 2,
                child: Container(
                  width: _dotSize,
                  height: _dotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: _opacities[i]),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}