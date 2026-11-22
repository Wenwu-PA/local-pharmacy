import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'palette.dart';

class GlassNavigation extends StatefulWidget {
  const GlassNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
    this.onPreview,
  });

  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<int>? onPreview;

  @override
  State<GlassNavigation> createState() => _GlassNavigationState();
}

class _GlassNavigationState extends State<GlassNavigation> {
  static const _destinations = [
    (Icons.home_outlined, 'Главная'),
    (Icons.medication_outlined, 'Аптека'),
    (Icons.shopping_basket_outlined, 'Корзина'),
    (Icons.settings_outlined, 'Настройки'),
  ];
  static const _inset = 5.0;
  static final _blur = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12);
  static final _program = ui.FragmentProgram.fromAsset(
    'shaders/liquid_glass.frag',
  );

  ui.FragmentShader? _shader;
  double? _dragCenter;

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) unawaited(_loadGlass());
  }

  Future<void> _loadGlass() async {
    try {
      final program = await _program;
      if (mounted) setState(() => _shader = program.fragmentShader());
    } on Exception {
      // The default backdrop blur also works on renderers without this shader.
    }
  }

  void _track(Offset position, double segment) {
    final center = ((position.dx - _inset) / segment - .5)
        .clamp(0.0, _destinations.length - 1.0)
        .toDouble();
    final previous = _dragCenter;
    if (previous == center) return;
    setState(() => _dragCenter = center);
    if (center.round() != (previous?.round() ?? widget.selected)) {
      widget.onPreview?.call(center.round());
    }
  }

  void _finish({required bool select}) {
    final target = _dragCenter?.round();
    if (target == null) return;
    setState(() => _dragCenter = null);
    if (select) widget.onSelect(target);
  }

  ui.ImageFilter _filter(double center) {
    final shader = _shader;
    if (shader == null) return _blur;
    shader.setFloat(2, center);
    return ui.ImageFilter.shader(shader);
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final corners = BorderRadius.circular(29);
    final primary = Theme.of(context).colorScheme.primary;
    final surface = context.color(PharmacyColor.nav);
    final tint = context.color(PharmacyColor.raised);
    final dark = context.dark;
    final dragging = _dragCenter != null;
    final active = _dragCenter?.round() ?? widget.selected;

    return LayoutBuilder(
      builder: (context, bounds) {
        final segment = (bounds.maxWidth - _inset * 2) / _destinations.length;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) =>
              _track(details.localPosition, segment),
          onHorizontalDragUpdate: (details) =>
              _track(details.localPosition, segment),
          onHorizontalDragEnd: (_) => _finish(select: true),
          onHorizontalDragCancel: () => _finish(select: false),
          onLongPressStart: (details) => _track(details.localPosition, segment),
          onLongPressMoveUpdate: (details) =>
              _track(details.localPosition, segment),
          onLongPressEnd: (_) => _finish(select: true),
          onLongPressCancel: () => _finish(select: false),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _dragCenter ?? widget.selected.toDouble()),
            duration: dragging || MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 230),
            curve: Curves.easeOutCubic,
            builder: (context, position, labels) {
              final lensLeft = _inset + segment * position;
              return ClipRRect(
                borderRadius: corners,
                child: BackdropFilter(
                  filter: _filter((lensLeft + segment / 2) / bounds.maxWidth),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: corners,
                      border: Border.all(
                        color: dark
                            ? context.buttonOutline
                            : Colors.white.withValues(alpha: .72),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.lerp(
                            surface,
                            Colors.white,
                            dark ? .11 : .24,
                          )!.withValues(alpha: .72),
                          surface.withValues(alpha: dark ? .69 : .78),
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: lensLeft + 1,
                          width: segment - 2,
                          top: 5,
                          bottom: 5,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: dark
                                      ? context.buttonOutline
                                      : Colors.white.withValues(
                                          alpha: dragging ? .49 : .31,
                                        ),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    tint.withValues(
                                      alpha: dragging ? .84 : .70,
                                    ),
                                    tint.withValues(alpha: .40),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .10),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        labels!,
                      ],
                    ),
                  ),
                ),
              );
            },
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.all(_inset),
                child: Row(
                  children: [
                    for (final (index, (icon, label)) in _destinations.indexed)
                      Expanded(
                        child: Semantics(
                          selected: active == index,
                          button: true,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () => widget.onSelect(index),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 50),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      icon,
                                      color: active == index
                                          ? primary
                                          : context.color(PharmacyColor.ink),
                                      size: 22,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      label,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: context.color(PharmacyColor.ink),
                                        fontWeight: active == index
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                    ),
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
          ),
        );
      },
    );
  }
}
