import 'package:flutter/material.dart';

import '../shared/palette.dart';
import '../shared/pharmacy_state.dart';
import '../shared/screen.dart';
import '../sharing/library_sharing_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.onLocations,
    required this.onNotifications,
  });

  final VoidCallback onLocations;
  final VoidCallback onNotifications;

  static const _themes = {
    ThemeMode.system: 'Как в системе',
    ThemeMode.light: 'Светлая',
    ThemeMode.dark: 'Тёмная',
  };

  @override
  Widget build(BuildContext context) {
    final state = PharmacyScope.of(context);

    return PharmacyScreen(
      reserveNavigationSpace: true,
      trailing: const Icon(Icons.settings_outlined),
      children: [
        const Intro('', 'Настройки', ''),
        PharmacyRow(
          icon: Icons.qr_code_2,
          title: 'Передача аптеки',
          onTap: () => openScreen(context, const LibrarySharingScreen()),
        ),
        const SizedBox(height: 9),
        PharmacyRow(
          icon: Icons.notifications_none_outlined,
          title: 'Уведомления и расписание',
          onTap: onNotifications,
        ),
        const SizedBox(height: 9),
        PharmacyRow(
          icon: Icons.place_outlined,
          title: 'Места хранения',
          onTap: onLocations,
        ),
        const SizedBox(height: 9),
        PharmacyRow(
          icon: Icons.dark_mode_outlined,
          title: 'Тема оформления',
          subtitle: _themes[state.theme],
          onTap: () async {
            final theme = await showModalBottomSheet<ThemeMode>(
              context: context,
              showDragHandle: true,
              useSafeArea: true,
              backgroundColor: context.color(PharmacyColor.glass),
              builder: (context) => SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: [
                      const SectionHeading('Тема оформления'),
                      for (final entry in _themes.entries)
                        PharmacyRow(
                          icon: switch (entry.key) {
                            ThemeMode.system => Icons.brightness_auto_outlined,
                            ThemeMode.light => Icons.light_mode_outlined,
                            ThemeMode.dark => Icons.dark_mode_outlined,
                          },
                          title: entry.value,
                          trailing: Icon(
                            entry.key == state.theme
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: Theme.of(context).colorScheme.primary,
                            semanticLabel: entry.key == state.theme
                                ? 'Выбрано'
                                : null,
                          ),
                          onTap: () => Navigator.pop(context, entry.key),
                        ),
                    ],
                  ),
                ),
              ),
            );
            if (context.mounted && theme != null) state.setTheme(theme);
          },
        ),
        const SizedBox(height: 9),
        Panel(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            secondary: const Icon(Icons.screen_rotation_outlined),
            title: const Text('Реакция капсулы на наклон'),
            value: state.tilt,
            onChanged: state.setTilt,
          ),
        ),
      ],
    );
  }
}
