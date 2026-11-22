import 'package:flutter/material.dart';

import '../medicines/medicine_detail_screen.dart';
import '../shared/palette.dart';
import '../shared/pharmacy_state.dart';
import '../shared/screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = PharmacyScope.of(context);
    final regular = state.medicines.where((medicine) => medicine.plan != null);
    const icons = {
      ReminderKind.expiry: Icons.schedule,
      ReminderKind.restock: Icons.shopping_basket_outlined,
      ReminderKind.review: Icons.fact_check_outlined,
    };

    return PharmacyScreen(
      trailing: const Icon(Icons.notifications_none_outlined),
      children: [
        const Intro('', 'Уведомления', ''),
        Panel(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            title: const Text('Системные уведомления'),
            subtitle: const Text('О приёме, сроках годности и остатках'),
            value: state.remindersEnabled,
            onChanged: state.setReminders,
          ),
        ),
        const SizedBox(height: 12),
        if (state.permissionDenied)
          PharmacyRow(
            icon: Icons.settings_outlined,
            title: 'Разрешить уведомления в Android',
            onTap: state.openNotificationSettings,
          ),
        for (final reminder in state.reminders) ...[
          PharmacyRow(
            icon: icons[reminder.kind]!,
            title: reminder.title,
            subtitle: reminder.body,
            trailing: Icon(
              reminder.read ? Icons.done : Icons.circle,
              size: reminder.read ? 18 : 8,
              color: context.color(PharmacyColor.accent),
              semanticLabel: reminder.read ? 'Прочитано' : 'Новое',
            ),
            onTap: reminder.read ? null : () => state.markRead(reminder),
          ),
          const SizedBox(height: 10),
        ],
        if (regular.isNotEmpty) const SectionHeading('План приёма'),
        for (final medicine in regular) ...[
          PharmacyRow(
            icon: Icons.schedule,
            title: medicine.name,
            subtitle: medicine.plan!.times
                .map((time) => time.format(context))
                .join(', '),
            onTap: () =>
                openScreen(context, MedicineDetailScreen(medicine: medicine)),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
