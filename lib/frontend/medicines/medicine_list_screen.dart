import 'package:flutter/material.dart';

import '../shared/palette.dart';
import '../shared/pharmacy_state.dart';
import '../shared/screen.dart';
import 'add_medicine_screen.dart';
import 'medicine_detail_screen.dart';

enum _MedicineFilter { all, regular, expiring }

class MedicineListScreen extends StatefulWidget {
  const MedicineListScreen({
    super.key,
    required this.place,
    required this.navigation,
  });

  final StoragePlace place;
  final Widget navigation;

  @override
  State<MedicineListScreen> createState() => _MedicineListScreenState();
}

class _MedicineListScreenState extends State<MedicineListScreen> {
  _MedicineFilter _filter = _MedicineFilter.all;

  void _add() => openScreen(context, AddMedicineScreen(place: widget.place));

  @override
  Widget build(BuildContext context) {
    final state = PharmacyScope.of(context);
    final medicines = state.medicines
        .where((item) => item.place == widget.place)
        .toList();
    final filtered = medicines
        .where(
          (item) => switch (_filter) {
            _MedicineFilter.all => true,
            _MedicineFilter.regular => item.plan != null,
            _MedicineFilter.expiring => item.expiring,
          },
        )
        .toList();

    const labels = {
      _MedicineFilter.all: 'Все',
      _MedicineFilter.regular: 'Регулярные',
      _MedicineFilter.expiring: 'Истекают',
    };

    return PharmacyScreen(
      navigation: widget.navigation,
      trailing: Icon(widget.place.icon),
      children: [
        Intro(
          'Место хранения',
          widget.place.name,
          'Препаратов: ${medicines.length}',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final entry in labels.entries)
              ChoiceChip(
                label: Text(entry.value),
                showCheckmark: false,
                selected: _filter == entry.key,
                onSelected: (_) => setState(() => _filter = entry.key),
              ),
          ],
        ),
        SectionHeading(
          'Лекарства',
          action: TextButton(onPressed: _add, child: const Text('+ Добавить')),
        ),
        if (filtered.isEmpty)
          Panel(
            child: Text(
              medicines.isEmpty
                  ? 'Добавьте первое лекарство в это место.'
                  : 'В этой подборке пока пусто.',
            ),
          ),
        for (final medicine in filtered) ...[
          PharmacyRow(
            icon: Icons.medication_outlined,
            title: medicine.name,
            subtitle: medicine.form.isEmpty && medicine.ingredient.isEmpty
                ? null
                : [
                    medicine.form,
                    medicine.ingredient,
                  ].where((value) => value.isNotEmpty).join(' · '),
            trailing: Text(
              '${quantity(medicine.remaining)} ${medicine.unit}',
              style: TextStyle(
                color:
                    (medicine.remaining <= medicine.pack / 2 ||
                        medicine.expiring)
                    ? context.color(PharmacyColor.coral)
                    : Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () =>
                openScreen(context, MedicineDetailScreen(medicine: medicine)),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
