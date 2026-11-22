import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math_64.dart' show Quaternion, Vector3;

import '../shared/palette.dart';

class InteractiveCapsule extends StatefulWidget {
  const InteractiveCapsule({
    super.key,
    required this.scroll,
    required this.useSensors,
  });

  final ScrollController scroll;
  final bool useSensors;

  @override
  State<InteractiveCapsule> createState() => _InteractiveCapsuleState();
}

class _InteractiveCapsuleState extends State<InteractiveCapsule>
    with TickerProviderStateMixin {
  static final _program = ui.FragmentProgram.fromAsset('shaders/capsule.frag');

  final _tilt = ValueNotifier(Offset.zero);
  late final _lift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  );
  late final _settle =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 540),
        value: 1,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _syncMotion();
      });
  late final _movement = Listenable.merge([_lift, _settle]);
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<AccelerometerEvent>? _subscription;
  ui.FragmentShader? _shader;
  static final _restPose =
      Quaternion.axisAngle(Vector3(0, 0, 1), .48) *
      Quaternion.axisAngle(Vector3(0, 1, 0), -.14) *
      Quaternion.axisAngle(Vector3(1, 0, 0), .10);
  Quaternion _rotation = Quaternion.identity();
  double _lateral = 0;
  int? _dragPointer;
  Offset _dragPosition = Offset.zero;
  bool _dragging = false;
  bool _visible = true;
  bool _reduceMotion = false;
  bool _foreground = false;
  bool _routeActive = false;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        _updateSubscription();
      },
    );
    widget.scroll.addListener(_onScroll);
    unawaited(_loadShader());
  }

  Future<void> _loadShader() async {
    try {
      final program = await _program;
      if (mounted) setState(() => _shader = program.fragmentShader());
    } on Exception catch (error) {
      debugPrint('Unable to load the capsule shader: $error');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _routeActive =
        (ModalRoute.isCurrentOf(context) ?? true) && TickerMode.of(context);
    _updateSubscription();
  }

  @override
  void didUpdateWidget(covariant InteractiveCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scroll != widget.scroll) {
      oldWidget.scroll.removeListener(_onScroll);
      widget.scroll.addListener(_onScroll);
      _onScroll();
    }
    _updateSubscription();
  }

  void _onScroll() {
    if (!widget.scroll.hasClients) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final top = viewport.getOffsetToReveal(box, 0).offset;
    final visible = widget.scroll.offset < top + box.size.height;
    if (_visible == visible) return;
    _visible = visible;
    _updateSubscription();
  }

  bool get _motionActive =>
      _foreground && _routeActive && _visible && !_reduceMotion;

  void _syncMotion() {
    if (!_motionActive) {
      _lift.stop();
      _dragPointer = null;
      _dragging = false;
      if (!_settle.isCompleted) _settle.value = 1;
    } else if (_dragPointer != null || !_settle.isCompleted) {
      _lift.stop();
    } else if (!_lift.isAnimating) {
      _lift.repeat(reverse: true);
    }
  }

  void _updateSubscription() {
    _syncMotion();
    if (!widget.useSensors || !_motionActive) {
      _stopSensors();
      return;
    }
    _subscription ??=
        accelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 50),
        ).listen(
          _onTilt,
          onError: (Object _) => _stopSensors(),
          cancelOnError: true,
        );
  }

  void _onTilt(AccelerometerEvent event) {
    final target = Offset(
      (event.x / 9.81).clamp(-1.0, 1.0).toDouble(),
      (-event.z / 9.81).clamp(-1.0, 1.0).toDouble(),
    );
    if (!target.isFinite) return;
    final eased = Offset.lerp(_tilt.value, target, .24)!;
    if ((eased - _tilt.value).distance > .012) _tilt.value = eased;
  }

  void _stopSensors({bool reset = true}) {
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    if (reset) _tilt.value = Offset.zero;
  }

  double get _manualAmount => 1 - Curves.easeOutCubic.transform(_settle.value);

  Quaternion _manualPose(double amount) {
    if (amount == 0) return Quaternion.identity();
    if (amount == 1) return _rotation;

    // q and -q describe the same pose. Choose the shorter route back to rest.
    final cosine = _rotation.w.abs().clamp(0.0, 1.0);
    if (cosine >= 1 - 1e-10) return Quaternion.identity();
    final sign = _rotation.w.isNegative ? -1.0 : 1.0;
    return Quaternion.axisAngle(
      Vector3(_rotation.x * sign, _rotation.y * sign, _rotation.z * sign),
      2 * math.acos(cosine) * amount,
    );
  }

  void _startDrag(PointerDownEvent event) {
    if (_dragPointer != null) return;
    _dragPointer = event.pointer;
    _dragPosition = event.position;
    final amount = _manualAmount;
    _rotation = _manualPose(amount);
    _lateral *= amount;
    _settle.value = 0;
    _lift.stop();
  }

  void _dragBy(Offset delta, double width) {
    if (delta == Offset.zero) return;
    setState(() {
      _dragging = true;
      // Apply each drag in camera space, regardless of the capsule's current pose.
      _rotation =
          Quaternion.axisAngle(
            Vector3(delta.dy, delta.dx, 0),
            delta.distance * (2 * math.pi) / (width * .43),
          ) *
          _rotation;
      _rotation.normalize();
      _lateral = (_lateral + delta.dx * .48 / width)
          .clamp(-.12, .12)
          .toDouble();
    });
  }

  void _endDrag(PointerEvent event) {
    if (_dragPointer != event.pointer) return;
    _dragPointer = null;
    if (_dragging) setState(() => _dragging = false);
    if (_motionActive) {
      _settle.forward();
    } else {
      _settle.value = 1;
    }
  }

  void _moveDrag(PointerEvent event, double width) {
    if (event.pointer != _dragPointer) return;
    final delta = event.position - _dragPosition;
    _dragPosition = event.position;
    _dragBy(delta, width);
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_onScroll);
    _lifecycle.dispose();
    _stopSensors(reset: false);
    _tilt.dispose();
    _lift.dispose();
    _settle.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.dark;
    final fallback = SvgPicture.asset(
      'assets/capsule/pill-${dark ? 'dark' : 'light'}.svg',
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        final size = math.min(bounds.maxWidth, 430.0);
        return Center(
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(painter: _CapsuleGlow(dark)),
                ),
                RepaintBoundary(
                  child: ValueListenableBuilder<Offset>(
                    valueListenable: _tilt,
                    builder: (context, tilt, child) {
                      final target = _reduceMotion ? Offset.zero : tilt;
                      return TweenAnimationBuilder<Offset>(
                        tween: Tween(begin: Offset.zero, end: target),
                        duration: _reduceMotion
                            ? Duration.zero
                            : Duration(milliseconds: _dragging ? 65 : 230),
                        curve: Curves.easeOutCubic,
                        child: child,
                        builder: (context, angle, child) => AnimatedBuilder(
                          animation: Listenable.merge([
                            widget.scroll,
                            _movement,
                          ]),
                          child: child,
                          builder: (context, child) {
                            final offset = widget.scroll.hasClients
                                ? widget.scroll.offset
                                : 0.0;
                            final progress = (offset / 168)
                                .clamp(0.0, 1.0)
                                .toDouble();
                            final turn = _reduceMotion ? 0.0 : progress;
                            final amount = _reduceMotion ? 0.0 : _manualAmount;
                            final orientation =
                                Quaternion.axisAngle(
                                  Vector3(0, 1, 0),
                                  angle.dx * .68 + turn * 1.05,
                                ) *
                                Quaternion.axisAngle(
                                  Vector3(1, 0, 0),
                                  -angle.dy * .59 + turn * .26,
                                ) *
                                _manualPose(amount) *
                                _restPose;
                            final shader = _shader;
                            return Transform.translate(
                              offset: Offset(
                                _lateral * size * amount,
                                turn * 48 -
                                    (_reduceMotion
                                        ? 0
                                        : 7 *
                                              Curves.easeInOutSine.transform(
                                                _lift.value,
                                              )),
                              ),
                              child: Transform.scale(
                                key: const ValueKey('capsule-projection'),
                                scale: 1 - .43 * turn,
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    key: const ValueKey('capsule-surface'),
                                    painter: _CapsuleSurface(
                                      shader,
                                      rotation: orientation,
                                      dark: dark,
                                    ),
                                    child: shader == null
                                        ? Transform.scale(
                                            scale: 1.6,
                                            child: child,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                    child: fallback,
                  ),
                ),
                if (!_reduceMotion)
                  Center(
                    child: SizedBox(
                      width: size * .88,
                      height: size * .62,
                      child: RawGestureDetector(
                        key: const ValueKey('capsule-drag-area'),
                        behavior: HitTestBehavior.opaque,
                        gestures: {
                          EagerGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                EagerGestureRecognizer
                              >(EagerGestureRecognizer.new, (_) {}),
                        },
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: _startDrag,
                          onPointerMove: (event) => _moveDrag(event, size),
                          onPointerUp: (event) {
                            _moveDrag(event, size);
                            _endDrag(event);
                          },
                          onPointerCancel: _endDrag,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CapsuleSurface extends CustomPainter {
  const _CapsuleSurface(
    this.shader, {
    required this.rotation,
    required this.dark,
  });

  final ui.FragmentShader? shader;
  final Quaternion rotation;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final shader = this.shader;
    if (shader == null) return;
    final basis = rotation.asRotationMatrix().storage;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(11, dark ? 1 : 0);
    for (var i = 0; i < basis.length; i++) {
      shader.setFloat(2 + i, basis[i]);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_CapsuleSurface old) =>
      shader != old.shader || rotation != old.rotation || dark != old.dark;
}

class _CapsuleGlow extends CustomPainter {
  const _CapsuleGlow(this.dark);

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final halo = Rect.fromCenter(
      center: center,
      width: size.width * .68,
      height: size.height * .55,
    );
    canvas.drawOval(
      halo,
      Paint()
        ..color = dark ? const Color(0x6687ad91) : const Color(0x6491b797)
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          size.width * .105,
        ),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, size.height * .22),
        width: size.width * .48,
        height: size.height * .08,
      ),
      Paint()
        ..color = dark ? const Color(0x790d1e15) : const Color(0x53425e46)
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          size.width * .044,
        ),
    );
  }

  @override
  bool shouldRepaint(_CapsuleGlow old) => dark != old.dark;
}
