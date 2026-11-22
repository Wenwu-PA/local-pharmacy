import 'package:flutter/material.dart';

import '../schedule/schedule_screen.dart';
import '../shared/pharmacy_state.dart';
import '../shared/screen.dart';

class AddMedicineScreen extends StatefulWidget {
  const AddMedicineScreen({super.key, required this.place});

  final StoragePlace place;

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _ingredient = TextEditingController();
  final _formName = TextEditingController();
  final _pack = TextEditingController();
  final _remaining = TextEditingController();
  String _category = categories.first;
  String _unit = units.first;
  DateTime _purchase = DateUtils.dateOnly(DateTime.now());
  DateTime? _expiry;
  bool _showExpiryError = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _ingredient,
      _formName,
      _pack,
      _remaining,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate({required bool expiry}) async {
    final now = DateUtils.dateOnly(DateTime.now());
    final lastExpiry = DateTime(now.year + 30, 12, 31);
    final value = await showDatePicker(
      context: context,
      initialDate: expiry ? _expiry ?? _purchase : _purchase,
      firstDate: expiry ? _purchase : DateTime(1900),
      lastDate: expiry
          ? lastExpiry
          : (_expiry != null && _expiry!.isBefore(now) ? _expiry! : now),
      helpText: expiry ? 'Срок годности' : 'Дата покупки',
    );
    if (!mounted || value == null) return;
    setState(() {
      if (expiry) {
        _expiry = value;
        _showExpiryError = false;
      } else {
        _purchase = value;
      }
    });
  }

  Future<void> _next() async {
    final valid = _form.currentState!.validate();
    setState(() => _showExpiryError = _expiry == null);
    if (!valid || _expiry == null) return;

    final pack = parseQuantity(_pack.text)!;
    final medicine = Medicine(
      place: widget.place,
      name: _name.text.trim(),
      ingredient: _ingredient.text.trim(),
      category: _category,
      form: _formName.text.trim(),
      unit: _unit,
      pack: pack,
      remaining: parseQuantity(_remaining.text) ?? pack,
      purchased: _purchase,
      expires: _expiry!,
    );
    FocusScope.of(context).unfocus();
    final saved = await openScreen<bool>(
      context,
      ScheduleScreen(medicine: medicine, isNew: true),
    );
    if (mounted && saved == true) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final dates = MaterialLocalizations.of(context);
    return PharmacyScreen(
      footer: PrimaryAction('Продолжить', onPressed: _next),
      children: [
        const Intro('', 'Добавить\nлекарство.', ''),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              TextFormField(
                controller: _name,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  counterText: '',
                ),
                validator: (value) => value?.trim().isNotEmpty == true
                    ? null
                    : 'Введите название',
              ),
              TextFormField(
                controller: _ingredient,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Действующее вещество',
                  counterText: '',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Категория',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
                items: [
                  for (final category in categories)
                    DropdownMenuItem(
                      value: category,
                      child: Text(
                        category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _category = value!),
              ),
              TextFormField(
                controller: _formName,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Форма',
                  counterText: '',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: _unit,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Единица измерения',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
                items: [
                  for (final unit in units)
                    DropdownMenuItem(value: unit, child: Text(unit)),
                ],
                onChanged: (value) => setState(() => _unit = value!),
              ),
              TextFormField(
                controller: _pack,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Количество в упаковке',
                ),
                validator: (value) => (parseQuantity(value) ?? 0) > 0
                    ? null
                    : 'Введите количество больше нуля',
              ),
              TextFormField(
                controller: _remaining,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Остаток',
                  hintText: 'По умолчанию — полная упаковка',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final remaining = parseQuantity(value);
                  final pack = parseQuantity(_pack.text);
                  if (remaining == null || remaining < 0) {
                    return 'Введите корректный остаток';
                  }
                  return pack != null && remaining > pack
                      ? 'Остаток больше упаковки'
                      : null;
                },
              ),
              PharmacyRow(
                icon: Icons.calendar_today_outlined,
                title: 'Дата покупки',
                subtitle: dates.formatCompactDate(_purchase),
                onTap: () => _pickDate(expiry: false),
              ),
              PharmacyRow(
                icon: Icons.event_outlined,
                title: 'Срок годности',
                subtitle: _expiry == null
                    ? 'Выбрать дату'
                    : dates.formatCompactDate(_expiry!),
                onTap: () => _pickDate(expiry: true),
              ),
              if (_showExpiryError)
                Text(
                  'Укажите срок годности',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
