import 'package:flutter/material.dart';

import '../schedule/schedule_screen.dart';
import '../shared/palette.dart';
import '../shared/pharmacy_state.dart';
import '../shared/screen.dart';
import 'consumption_screen.dart';

class MedicineDetailScreen extends StatelessWidget {
  const MedicineDetailScreen({super.key, required this.medicine});

  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    PharmacyScope.of(context);
    final dates = MaterialLocalizations.of(context);
    final plan = medicine.plan;
    final low = medicine.remaining <= medicine.pack / 2;
    return PharmacyScreen(
      footer: PrimaryAction(
        'Отметить расход',
        onPressed: medicine.remaining <= 0
            ? null
            : () => openScreen(context, ConsumptionScreen(medicine: medicine)),
      ),
      children: [
        Intro(
          '',
          medicine.name,
          medicine.ingredient.isEmpty
              ? ''
              : 'Действующее вещество: ${medicine.ingredient}',
        ),
        Panel(
          padding: const EdgeInsets.all(18),
          radius: 26,
          color: context.color(PharmacyColor.glass),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ОСТАТОК В УПАКОВКЕ',
                      style: TextStyle(
                        fontSize: 10,
                        color: context.color(PharmacyColor.secondary),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      quantity(medicine.remaining),
                      style: const TextStyle(
                        fontSize: 62,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'из ${quantity(medicine.pack)} ${medicine.unit}',
                      style: TextStyle(
                        color: context.color(PharmacyColor.secondary),
                      ),
                    ),
                    if (low) ...[
                      const SizedBox(height: 12),
                      Text(
                        medicine.remaining == 0
                            ? 'Запас закончился'
                            : 'Осталось половина или меньше',
                        style: TextStyle(
                          color: context.color(PharmacyColor.coral),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 40,
                backgroundColor: context.color(PharmacyColor.raised),
                foregroundColor: Theme.of(context).colorScheme.primary,
                child: const Icon(Icons.medication_outlined, size: 36),
              ),
            ],
          ),
        ),
        const SectionHeading('Информация о препарате'),
        Panel(
          child: Column(
            spacing: 12,
            children: [
              _Info('Категория', medicine.category),
              if (medicine.form.isNotEmpty) _Info('Форма', medicine.form),
              _Info(
                'Дата покупки',
                dates.formatCompactDate(medicine.purchased),
              ),
              _Info('Срок годности', dates.formatCompactDate(medicine.expires)),
              _Info('Хранится', medicine.place.name),
            ],
          ),
        ),
        const SizedBox(height: 11),
        PharmacyRow(
          icon: Icons.schedule,
          title: 'План приёма',
          subtitle: plan == null
              ? 'Нерегулярный приём'
              : '${plan.amount} ${plan.unit} · ${plan.times.map((time) => time.format(context)).join(', ')}',
          onTap: () => openScreen(context, ScheduleScreen(medicine: medicine)),
        ),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(color: context.color(PharmacyColor.secondary)),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}
