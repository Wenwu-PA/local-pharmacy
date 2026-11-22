import 'package:flutter/material.dart';

import '../shared/palette.dart';
import '../shared/pharmacy_state.dart';
import '../shared/screen.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, required this.medicine, this.isNew = false});

  final Medicine medicine;
  final bool isNew;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  static const _custom = 'Другое';
  static const _presets = <String, List<TimeOfDay>>{
    'Утром и вечером': [
      TimeOfDay(hour: 8, minute: 0),
      TimeOfDay(hour: 20, minute: 0),
    ],
    'Утром и днём': [
      TimeOfDay(hour: 8, minute: 0),
      TimeOfDay(hour: 14, minute: 0),
    ],
    'Днём и вечером': [
      TimeOfDay(hour: 14, minute: 0),
      TimeOfDay(hour: 20, minute: 0),
    ],
    'За 30 минут до еды': [],
    'Через 30 минут после еды': [],
    _custom: [],
  };

  final _form = GlobalKey<FormState>();
  late final TextEditingController _notes;
  late final bool _hasExistingPlan;
  bool _regular = false;
  int _amount = 1;
  int _frequency = 1;
  late String _unit;
  String _when = _custom;
  List<TimeOfDay?> _times = [null];
  String? _timeError;

  @override
  void initState() {
    super.initState();
    final plan = widget.medicine.plan;
    _hasExistingPlan = plan != null;
    _regular = _hasExistingPlan;
    _unit = plan?.unit ?? widget.medicine.unit;
    _amount = plan?.amount ?? _amount;
    _frequency = plan?.frequency ?? _frequency;
    _when = plan != null && _presets.containsKey(plan.when)
        ? plan.when
        : _custom;
    _times = plan?.times.toList() ?? _times;
    _notes = TextEditingController(
      text: _when == _custom && _hasExistingPlan ? plan!.when : '',
    );
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _selectFrequency(int value) {
    _frequency = value;
    _times = List.generate(
      value,
      (index) => index < _times.length ? _times[index] : null,
    );
    _timeError = null;
    if (_presets[_when]!.isNotEmpty && value != 2) _when = _custom;
  }

  void _selectPreset(String value) {
    _when = value;
    _timeError = null;
    final preset = _presets[value]!;
    if (preset.isNotEmpty) {
      _frequency = preset.length;
      _times = [...preset];
    }
  }

  Future<void> _pickTime(int index) async {
    final time = await showTimePicker(
      context: context,
      initialTime: _times[index] ?? TimeOfDay.now(),
    );
    if (!mounted || time == null || index >= _times.length) return;
    setState(() {
      _times[index] = time;
      _timeError = null;
    });
  }

  void _save() {
    IntakePlan? plan;
    if (_regular) {
      final valid = _form.currentState!.validate();
      final times = _times.whereType<TimeOfDay>().toList();
      final unique = times.map((time) => time.hour * 60 + time.minute).toSet();
      final error = times.length != _frequency
          ? 'Укажите время каждого приёма'
          : unique.length != times.length
          ? 'Время приёмов должно различаться'
          : null;
      setState(() => _timeError = error);
      if (!valid || error != null) return;
      final when = _when == _custom ? _notes.text.trim() : _when;
      plan = IntakePlan(
        _amount,
        _unit,
        _frequency,
        when.isEmpty ? _custom : when,
        times,
      );
    }
    PharmacyScope.read(context).saveMedicine(widget.medicine, plan);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final doseUnits = {...units, widget.medicine.unit};
    return PharmacyScreen(
      footer: PrimaryAction(
        widget.isNew ? 'Сохранить препарат' : 'Сохранить план',
        onPressed: _save,
      ),
      children: [
        const Intro(
          '',
          'План приёма.',
          'Укажите свой режим и время напоминаний.',
        ),
        const SectionHeading('Режим использования'),
        Panel(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            title: const Text('Регулярный приём'),
            subtitle: Text(
              _regular
                  ? 'Приём по расписанию'
                  : 'Нерегулярный приём с ручным учётом',
            ),
            value: _regular,
            onChanged: (value) => setState(() {
              _regular = value;
              _timeError = null;
            }),
          ),
        ),
        if (_regular) ...[
          const SizedBox(height: 10),
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _countField(
                        'За один приём',
                        _amount,
                        (value) => setState(() => _amount = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _unit,
                        decoration: const InputDecoration(labelText: 'Единица'),
                        isExpanded: true,
                        items: [
                          for (final unit in doseUnits)
                            DropdownMenuItem(value: unit, child: Text(unit)),
                        ],
                        onChanged: (value) => setState(() => _unit = value!),
                      ),
                    ),
                  ],
                ),
                _countField(
                  'Приёмов в день',
                  _frequency,
                  (value) => setState(() => _selectFrequency(value)),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(_when),
                  initialValue: _when,
                  decoration: const InputDecoration(labelText: 'Когда'),
                  isExpanded: true,
                  items: [
                    for (final preset in _presets.keys)
                      DropdownMenuItem(
                        value: preset,
                        child: Text(
                          preset,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _selectPreset(value!)),
                ),
                if (_when == _custom)
                  TextFormField(
                    controller: _notes,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Пояснение',
                      counterText: '',
                    ),
                  ),
                for (var index = 0; index < _times.length; index++)
                  PharmacyRow(
                    icon: Icons.schedule,
                    title: 'Приём ${index + 1}',
                    subtitle: _times[index]?.format(context) ?? 'Указать время',
                    onTap: () => _pickTime(index),
                  ),
                if (_timeError != null)
                  Text(
                    _timeError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Panel(
                  color: context.color(PharmacyColor.raised),
                  child: Text(
                    'На день по плану: ${_amount * _frequency} $_unit',
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _countField(String label, int selected, ValueChanged<int> onChanged) =>
      DropdownButtonFormField<int>(
        key: ValueKey((label, selected)),
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (var value = 1; value <= 10; value++)
            DropdownMenuItem(value: value, child: Text('$value')),
        ],
        onChanged: (value) => onChanged(value!),
      );
}
