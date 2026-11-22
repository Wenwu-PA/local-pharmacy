import 'package:flutter/material.dart';

import '../shared/palette.dart';
import '../shared/pharmacy_state.dart';
import '../shared/screen.dart';

class BasketScreen extends StatelessWidget {
  const BasketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = PharmacyScope.of(context);
    final pending = state.shopping.where((item) => !item.bought);
    final completed = state.shopping.where((item) => item.bought);

    return PharmacyScreen(
      reserveNavigationSpace: true,
      trailing: const Icon(Icons.shopping_basket_outlined),
      children: [
        const Intro('', 'Нужно\nдокупить.', ''),
        Panel(
          color: context.color(PharmacyColor.glass),
          radius: 26,
          child: Row(
            children: [
              Text(
                pending.length.toString().padLeft(2, '0'),
                style: const TextStyle(
                  fontSize: 54,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  'Позиций к покупке',
                  style: TextStyle(
                    color: context.color(PharmacyColor.secondary),
                  ),
                ),
              ),
              const Icon(Icons.shopping_basket_outlined, size: 30),
            ],
          ),
        ),
        if (pending.isNotEmpty) const SectionHeading('Лекарства'),
        for (final item in pending) ...[
          _ShoppingRow(item),
          const SizedBox(height: 10),
        ],
        if (completed.isNotEmpty) ...[
          const SectionHeading('Куплено'),
          for (final item in completed) ...[
            _ShoppingRow(item),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _ShoppingRow extends StatelessWidget {
  const _ShoppingRow(this.item);

  final ShoppingItem item;

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: CheckboxListTile(
      value: item.bought,
      onChanged: (_) => PharmacyScope.read(context).toggleBought(item),
      title: Text(
        item.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text('${item.reason} · ${item.amount}'),
      secondary: const Icon(Icons.medication_outlined),
    ),
  );
}
