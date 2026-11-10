import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A bounded, repaint-only globe; it never rebuilds the surrounding dashboard.
class DixGlobe extends StatefulWidget {
  final Color color;
  final double latitude, longitude;
  final bool animate;
  const DixGlobe({
    super.key,
    required this.color,
    this.latitude = 60.17,
    this.longitude = 24.94,
    this.animate = true,
  });
  @override
  State<DixGlobe> createState() => _DixGlobeState();
}

class _DixGlobeState extends State<DixGlobe>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 160),
  );
  List<(double, double, double)> points = [];
  double drag = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  void _animate() {
    if (widget.animate && TickerMode.valuesOf(context).enabled) {
      if (!rotation.isAnimating) rotation.repeat();
    } else {
      rotation.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate();
  }

  @override
  void didUpdateWidget(covariant DixGlobe oldWidget) {
    super.didUpdateWidget(oldWidget);
    _animate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _animate();
    } else {
      rotation.stop();
    }
  }

  Future<void> _load() async {
    final bytes = await rootBundle.load('assets/land_mask.png');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final generated = <(double, double, double)>[];
    if (data != null) {
      final pixels = data.buffer.asUint8List();
      const count = 16000;
      final golden = math.pi * (3 - math.sqrt(5));
      for (var i = 0; i < count; i++) {
        final y = 1 - 2 * (i + .5) / count,
            lat = math.asin(y),
            lon = (i * golden) % (math.pi * 2) - math.pi;
        final x = ((lon + math.pi) / (2 * math.pi) * image.width).floor().clamp(
              0,
              image.width - 1,
            ),
            py = ((math.pi / 2 - lat) / math.pi * image.height).floor().clamp(
              0,
              image.height - 1,
            );
        if (pixels[(py * image.width + x) * 4] < 100) continue;
        final radius = math.sqrt(1 - y * y);
        generated.add((radius * math.sin(lon), y, radius * math.cos(lon)));
      }
    }
    image.dispose();
    codec.dispose();
    if (mounted) setState(() => points = generated);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: GestureDetector(
      onPanUpdate: (event) => setState(() => drag += event.delta.dx * .006),
      child: CustomPaint(
        painter: _GlobePainter(
          points,
          widget.color,
          rotation,
          drag,
          widget.latitude,
          widget.longitude,
        ),
        size: Size.infinite,
      ),
    ),
  );
}

class _GlobePainter extends CustomPainter {
  final List<(double, double, double)> points;
  final Color color;
  final Animation<double> rotation;
  final double drag, latitude, longitude;
  _GlobePainter(
    this.points,
    this.color,
    this.rotation,
    this.drag,
    this.latitude,
    this.longitude,
  ) : super(repaint: rotation);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2),
        radius = math.min(size.width, size.height) * .405;
    final angle = rotation.value * math.pi * 2 + drag - .55,
        cos = math.cos(angle),
        sin = math.sin(angle);
    const tilt = .22;
    final ct = math.cos(tilt), st = math.sin(tilt);
    Offset project(double x, double y, double z) =>
        Offset(center.dx + x * radius, center.dy - y * radius);
    final rim = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius * 1.18,
        [
          color.withValues(alpha: .0),
          color.withValues(alpha: .015),
          color.withValues(alpha: .11),
          color.withValues(alpha: 0),
        ],
        [0, .7, .86, 1],
      );
    canvas.drawCircle(center, radius * 1.18, rim);
    final point = Paint();
    for (final (x, y, z) in points) {
      final rx = x * cos + z * sin,
          rz = z * cos - x * sin,
          ry = y * ct - rz * st,
          depth = rz * ct + y * st;
      if (depth < -.08) continue;
      point.color = color.withValues(
        alpha: (.05 + .38 * math.pow(math.max(0, depth), 1.5)).toDouble(),
      );
      canvas.drawCircle(
        project(rx, ry, depth),
        .55 + math.max(0, depth) * .62,
        point,
      );
    }
    // Deterministic star positions, low contrast so they never compete with text.
    final random = math.Random(71);
    for (var i = 0; i < 45; i++) {
      point.color = color.withValues(alpha: .10 + random.nextDouble() * .15);
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        random.nextDouble() * .8 + .3,
        point,
      );
    }
    final lat = latitude * math.pi / 180, lon = longitude * math.pi / 180;
    final x = math.cos(lat) * math.sin(lon),
        y = math.sin(lat),
        z = math.cos(lat) * math.cos(lon);
    final rx = x * cos + z * sin,
        rz = z * cos - x * sin,
        ry = y * ct - rz * st,
        depth = rz * ct + y * st;
    if (depth > 0) {
      final position = project(rx, ry, depth);
      canvas.drawCircle(
        position,
        9,
        Paint()..color = color.withValues(alpha: .10),
      );
      canvas.drawCircle(
        position,
        3,
        Paint()..color = color.withValues(alpha: .85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlobePainter old) =>
      old.points != points ||
      old.color != color ||
      old.drag != drag ||
      old.latitude != latitude ||
      old.longitude != longitude;
}
