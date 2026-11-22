import 'dart:async';

import 'package:flutter/material.dart';

import '../../backend/notifications/android_reminders.dart';
import '../../backend/storage/pharmacy_database.dart';

const units = ['таб.', 'мл', 'мг', 'МЕ', 'амп.'];
const categories = [
  'Обезболивающее',
  'Витамины',
  'От кашля',
  'Антисептик',
  'Другое',
];

enum StorageKind {
  home('Дом', Icons.home_outlined),
  car('Машина', Icons.directions_car_outlined),
  work('Работа', Icons.work_outline),
  bag('Сумка', Icons.shopping_bag_outlined);

  const StorageKind(this.label, this.icon);

  final String label;
  final IconData icon;

  static StorageKind fromName(String name) {
    final lower = name.toLowerCase();
    if (RegExp('машин|авто|бардач').hasMatch(lower)) return car;
    if (RegExp('работ|офис').hasMatch(lower)) return work;
    if (RegExp('сумк|рюкзак|портфел').hasMatch(lower)) return bag;
    return home;
  }
}

class StoragePlace {
  StoragePlace(this.name, this.kind);

  final String name;
  final StorageKind kind;

  IconData get icon => kind.icon;
}

class IntakePlan {
  IntakePlan(this.amount, this.unit, this.frequency, this.when, this.times);

  final int amount;
  final String unit;
  final int frequency;
  final String when;
  final List<TimeOfDay> times;
}

class Medicine {
  Medicine({
    required this.place,
    required this.name,
    required this.ingredient,
    required this.category,
    required this.form,
    required this.unit,
    required this.pack,
    required this.remaining,
    required this.purchased,
    required this.expires,
    this.plan,
    DateTime? lastActivity,
  }) : lastActivity = lastActivity ?? DateTime.now();

  final StoragePlace place;
  final String name;
  final String ingredient;
  final String category;
  final String form;
  final String unit;
  final double pack;
  final DateTime purchased;
  final DateTime expires;
  double remaining;
  IntakePlan? plan;
  DateTime lastActivity;

  bool get expiring => !expires.isAfter(
    DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 14)),
  );
}

String quantity(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0$'), '')
          .replaceAll('.', ',');

double? parseQuantity(String? value) {
  final input = value?.trim() ?? '';
  if (!RegExp(r'^\d{1,7}([.,]\d{1,2})?$').hasMatch(input)) return null;
  final parsed = double.parse(input.replaceAll(',', '.'));
  if (parsed > 1000000) return null;
  return parsed;
}

class ShoppingItem {
  ShoppingItem(this.name, this.reason, this.amount, {required this.medicine});

  final String name;
  final String reason;
  final String amount;
  final Medicine medicine;
  bool bought = false;
}

enum ReminderKind { expiry, restock, review }

class PharmacyReminder {
  const PharmacyReminder(
    this.id,
    this.title,
    this.body,
    this.kind,
    this.when,
    this.read,
  );

  final String id;
  final String title;
  final String body;
  final ReminderKind kind;
  final DateTime when;
  final bool read;
}

class PharmacyState extends ChangeNotifier {
  PharmacyState({
    PharmacyDatabase? database,
    AndroidReminders? system,
    Map<String, dynamic>? snapshot,
  }) : _database = database,
       _system = system {
    if (snapshot != null) _restore(snapshot);
  }

  final PharmacyDatabase? _database;
  final AndroidReminders? _system;
  final places = <StoragePlace>[];
  final medicines = <Medicine>[];
  final shopping = <ShoppingItem>[];
  final _read = <String>{};
  Future<void> _updates = Future.value();
  ThemeMode theme = ThemeMode.system;
  bool tilt = true;
  bool remindersEnabled = false;
  bool permissionDenied = false;
  bool saveFailed = false;
  bool _requesting = false;
  bool _disposed = false;
  int _libraryRevision = 0;

  Iterable<PharmacyReminder> get reminders {
    final now = DateTime.now();
    return _datedReminders.where((item) => !item.when.isAfter(now)).toList()
      ..sort((a, b) => b.when.compareTo(a.when));
  }

  Iterable<PharmacyReminder> get _datedReminders sync* {
    final pending = shopping
        .where((item) => !item.bought)
        .map((item) => item.medicine)
        .toSet();
    for (final (id, medicine) in medicines.indexed) {
      final expiry = medicine.expires;
      final due = DateTime(expiry.year, expiry.month, expiry.day - 14, 9);
      final expiryId = 'expiry:$id:${expiry.toIso8601String()}';
      yield PharmacyReminder(
        expiryId,
        'Проверьте срок годности',
        medicine.name,
        ReminderKind.expiry,
        due,
        _read.contains(expiryId),
      );

      final last = medicine.lastActivity;
      final check = DateTime(last.year, last.month, last.day + 30, 9);
      final reviewId = 'review:$id:${last.toIso8601String()}';
      if (medicine.remaining > 0 && check.isBefore(expiry)) {
        yield PharmacyReminder(
          reviewId,
          'Проверьте остаток',
          medicine.name,
          ReminderKind.review,
          check,
          _read.contains(reviewId),
        );
      }
      final stockId = 'restock:$id';
      if (medicine.plan != null && pending.contains(medicine)) {
        yield PharmacyReminder(
          stockId,
          'Пора пополнить запас',
          medicine.name,
          ReminderKind.restock,
          last,
          _read.contains(stockId),
        );
      }
    }
  }

  List<Map<String, Object>> _events() {
    final now = DateTime.now();
    final events = <Map<String, Object>>[
      for (final reminder in _datedReminders)
        if (reminder.kind != ReminderKind.restock)
          {
            'id': reminder.id,
            'title': reminder.title,
            'body': reminder.body,
            'due': reminder.when.millisecondsSinceEpoch,
          },
      for (final item in shopping)
        {
          'id': 'restock:${medicines.indexOf(item.medicine)}',
          'title': 'Пора пополнить запас',
          'body': item.name,
          'due': item.medicine.lastActivity.millisecondsSinceEpoch,
          'muted': item.bought || item.medicine.plan == null,
        },
      for (final (id, medicine) in medicines.indexed)
        if (medicine.plan case final IntakePlan plan
            when medicine.remaining > 0 &&
                medicine.expires.isAfter(DateUtils.dateOnly(now)))
          for (final time in plan.times)
            {
              'id': 'intake:$id:${time.hour}:${time.minute}',
              'title': 'Напоминание о приёме',
              'body': '${medicine.name} · ${plan.amount} ${plan.unit}',
              'hour': time.hour,
              'minute': time.minute,
              'until': medicine.expires.millisecondsSinceEpoch,
            },
    ];
    if (_libraryRevision != 0) {
      for (final event in events) {
        event['id'] = '$_libraryRevision.${event['id']}';
      }
    }
    return events;
  }

  void addPlace(StoragePlace place) {
    places.add(place);
    _commit();
  }

  void saveMedicine(Medicine medicine, IntakePlan? plan) {
    medicine.plan = plan;
    if (!medicines.contains(medicine)) medicines.add(medicine);
    _checkStock(medicine);
    _commit();
  }

  void _checkStock(Medicine medicine) {
    if (medicine.plan == null || medicine.remaining > medicine.pack / 2) return;
    if (shopping.any((item) => item.medicine == medicine)) return;
    shopping.add(
      ShoppingItem(
        medicine.name,
        'Осталась половина упаковки или меньше',
        '1 уп.',
        medicine: medicine,
      ),
    );
  }

  bool consume(Medicine medicine, double amount) {
    if (!amount.isFinite || amount <= 0 || amount > medicine.remaining) {
      return false;
    }
    medicine.remaining = double.parse(
      (medicine.remaining - amount).toStringAsFixed(2),
    );
    medicine.lastActivity = DateTime.now();
    _checkStock(medicine);
    _commit();
    return true;
  }

  void toggleBought(ShoppingItem item) {
    item.bought = !item.bought;
    _commit();
  }

  void markRead(PharmacyReminder reminder) {
    _read.add(reminder.id);
    _commit();
  }

  void setTheme(ThemeMode value) {
    theme = value;
    _commit();
  }

  void setTilt(bool value) {
    tilt = value;
    _commit();
  }

  Future<void> setReminders(bool value) async {
    if (_requesting) return;
    if (value && _system != null) {
      _requesting = true;
      try {
        if (!await _system.requestPermission()) {
          if (!_disposed) {
            permissionDenied = true;
            notifyListeners();
          }
          return;
        }
      } finally {
        _requesting = false;
      }
    }
    if (_disposed) return;
    permissionDenied = false;
    remindersEnabled = value;
    _commit();
  }

  Future<void> openNotificationSettings() async {
    await _system?.openSettings();
  }

  void refresh() => _commit(save: false);

  void retrySave() => _commit();

  void _commit({bool save = true}) {
    notifyListeners();
    if (_database == null && _system == null) return;
    final snapshot = save ? _snapshot() : null;
    _enqueue(() async {
      if (snapshot != null) await _save(snapshot);
      await _updateReminders();
    }).ignore();
  }

  Future<void> _enqueue(
    Future<void> Function() work, {
    bool reportFailure = true,
  }) {
    final operation = _updates.then((_) => work());
    _updates = operation.catchError((Object error, StackTrace stack) {
      if (reportFailure) _reportStorageError(error, stack);
    });
    return operation;
  }

  Future<void> _save(Map<String, dynamic> snapshot) async {
    try {
      await _database?.save(snapshot);
      _setSaveFailure(false);
    } catch (_) {
      _setSaveFailure(true);
      rethrow;
    }
  }

  void _setSaveFailure(bool failed) {
    if (saveFailed == failed) return;
    saveFailed = failed;
    if (!_disposed) notifyListeners();
  }

  void _reportStorageError(Object _, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError('Protected pharmacy storage operation failed'),
        stack: stack,
        library: 'local_pharmacy',
      ),
    );
  }

  Future<void> _updateReminders() async {
    try {
      await _system?.replace(remindersEnabled, _events());
    } catch (error, stack) {
      _reportStorageError(error, stack);
    }
  }

  Future<void> replaceLibrary(Map<String, dynamic> library) =>
      _enqueue(() async {
        final candidate = PharmacyState(
          snapshot: {
            'places': library['places'],
            'medicines': library['medicines'],
            'shopping': library['shopping'],
            'read': library['read'],
            'theme': theme.index,
            'tilt': tilt,
            'reminders': remindersEnabled,
            'libraryRevision': _libraryRevision + 1,
          },
        );
        try {
          candidate._validateLibrary();
          await _save(candidate._snapshot());
          places
            ..clear()
            ..addAll(candidate.places);
          medicines
            ..clear()
            ..addAll(candidate.medicines);
          shopping
            ..clear()
            ..addAll(candidate.shopping);
          _read
            ..clear()
            ..addAll(candidate._read);
          _libraryRevision = candidate._libraryRevision;
          if (!_disposed) notifyListeners();
          await _updateReminders();
        } finally {
          candidate.dispose();
        }
      }, reportFailure: false);

  void _validateLibrary() {
    final names = <String>{};
    for (final place in places) {
      if (place.name.trim().isEmpty || !names.add(place.name.toLowerCase())) {
        throw const FormatException('Invalid storage place');
      }
    }
    for (final medicine in medicines) {
      final plan = medicine.plan;
      if (medicine.name.trim().isEmpty ||
          !medicine.pack.isFinite ||
          medicine.pack <= 0 ||
          medicine.pack > 1000000 ||
          !medicine.remaining.isFinite ||
          medicine.remaining < 0 ||
          medicine.remaining > medicine.pack ||
          medicine.expires.isBefore(medicine.purchased) ||
          (plan != null &&
              (plan.amount < 1 ||
                  plan.amount > 10 ||
                  plan.times.isEmpty ||
                  plan.times.length > 10 ||
                  plan.times.toSet().length != plan.times.length))) {
        throw const FormatException('Invalid medicine record');
      }
    }
    if (shopping.map((item) => item.medicine).toSet().length !=
        shopping.length) {
      throw const FormatException('Invalid shopping list');
    }
  }

  Map<String, dynamic> _snapshot() => {
    ...exportLibrary(),
    'theme': theme.index,
    'tilt': tilt,
    'reminders': remindersEnabled,
    'libraryRevision': _libraryRevision,
  };

  Map<String, dynamic> exportLibrary() => {
    'places': [
      for (final place in places) {'name': place.name, 'kind': place.kind.name},
    ],
    'medicines': [
      for (final medicine in medicines)
        {
          'place': places.indexOf(medicine.place),
          'name': medicine.name,
          'ingredient': medicine.ingredient,
          'category': medicine.category,
          'form': medicine.form,
          'unit': medicine.unit,
          'pack': medicine.pack,
          'remaining': medicine.remaining,
          'purchase': medicine.purchased.toIso8601String(),
          'expiry': medicine.expires.toIso8601String(),
          'last': medicine.lastActivity.toIso8601String(),
          if (medicine.plan case final IntakePlan plan)
            'plan': {
              'amount': plan.amount,
              'unit': plan.unit,
              'when': plan.when,
              'times': [
                for (final time in plan.times) time.hour * 60 + time.minute,
              ],
            },
        },
    ],
    'shopping': [
      for (final item in shopping)
        {'medicine': medicines.indexOf(item.medicine), 'bought': item.bought},
    ],
    'read': _read.toList(),
  };

  void _restore(Map<String, dynamic> snapshot) {
    for (final entry in snapshot['places'] as List) {
      if (entry is String) {
        places.add(StoragePlace(entry, StorageKind.fromName(entry)));
      } else if (entry case {
        'name': final String name,
        'kind': final String kind,
      }) {
        places.add(StoragePlace(name, StorageKind.values.byName(kind)));
      } else {
        throw const FormatException('Invalid storage place');
      }
    }
    for (final row
        in (snapshot['medicines'] as List).cast<Map<String, dynamic>>()) {
      final plan = row['plan'] as Map<String, dynamic>?;
      final times = (plan?['times'] as List?)?.cast<int>() ?? const <int>[];
      if (times.any((time) => time < 0 || time >= 1440)) {
        throw const FormatException('Invalid schedule time');
      }
      medicines.add(
        Medicine(
          place: places[row['place'] as int],
          name: row['name'] as String,
          ingredient: row['ingredient'] as String,
          category: row['category'] as String,
          form: row['form'] as String,
          unit: row['unit'] as String,
          pack: (row['pack'] as num).toDouble(),
          remaining: (row['remaining'] as num).toDouble(),
          purchased: DateTime.parse(row['purchase'] as String),
          expires: DateTime.parse(row['expiry'] as String),
          lastActivity: DateTime.parse(row['last'] as String),
          plan: plan == null
              ? null
              : IntakePlan(
                  plan['amount'] as int,
                  plan['unit'] as String,
                  times.length,
                  plan['when'] as String,
                  [
                    for (final time in times)
                      TimeOfDay(hour: time ~/ 60, minute: time % 60),
                  ],
                ),
        ),
      );
    }
    for (final row
        in (snapshot['shopping'] as List).cast<Map<String, dynamic>>()) {
      final medicine = medicines[row['medicine'] as int];
      shopping.add(
        ShoppingItem(
          medicine.name,
          'Осталась половина упаковки или меньше',
          '1 уп.',
          medicine: medicine,
        )..bought = row['bought'] as bool,
      );
    }
    _read.addAll((snapshot['read'] as List).cast<String>());
    theme = ThemeMode.values[snapshot['theme'] as int];
    tilt = snapshot['tilt'] as bool;
    remindersEnabled = snapshot['reminders'] as bool;
    _libraryRevision = snapshot['libraryRevision'] as int? ?? 0;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class PharmacyScope extends InheritedNotifier<PharmacyState> {
  const PharmacyScope({
    super.key,
    required PharmacyState state,
    required super.child,
  }) : super(notifier: state);

  static PharmacyState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PharmacyScope>()!.notifier!;

  static PharmacyState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PharmacyScope>()!.notifier!;
}
