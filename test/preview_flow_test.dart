import 'package:local_pharmacy/frontend/app.dart';
import 'package:local_pharmacy/frontend/shared/pharmacy_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Quaternion;

Future<void> _openApp(
  WidgetTester tester, {
  bool reduceMotion = true,
  PharmacyState? state,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 852);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: reduceMotion);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(LocalPharmacyApp(state: state));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Capsule shrinks and returns when scrolling the home screen', (
    tester,
  ) async {
    await _openApp(tester, reduceMotion: false);

    final projection = find.byKey(const ValueKey('capsule-projection'));
    double scale() =>
        tester.widget<Transform>(projection).transform.entry(0, 0);
    expect(scale(), 1);
    await tester.dragFrom(const Offset(25, 430), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(scale(), lessThan(.85));
    await tester.dragFrom(const Offset(25, 320), const Offset(0, 260));
    await tester.pumpAndSettle();
    expect(scale(), 1);
  });

  testWidgets('Capsule completes a full turn around either screen axis', (
    tester,
  ) async {
    await _openApp(tester, reduceMotion: false);
    final surface = find.byKey(const ValueKey('capsule-surface'));
    Quaternion rotation() {
      final dynamic painter = tester.widget<CustomPaint>(surface).painter;
      return painter.rotation as Quaternion;
    }

    double similarity(Quaternion a, Quaternion b) =>
        (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w).abs();
    const turn = (393.0 - 40) * .43;
    final drag = find.byKey(const ValueKey('capsule-drag-area'));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    for (final axis in const [Offset(1, 0), Offset(0, 1)]) {
      final initial = rotation();
      final gesture = await tester.startGesture(tester.getCenter(drag));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(axis * (turn / 12));
        await tester.pump();
        if (i == 5) expect(similarity(initial, rotation()), lessThan(.10));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(similarity(initial, rotation()), greaterThan(.99));
      expect(scroll.position.pixels, 0);
    }
  });

  testWidgets(
    'Capsule returns to rest after drag and resumes vertical motion',
    (tester) async {
      await _openApp(
        tester,
        reduceMotion: false,
        state: PharmacyState()..setTilt(false),
      );
      final previous =
          tester.binding.lifecycleState ?? AppLifecycleState.detached;
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(previous),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      final surface = find.byKey(const ValueKey('capsule-surface'));
      final projection = find.byKey(const ValueKey('capsule-projection'));
      Quaternion rotation() {
        final dynamic painter = tester.widget<CustomPaint>(surface).painter;
        return painter.rotation as Quaternion;
      }

      double similarity(Quaternion a, Quaternion b) =>
          (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w).abs();
      final initial = tester.getCenter(projection);
      final rest = rotation();
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.getCenter(projection).dy, lessThan(initial.dy - 1));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('capsule-drag-area'))),
      );
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      final held = tester.getCenter(projection);
      expect(held.dx, greaterThan(initial.dx + 10));
      expect(similarity(rest, rotation()), lessThan(.9));
      await tester.pump(const Duration(milliseconds: 360));
      expect(tester.getCenter(projection), held);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      final returning = tester.getCenter(projection);
      expect(returning.dx, inExclusiveRange(initial.dx, held.dx));
      expect(similarity(rest, rotation()), inExclusiveRange(.9, 1.0));
      await tester.pump(const Duration(milliseconds: 420));
      expect(tester.getCenter(projection).dx, closeTo(initial.dx, .01));
      expect(similarity(rest, rotation()), closeTo(1, .001));
      final returned = tester.getCenter(projection);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getCenter(projection).dy, lessThan(returned.dy));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Outlined action and header buttons have dark borders in dark mode',
    (tester) async {
      await _openApp(tester, state: PharmacyState()..setTheme(ThemeMode.dark));
      final plus = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add),
      );
      expect(
        plus.style?.side?.resolve({})?.color.computeLuminance(),
        lessThan(.05),
      );
      await tester.tap(find.byTooltip('Добавить место'));
      await tester.pumpAndSettle();
      final save = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Создать место'),
      );
      expect(
        save.style?.side?.resolve({})?.color.computeLuminance(),
        lessThan(.05),
      );
    },
  );

  testWidgets(
    'Holding and sliding on the glass menu switches tabs before release',
    (tester) async {
      await _openApp(tester, reduceMotion: false);
      final home = tester.getCenter(find.text('Главная'));
      final basket = tester.getCenter(find.text('Корзина'));
      final settings = tester.getCenter(find.text('Настройки'));
      final pointer = await tester.startGesture(home);
      await tester.pump(const Duration(milliseconds: 550));
      await pointer.moveTo(basket);
      await tester.pumpAndSettle();
      expect(find.text('Нужно\nдокупить.'), findsOneWidget);
      await pointer.moveTo(settings);
      await tester.pumpAndSettle();
      expect(find.text('Тема оформления'), findsOneWidget);
      await pointer.up();
      await tester.pumpAndSettle();
      expect(find.text('Тема оформления'), findsOneWidget);
    },
  );

  testWidgets('Storage creation opens an empty medicine list', (tester) async {
    await _openApp(tester);

    expect(find.text('Живая капсула'), findsNothing);
    expect(find.text('Аптека'), findsOneWidget);
    await tester.tap(find.byTooltip('Добавить место'));
    await tester.pumpAndSettle();
    expect(find.text('Где хранятся\nлекарства?'), findsOneWidget);
    await tester.tap(find.text('Работа'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Работа'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Дача');
    await tester.tap(find.text('Создать место'));
    await tester.pumpAndSettle();

    expect(find.text('Дача'), findsOneWidget);
    expect(find.byIcon(Icons.work_outline), findsOneWidget);
    expect(find.text('Добавьте первое лекарство в это место.'), findsOneWidget);
    await tester.tap(find.text('+ Добавить'));
    await tester.pumpAndSettle();
    expect(find.text('Добавить\nлекарство.'), findsOneWidget);
    final fields = find.byType(TextFormField);
    expect(
      tester.getTopLeft(fields.at(1)).dy -
          tester.getBottomLeft(fields.at(0)).dy,
      greaterThanOrEqualTo(16),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('A new pharmacy contains no sample entries', (tester) async {
    await _openApp(tester);
    expect(find.text('Дом'), findsNothing);
    await tester.tap(find.byTooltip('Уведомления'));
    await tester.pumpAndSettle();
    expect(find.text('Системные уведомления'), findsOneWidget);
    expect(find.text('Проверьте остаток'), findsNothing);
  });

  testWidgets('Theme can be changed from the theme sheet', (tester) async {
    await _openApp(tester);

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    final theme = find.text('Тема оформления');
    await tester.ensureVisible(theme);
    await tester.tap(theme);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();

    expect(Theme.of(tester.element(theme)).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  test('Saved places retain names and restore legacy and explicit icons', () {
    final state = PharmacyState(
      snapshot: {
        'places': [
          'Лекарства в машине',
          {'name': 'На даче', 'kind': 'bag'},
        ],
        'medicines': [],
        'shopping': [],
        'read': [],
        'theme': 0,
        'tilt': true,
        'reminders': false,
      },
    );
    addTearDown(state.dispose);
    expect(state.places.map((place) => place.name), [
      'Лекарства в машине',
      'На даче',
    ]);
    expect(state.places.map((place) => place.kind), [
      StorageKind.car,
      StorageKind.bag,
    ]);
  });

  test('Regular stock crossing half adds one shopping item and reminder', () {
    final state = PharmacyState();
    addTearDown(state.dispose);
    final place = StoragePlace('Дом', StorageKind.home);
    state.addPlace(place);
    final medicine = Medicine(
      place: place,
      name: 'Тестовое лекарство',
      ingredient: '',
      category: categories.first,
      form: 'Таблетки',
      unit: 'таб.',
      pack: 30,
      remaining: 18,
      purchased: DateTime.now(),
      expires: DateTime.now().add(const Duration(days: 60)),
    );
    state.saveMedicine(
      medicine,
      IntakePlan(1, 'таб.', 1, 'Утром', const [TimeOfDay(hour: 8, minute: 0)]),
    );

    expect(state.consume(medicine, 3), isTrue);
    expect(medicine.remaining, 15);
    expect(state.consume(medicine, 1), isTrue);
    expect(state.consume(medicine, 20), isFalse);
    expect(medicine.remaining, 14);
    expect(
      state.shopping.where((item) => item.medicine == medicine),
      hasLength(1),
    );
    expect(
      state.reminders.where((item) => item.body.contains(medicine.name)),
      hasLength(1),
    );
  });
}
