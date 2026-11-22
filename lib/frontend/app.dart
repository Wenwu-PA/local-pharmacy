import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'basket/basket_screen.dart';
import 'home/home_screen.dart';
import 'locations/locations_screen.dart';
import 'medicines/medicine_list_screen.dart';
import 'notifications/notifications_screen.dart';
import 'settings/settings_screen.dart';
import 'shared/glass_navigation.dart';
import 'shared/palette.dart';
import 'shared/pharmacy_state.dart';
import 'shared/screen.dart';

class LocalPharmacyApp extends StatefulWidget {
  const LocalPharmacyApp({super.key, this.state});

  final PharmacyState? state;

  @override
  State<LocalPharmacyApp> createState() => _LocalPharmacyAppState();
}

class _LocalPharmacyAppState extends State<LocalPharmacyApp> {
  late final _state = widget.state ?? PharmacyState();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _state.refresh);
    _state.refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PharmacyScope(
    state: _state,
    child: const _AppTheme(child: _RootScreen()),
  );
}

class _AppTheme extends StatelessWidget {
  const _AppTheme({required this.child});

  final Widget child;
  static final _light = pharmacyTheme(Brightness.light);
  static final _dark = pharmacyTheme(Brightness.dark);

  @override
  Widget build(BuildContext context) {
    final state = PharmacyScope.of(context);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Локальная аптека',
      theme: _light,
      darkTheme: _dark,
      themeMode: state.theme,
      themeAnimationDuration: Duration.zero,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => state.saveFailed
          ? Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: MaterialBanner(
                    content: const Text(
                      'Изменения не удалось сохранить на телефоне.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: state.retrySave,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
                Expanded(child: child!),
              ],
            )
          : child!,
      home: child,
    );
  }
}

class _RootScreen extends StatefulWidget {
  const _RootScreen();

  @override
  State<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<_RootScreen> {
  int _tab = 0;

  void _select(int tab) {
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    _preview(tab);
  }

  void _preview(int tab) {
    if (tab != _tab) setState(() => _tab = tab);
  }

  void _notifications() => openScreen(context, const NotificationsScreen());

  Future<void> _addLocation() async {
    final place = await openScreen<StoragePlace>(
      context,
      const AddLocationScreen(),
    );
    if (mounted && place != null) {
      setState(() => _tab = 1);
      _location(place);
    }
  }

  void _location(StoragePlace place) => openScreen(
    context,
    MedicineListScreen(
      place: place,
      navigation: GlassNavigation(selected: 1, onSelect: _select),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final screen = switch (_tab) {
      0 => HomeScreen(
        onAdd: _addLocation,
        onNotifications: _notifications,
        onBasket: () => _select(2),
        onLocation: _location,
      ),
      1 => LocationsScreen(onAdd: _addLocation, onLocation: _location),
      2 => const BasketScreen(),
      _ => SettingsScreen(
        onLocations: () => _select(1),
        onNotifications: _notifications,
      ),
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        screen,
        PharmacyDock(
          child: GlassNavigation(
            selected: _tab,
            onSelect: _select,
            onPreview: _preview,
          ),
        ),
      ],
    );
  }
}
