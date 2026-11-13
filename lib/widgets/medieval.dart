import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/color_utils.dart';

/// Fondo de pergamino: más claro al centro, tostado hacia los bordes.
class ParchmentBackground extends StatelessWidget {
  final Widget child;

  const ParchmentBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Ocupa toda la pantalla aunque el contenido sea más corto.
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.3),
            radius: 1.25,
            colors: [
              AppColors.vellum,
              AppColors.parchment,
              AppColors.parchmentDeep,
            ],
            stops: [0, 0.6, 1],
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Fondo oscuro con el damero de rombos del ícono (rojo y azul sobre tinta).
class DiaperBackground extends StatelessWidget {
  final Widget child;

  const DiaperBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: const _DiaperPainter(), child: child),
    );
  }
}

class _DiaperPainter extends CustomPainter {
  const _DiaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.ink);

    const cell = 34.0;
    final red = Paint()..color = AppColors.crimson.withValues(alpha: 0.62);
    final blue = Paint()..color = AppColors.royal.withValues(alpha: 0.66);
    final cross =
        Paint()
          ..color = AppColors.gold.withValues(alpha: 0.42)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round;

    for (var row = 0; row * cell < size.height; row++) {
      for (var col = 0; col * cell < size.width; col++) {
        final rect = Rect.fromLTWH(
          col * cell + 2,
          row * cell + 2,
          cell - 4,
          cell - 4,
        );
        canvas.drawRect(rect, (row + col).isEven ? red : blue);
        final c = rect.center;
        const arm = 4.5;
        canvas.drawLine(c.translate(-arm, -arm), c.translate(arm, arm), cross);
        canvas.drawLine(c.translate(-arm, arm), c.translate(arm, -arm), cross);
      }
    }

    // Viñeta para que el contenido resalte sobre el patrón.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [
            AppColors.ink.withValues(alpha: 0.30),
            AppColors.ink.withValues(alpha: 0.80),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_DiaperPainter oldDelegate) => false;
}

/// Reduce apenas el tamaño de [child] mientras se mantiene presionado.
/// No compite con los gestos del hijo: solo observa el puntero.
class PressScale extends StatefulWidget {
  final Widget child;
  final double scale;
  final bool enabled;

  const PressScale({
    super.key,
    required this.child,
    this.scale = 0.96,
    this.enabled = true,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value && mounted) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.enabled ? (_) => _set(true) : null,
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 180),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Tarjeta de pergamino con filete dorado doble y rombos en las esquinas.
class OrnateCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color color;
  final VoidCallback? onTap;

  const OrnateCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.color = AppColors.vellum,
    this.onTap,
  });

  static const double radius = 14;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: color,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        child: CustomPaint(
          foregroundPainter: const _FiligreePainter(),
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
    return onTap == null ? card : PressScale(scale: 0.98, child: card);
  }
}

class _FiligreePainter extends CustomPainter {
  const _FiligreePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 5.0;
    final line =
        Paint()
          ..color = AppColors.goldDeep.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2),
        const Radius.circular(OrnateCard.radius - inset),
      ),
      line,
    );

    final gem = Paint()..color = AppColors.gold;
    const d = 3.0;
    for (final corner in [
      const Offset(inset + 6, inset + 6),
      Offset(size.width - inset - 6, inset + 6),
      Offset(inset + 6, size.height - inset - 6),
      Offset(size.width - inset - 6, size.height - inset - 6),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy - d)
          ..lineTo(corner.dx + d, corner.dy)
          ..lineTo(corner.dx, corner.dy + d)
          ..lineTo(corner.dx - d, corner.dy)
          ..close(),
        gem,
      );
    }
  }

  @override
  bool shouldRepaint(_FiligreePainter oldDelegate) => false;
}

/// Botón principal: placa de color con borde dorado y respuesta al toque.
class MedievalButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool expand;

  const MedievalButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppColors.bark,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = onColor(color);
    final radius = BorderRadius.circular(12);

    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.55,
      duration: const Duration(milliseconds: 200),
      child: PressScale(
        enabled: enabled,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.28),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color, darken(color, 0.28)],
                ),
                borderRadius: radius,
                border: Border.all(color: AppColors.gold, width: 1.5),
              ),
              child: InkWell(
                onTap: onPressed,
                borderRadius: radius,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 13,
                    horizontal: 26,
                  ),
                  child: Row(
                    mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: foreground, size: 22),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: bodyFont,
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón redondo con forma de moneda de oro.
class CoinButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const CoinButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PressScale(
        scale: 0.9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.3, -0.4),
                  colors: [AppColors.goldLight, AppColors.gold, AppColors.goldDeep],
                  stops: [0, 0.65, 1],
                ),
                border: Border.all(color: AppColors.bark, width: 2),
              ),
              child: InkWell(
                onTap: onPressed,
                customBorder: const CircleBorder(),
                child: Icon(icon, size: 32, color: AppColors.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Separador: dos filetes dorados con un rombo en medio.
class OrnamentDivider extends StatelessWidget {
  final Color color;
  final double width;

  const OrnamentDivider({
    super.key,
    this.color = AppColors.gold,
    this.width = 160,
  });

  @override
  Widget build(BuildContext context) {
    Widget line() => Expanded(child: Container(height: 1.2, color: color));
    return SizedBox(
      width: width,
      child: Row(
        children: [
          line(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(width: 7, height: 7, color: color),
            ),
          ),
          line(),
        ],
      ),
    );
  }
}

/// Hace aparecer a [child] con un fundido y un leve ascenso. [index] escalona
/// la entrada de los elementos de una lista.
class FadeSlideIn extends StatelessWidget {
  final int index;
  final Widget child;

  const FadeSlideIn({super.key, this.index = 0, required this.child});

  @override
  Widget build(BuildContext context) {
    const base = 320;
    final delay = index.clamp(0, 8) * 45;
    final total = base + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 14),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Texto de dinero que cuenta suavemente hasta el nuevo valor cuando cambia.
class AnimatedMoney extends StatelessWidget {
  final double value;
  final TextStyle? style;
  final String prefix;

  const AnimatedMoney({
    super.key,
    required this.value,
    this.style,
    this.prefix = '',
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('$prefix${formatMoney(v)}', style: style),
    );
  }
}
