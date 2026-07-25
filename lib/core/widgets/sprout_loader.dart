import 'package:flutter/material.dart';

/// Indicador de carga con animación de brote emergiendo de la tierra.
/// Reemplazo directo de un CircularProgressIndicator.
///
/// En Fase 2b se puede sustituir por Lottie con `sprout_loader.json`.
class SproutLoader extends StatefulWidget {
  const SproutLoader({super.key, this.size = 120, this.label});
  final double size;
  final String? label;

  @override
  State<SproutLoader> createState() => _SproutLoaderState();
}

class _SproutLoaderState extends State<SproutLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            painter: _SproutPainter(t: _c.value),
            size: Size(widget.size, widget.size),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 8),
          Text(widget.label!, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _SproutPainter extends CustomPainter {
  _SproutPainter({required this.t});
  final double t; // 0..1

  static const _brown = Color(0xFF5D3A1C);
  static const _seed = Color(0xFF3D2614);
  static const _leafL = Color(0xFF7DBA62);
  static const _leafR = Color(0xFF5BA049);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Tierra
    final soil = Path()
      ..moveTo(w * 0.15, h * 0.85)
      ..quadraticBezierTo(w / 2, h * 0.72, w * 0.85, h * 0.85)
      ..lineTo(w * 0.85, h * 0.95)
      ..lineTo(w * 0.15, h * 0.95)
      ..close();
    canvas.drawPath(soil, Paint()..color = _brown);

    // Semilla siempre visible
    canvas.drawCircle(Offset(w / 2, h * 0.83), w * 0.045, Paint()..color = _seed);

    // Crecimiento: la escala va de 0 -> 1 -> 0 en el ciclo, con easing
    final eased = _easeOutCubic(t < 0.5 ? t * 2 : (1 - (t - 0.5) * 2));
    if (eased <= 0) return;

    // Tallo
    final stemPaint = Paint()
      ..color = _leafR
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final stemBaseY = h * 0.83;
    final stemTopY = stemBaseY - (h * 0.35) * eased;
    canvas.drawLine(
      Offset(w / 2, stemBaseY),
      Offset(w / 2, stemTopY),
      stemPaint,
    );

    // Cotiledones
    final leafScale = eased.clamp(0.0, 1.0);
    _drawLeaf(canvas, Offset(w / 2 - 14 * leafScale, stemTopY), leafScale, -0.6, _leafL);
    _drawLeaf(canvas, Offset(w / 2 + 14 * leafScale, stemTopY), leafScale, 0.6, _leafR);
  }

  void _drawLeaf(Canvas c, Offset center, double scale, double angle, Color color) {
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(angle);
    c.scale(scale);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 28, height: 12),
      const Radius.circular(12),
    );
    c.drawRRect(rrect, Paint()..color = color);
    c.restore();
  }

  double _easeOutCubic(double x) => 1 - _pow3(1 - x);
  double _pow3(double x) => x * x * x;

  @override
  bool shouldRepaint(covariant _SproutPainter old) => old.t != t;
}
