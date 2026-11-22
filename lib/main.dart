import 'package:flutter/material.dart';

import 'backend/notifications/android_reminders.dart';
import 'backend/storage/pharmacy_database.dart';
import 'frontend/app.dart';
import 'frontend/shared/palette.dart';
import 'frontend/shared/pharmacy_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _OpenPharmacy());
}

class _OpenPharmacy extends StatefulWidget {
  const _OpenPharmacy();

  @override
  State<_OpenPharmacy> createState() => _OpenPharmacyState();
}

class _OpenPharmacyState extends State<_OpenPharmacy> {
  final _database = PharmacyDatabase();
  late Future<PharmacyState> _state = _load();

  Future<PharmacyState> _load() async => PharmacyState(
    database: _database,
    system: AndroidReminders(),
    snapshot: await _database.load(),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<PharmacyState>(
    future: _state,
    builder: (context, snapshot) {
      if (snapshot.hasData) return LocalPharmacyApp(state: snapshot.data);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: pharmacyTheme(Brightness.light),
        darkTheme: pharmacyTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: snapshot.hasError
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Не удалось открыть защищённое хранилище.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => setState(() => _state = _load()),
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    },
  );
}
