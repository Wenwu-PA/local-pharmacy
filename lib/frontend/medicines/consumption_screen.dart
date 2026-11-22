import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shared/palette.dart';
import '../shared/pharmacy_state.dart';
import '../shared/screen.dart';

class ConsumptionScreen extends StatefulWidget {
  const ConsumptionScreen({super.key, required this.medicine});

  final Medicine medicine;

  @override
  State<ConsumptionScreen> createState() => _ConsumptionScreenState();
}

class _ConsumptionScreenState extends State<ConsumptionScreen> {
  late final TextEditingController _amount;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: quantity(math.min(1.0, widget.medicine.remaining)),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _change(double value) {
    final next = value.clamp(0.0, widget.medicine.remaining).toDouble();
    setState(() {
      _amount.text = quantity(next);
      _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
    });
  }

  void _confirm(double amount) {
    if (!PharmacyScope.read(context).consume(widget.medicine, amount)) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(content: Text('Расход отмечен')));
  }

  @override
  Widget build(BuildContext context) {
    PharmacyScope.of(context);
    final medicine = widget.medicine;
    final amount = parseQuantity(_amount.text);
    final valid = amount != null && amount > 0 && amount <= medicine.remaining;
    final numeric = amount ?? 0;
    return PharmacyScreen(
      footer: PrimaryAction(
        'Подтвердить расход',
        onPressed: valid ? () => _confirm(numeric) : null,
      ),
      children: [
        const Intro('', 'Отметить\nиспользование.', ''),
        PharmacyRow(
          icon: Icons.medication_outlined,
          title: medicine.name,
          subtitle:
              'Сейчас осталось ${quantity(medicine.remaining)} ${medicine.unit}',
        ),
        const SectionHeading('Сколько использовано?'),
        Panel(
          color: context.color(PharmacyColor.glass),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Уменьшить расход',
                onPressed: numeric > 0 ? () => _change(numeric - 1) : null,
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: TextField(
                  controller: _amount,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Количество, ${medicine.unit}',
                    border: InputBorder.none,
                    filled: false,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: 'Увеличить расход',
                onPressed: numeric < medicine.remaining
                    ? () => _change(numeric + 1)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          color: context.color(PharmacyColor.raised),
          child: valid
              ? Text(
                  'После списания останется ${quantity(medicine.remaining - numeric)} ${medicine.unit}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )
              : const Text(
                  'Введите количество больше нуля в пределах остатка.',
                ),
        ),
      ],
    );
  }
}
