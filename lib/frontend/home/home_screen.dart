import 'package:flutter/material.dart';

import '../shared/palette.dart';
import '../shared/pharmacy_state.dart';
import '../shared/screen.dart';
import 'interactive_capsule.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onAdd,
    required this.onNotifications,
    required this.onBasket,
    required this.onLocation,
  });

  final VoidCallback onAdd;
  final VoidCallback onNotifications;
  final VoidCallback onBasket;
  final ValueChanged<StoragePlace> onLocation;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = PharmacyScope.of(context);
    final expiring = state.medicines
        .where((medicine) => medicine.expiring)
        .length;
    final shopping = state.shopping.where((item) => !item.bought).length;
    return PharmacyScreen(
      controller: _scroll,
      minimumScrollExtent: 168,
      reserveNavigationSpace: true,
      onAdd: widget.onAdd,
      addLabel: 'Добавить место',
      trailing: IconButton.outlined(
        tooltip: 'Уведомления',
        style: IconButton.styleFrom(
          backgroundColor: context
              .color(PharmacyColor.glass)
              .withValues(alpha: .57),
          side: BorderSide(color: context.buttonOutline.withValues(alpha: .70)),
        ),
        onPressed: widget.onNotifications,
        icon: Badge(
          isLabelVisible: state.reminders.any((item) => !item.read),
          child: const Icon(Icons.notifications_none_outlined, size: 21),
        ),
      ),
      children: [
        const Intro('', 'Забота всегда\nпод рукой.', ''),
        InteractiveCapsule(scroll: _scroll, useSensors: state.tilt),
        const SectionHeading('Сегодня важно'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Metric('Срок истекает', expiring, widget.onNotifications),
            ),
            const SizedBox(width: 12),
            Expanded(child: _Metric('К покупке', shopping, widget.onBasket)),
          ],
        ),
        if (state.places.isNotEmpty) const SectionHeading('Места хранения'),
        for (final place in state.places) ...[
          PharmacyRow(
            icon: place.icon,
            title: place.name,
            onTap: () => widget.onLocation(place),
          ),
          const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.title, this.value, this.onTap);

  final String title;
  final int value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Panel(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: context.color(PharmacyColor.secondary),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value.toString().padLeft(2, '0'),
          style: const TextStyle(
            fontSize: 33,
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
