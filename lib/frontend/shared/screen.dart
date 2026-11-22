import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'palette.dart';

Future<T?> openScreen<T>(BuildContext context, Widget screen) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));

class PharmacyScreen extends StatelessWidget {
  const PharmacyScreen({
    super.key,
    required this.children,
    this.onAdd,
    this.addLabel,
    this.trailing,
    this.navigation,
    this.reserveNavigationSpace = false,
    this.footer,
    this.controller,
    this.minimumScrollExtent = 0,
  });

  final List<Widget> children;
  final VoidCallback? onAdd;
  final String? addLabel;
  final Widget? trailing;
  final Widget? navigation;
  final bool reserveNavigationSpace;
  final Widget? footer;
  final ScrollController? controller;
  final double minimumScrollExtent;

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final scheme = Theme.of(context).colorScheme;
    final padding = EdgeInsets.fromLTRB(
      20,
      10,
      20,
      (navigation != null || reserveNavigationSpace ? 99 : 22) +
          (footer == null ? MediaQuery.paddingOf(context).bottom : 0),
    );
    final scrollView = LayoutBuilder(
      builder: (context, bounds) => SingleChildScrollView(
        controller: controller,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: minimumScrollExtent == 0
                ? 0
                : math.max(
                    0,
                    bounds.maxHeight + minimumScrollExtent - padding.vertical,
                  ),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (canPop || onAdd != null)
                        IconButton(
                          onPressed: canPop
                              ? () => Navigator.maybePop(context)
                              : onAdd,
                          tooltip: canPop ? 'Назад' : addLabel ?? 'Добавить',
                          icon: Icon(
                            canPop ? Icons.chevron_left : Icons.add,
                            size: 24,
                          ),
                          style: IconButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            backgroundColor: context
                                .color(PharmacyColor.glass)
                                .withValues(alpha: .61),
                            foregroundColor: scheme.primary,
                            side: BorderSide(
                              color: context.buttonOutline.withValues(
                                alpha: .70,
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      ?trailing,
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final bottomBar = navigation == null && footer == null
        ? null
        : PharmacyDock(child: navigation ?? footer!);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (context.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
              ),
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-.9, -1.05),
              radius: 1.3,
              colors: [
                context.color(PharmacyColor.raised).withValues(alpha: .72),
                context.color(PharmacyColor.background),
                context.dark
                    ? context.color(PharmacyColor.shade)
                    : context.color(PharmacyColor.background),
              ],
              stops: const [0, .55, 1],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: footer != null && navigation == null
                ? Column(
                    children: [
                      Expanded(child: scrollView),
                      bottomBar!,
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [scrollView, if (navigation != null) bottomBar!],
                  ),
          ),
        ),
      ),
    );
  }
}

class Intro extends StatelessWidget {
  const Intro(this.kicker, this.title, this.subtitle, {super.key});

  final String kicker;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ink = context.color(PharmacyColor.ink);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (kicker.isNotEmpty) ...[
            Text(
              kicker.toUpperCase(),
              style: TextStyle(
                color: context.color(PharmacyColor.coral),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.25,
              ),
            ),
            const SizedBox(height: 9),
          ],
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                color: ink,
                fontSize: 40,
                height: .98,
                fontWeight: FontWeight.w700,
                letterSpacing: -.95,
              ),
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 15),
            Text(
              subtitle,
              style: TextStyle(
                color: context.color(PharmacyColor.secondary),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 9),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 23,
                height: 1.08,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.padding = const EdgeInsets.all(15),
    this.radius = 20,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Material(
    color: color ?? context.color(PharmacyColor.card),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(
        color: onTap == null
            ? context.color(PharmacyColor.border)
            : context.buttonOutline,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class PharmacyRow extends StatelessWidget {
  const PharmacyRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Panel(
    onTap: onTap,
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: context.color(PharmacyColor.raised),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 21,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.color(PharmacyColor.secondary),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ] else if (onTap != null)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.chevron_right, size: 20),
          ),
      ],
    ),
  );
}

class PharmacyDock extends StatelessWidget {
  const PharmacyDock({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: child,
      ),
    ),
  );
}

class PrimaryAction extends StatelessWidget {
  const PrimaryAction(this.label, {super.key, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
        backgroundColor: context
            .color(PharmacyColor.raised)
            .withValues(alpha: .73),
        foregroundColor: context.color(PharmacyColor.ink),
        disabledBackgroundColor: context
            .color(PharmacyColor.raised)
            .withValues(alpha: .32),
        side: BorderSide(color: context.buttonOutline.withValues(alpha: .80)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
  );
}
