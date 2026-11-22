import 'package:flutter/material.dart';

import '../shared/palette.dart';
import '../shared/pharmacy_state.dart';
import '../shared/screen.dart';

class LocationsScreen extends StatelessWidget {
  const LocationsScreen({
    super.key,
    required this.onAdd,
    required this.onLocation,
  });

  final VoidCallback onAdd;
  final ValueChanged<StoragePlace> onLocation;

  @override
  Widget build(BuildContext context) {
    final state = PharmacyScope.of(context);
    final places = state.places;
    String count(StoragePlace place) =>
        'Препаратов: ${state.medicines.where((item) => item.place == place).length}';

    return PharmacyScreen(
      reserveNavigationSpace: true,
      onAdd: onAdd,
      addLabel: 'Добавить место',
      trailing: const Icon(Icons.medication_outlined),
      children: [
        const Intro('', 'Аптека', ''),
        SectionHeading(
          'Места хранения',
          action: TextButton(onPressed: onAdd, child: const Text('+ Добавить')),
        ),
        if (places.length >= 2)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _LocationTile(
                  places[0],
                  count(places[0]),
                  () => onLocation(places[0]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LocationTile(
                  places[1],
                  count(places[1]),
                  () => onLocation(places[1]),
                ),
              ),
            ],
          ),
        for (final place in places.skip(places.length >= 2 ? 2 : 0)) ...[
          const SizedBox(height: 12),
          PharmacyRow(
            icon: place.icon,
            title: place.name,
            subtitle: count(place),
            onTap: () => onLocation(place),
          ),
        ],
      ],
    );
  }
}

class _LocationTile extends StatelessWidget {
  const _LocationTile(this.place, this.subtitle, this.onTap);

  final StoragePlace place;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Panel(
    onTap: onTap,
    child: SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            place.icon,
            color: Theme.of(context).colorScheme.primary,
            size: 28,
          ),
          const SizedBox(height: 12),
          Text(
            place.name,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: context.color(PharmacyColor.secondary),
            ),
          ),
        ],
      ),
    ),
  );
}

class AddLocationScreen extends StatefulWidget {
  const AddLocationScreen({super.key});

  @override
  State<AddLocationScreen> createState() => _AddLocationScreenState();
}

class _AddLocationScreenState extends State<AddLocationScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(text: StorageKind.home.label);
  StorageKind _kind = StorageKind.home;

  void _selectKind(StorageKind kind) {
    if (_name.text.isEmpty || _name.text == _kind.label) {
      _name.text = kind.label;
      _name.selection = TextSelection.collapsed(offset: _name.text.length);
    }
    setState(() => _kind = kind);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final place = StoragePlace(_name.text.trim(), _kind);
    PharmacyScope.read(context).addPlace(place);
    Navigator.pop(context, place);
  }

  @override
  Widget build(BuildContext context) => PharmacyScreen(
    footer: PrimaryAction('Создать место', onPressed: _submit),
    children: [
      const Intro('', 'Где хранятся\nлекарства?', ''),
      for (var first = 0; first < StorageKind.values.length; first += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              for (final kind in StorageKind.values.skip(first).take(2)) ...[
                if (kind != StorageKind.values[first])
                  const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    selected: _kind == kind,
                    button: true,
                    child: Panel(
                      onTap: () => _selectKind(kind),
                      radius: 18,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 15,
                      ),
                      color: context
                          .color(
                            _kind == kind
                                ? PharmacyColor.raised
                                : PharmacyColor.glass,
                          )
                          .withValues(alpha: _kind == kind ? .85 : .55),
                      child: Row(
                        children: [
                          Icon(kind.icon, size: 22),
                          const SizedBox(width: 9),
                          Expanded(child: Text(kind.label)),
                          if (kind == _kind) const Icon(Icons.check, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      const SizedBox(height: 10),
      Form(
        key: _form,
        child: TextFormField(
          controller: _name,
          maxLength: 48,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          decoration: const InputDecoration(labelText: 'Название места'),
          validator: (value) {
            final name = value?.trim() ?? '';
            if (name.isEmpty) return 'Введите название места';
            final exists = PharmacyScope.read(context).places.any(
              (place) => place.name.toLowerCase() == name.toLowerCase(),
            );
            return exists ? 'Такое место уже есть' : null;
          },
        ),
      ),
    ],
  );
}
