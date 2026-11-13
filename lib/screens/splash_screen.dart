import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/medieval.dart';
import 'books_screen.dart';

/// Portada de la app.
class SplashScreen extends StatefulWidget {
  /// Tiempo que se muestra la portada antes de entrar a la app.
  static const Duration duration = Duration(seconds: 2);

  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _logo = AssetImage('assets/images/pennytree_logo.jpg');

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  late final Animation<double> _emblem = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0, 0.65, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _title = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.3, 0.9, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _credit = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.55, 1, curve: Curves.easeOut),
  );

  Timer? _timer;
  Timer? _introFallback;
  bool _introStarted = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(SplashScreen.duration, _goToBooks);
    // Si la imagen tarda, la animación empieza de todos modos.
    _introFallback = Timer(const Duration(milliseconds: 200), _startIntro);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // La entrada empieza cuando el emblema ya está cargado, para que no
    // aparezca el marco vacío.
    if (!_introStarted) {
      precacheImage(_logo, context).whenComplete(_startIntro);
    }
  }

  void _startIntro() {
    if (_introStarted || !mounted) return;
    _introStarted = true;
    _intro.forward();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _introFallback?.cancel();
    _intro.dispose();
    super.dispose();
  }

  void _goToBooks() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 550),
        pageBuilder: (_, __, ___) => const BooksScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation.drive(CurveTween(curve: Curves.easeInOut)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final emblemSize = (width * 0.62).clamp(160.0, 280.0);

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: DiaperBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeTransition(
                        opacity: _emblem,
                        child: ScaleTransition(
                          scale: Tween(begin: 0.86, end: 1.0).animate(_emblem),
                          child: _Emblem(size: emblemSize),
                        ),
                      ),
                      const SizedBox(height: 30),
                      FadeTransition(
                        opacity: _title,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.25),
                            end: Offset.zero,
                          ).animate(_title),
                          child: Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'PennyTree',
                                  style: displayStyle(
                                    size: 44,
                                    color: AppColors.goldLight,
                                  ).copyWith(
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 8,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const OrnamentDivider(width: 200),
                              const SizedBox(height: 12),
                              const Text(
                                'Organiza tus finanzas personales',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: bodyFont,
                                  fontSize: 20,
                                  fontStyle: FontStyle.italic,
                                  color: AppColors.parchment,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Créditos en la parte inferior
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: FadeTransition(
                    opacity: _credit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 9,
                        horizontal: 22,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.parchment,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.gold, width: 1.5),
                      ),
                      child: const Text(
                        'By Beatriz de Carbonero',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: bodyFont,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
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
    );
  }
}

/// El ícono de la app enmarcado en oro.
class _Emblem extends StatelessWidget {
  final double size;

  const _Emblem({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.goldLight, AppColors.goldDeep, AppColors.goldLight],
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: const Image(
          image: _SplashScreenState._logo,
          fit: BoxFit.cover,
          semanticLabel: 'PennyTree',
        ),
      ),
    );
  }
}
