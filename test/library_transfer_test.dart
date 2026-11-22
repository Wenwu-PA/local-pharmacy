import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:local_pharmacy/backend/crypto/compressed_json.dart';
import 'package:local_pharmacy/backend/sharing/library_transfer.dart';
import 'package:local_pharmacy/frontend/shared/pharmacy_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _sampleLibrary() {
  final state = PharmacyState();
  final random = Random(124);
  final place = StoragePlace('Дорожная сумка', StorageKind.bag);
  state.addPlace(place);
  for (var index = 0; index < 70; index++) {
    final name = String.fromCharCodes(
      List.generate(24, (_) => 97 + random.nextInt(26)),
    );
    state.saveMedicine(
      Medicine(
        place: place,
        name: name,
        ingredient: 'Пример действующего вещества',
        category: categories.first,
        form: 'Таблетки',
        unit: units.first,
        pack: 20,
        remaining: index == 0 ? 3 : 20,
        purchased: DateTime(2026, 2, 1),
        expires: DateTime(2027, 1, 1),
      ),
      IntakePlan(1, units.first, 1, 'Утром', const [
        TimeOfDay(hour: 8, minute: 30),
      ]),
    );
  }
  final library = state.exportLibrary();
  state.dispose();
  return library;
}

ReceivedLibrary _assemble(LibraryFrames assembly, Iterable<String> frames) {
  ReceivedLibrary? result;
  for (final frame in frames) {
    result = assembly.add(frame) ?? result;
  }
  return result!;
}

void main() {
  test(
    'A complete library round-trips through shuffled encrypted QR frames',
    () async {
      final library = _sampleLibrary();
      final recipient = await LibraryRecipient.create();
      addTearDown(recipient.dispose);

      final request = TransferRequest.parse(recipient.request.qr);
      final frames = await LibraryTransfer.encode(request, library);
      expect(frames.length, greaterThan(1));
      expect(frames.join(), isNot(contains('Дорожная сумка')));

      final assembly = LibraryFrames(request.id);
      expect(assembly.add('https://example.com'), isNull);
      expect(assembly.add(frames.last), isNull);
      expect(assembly.add(frames.last), isNull);
      expect(assembly.received, 1);
      final received = _assemble(assembly, frames.reversed);
      expect(await recipient.decrypt(received), library);
    },
  );

  test(
    'A damaged QR payload and a substituted recipient cannot decrypt',
    () async {
      final recipient = await LibraryRecipient.create();
      final other = await LibraryRecipient.create();
      addTearDown(recipient.dispose);
      addTearDown(other.dispose);

      final frames = await LibraryTransfer.encode(
        recipient.request,
        _sampleLibrary(),
      );
      final altered = frames.toList();
      final marker = altered[0].lastIndexOf('.') + 1;
      final index = marker + 160;
      final set = altered[0][index] == 'A' ? 'B' : 'A';
      altered[0] = altered[0].replaceRange(index, index + 1, set);
      final corrupted = _assemble(LibraryFrames(recipient.request.id), altered);
      await expectLater(
        recipient.decrypt(corrupted),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );

      final substituted = frames.map(
        (frame) => frame.replaceFirst(
          '.${recipient.request.id}.',
          '.${other.request.id}.',
        ),
      );
      final wrong = _assemble(LibraryFrames(other.request.id), substituted);
      await expectLater(
        other.decrypt(wrong),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    },
  );

  test('A repeated large record compresses and expansion has a byte limit', () {
    final input = {'records': List.filled(1000, 'локальная аптека')};
    final compressed = CompressedJson.encode(input);
    expect(compressed.length, lessThan(500));
    expect(
      () => CompressedJson.decode(compressed, maxBytes: 800),
      throwsFormatException,
    );
    expect(CompressedJson.decode(compressed, maxBytes: 50000), input);
  });

  test(
    'Import replaces the whole library, preserves settings and rejects invalid rows',
    () async {
      final state = PharmacyState()..setTheme(ThemeMode.dark);
      addTearDown(state.dispose);
      state.setTilt(false);
      await state.setReminders(true);
      state.addPlace(StoragePlace('Старое место', StorageKind.home));
      final library = _sampleLibrary();
      await state.replaceLibrary(library);

      expect(state.exportLibrary(), library);
      expect(state.theme, ThemeMode.dark);
      expect(state.tilt, isFalse);
      expect(state.remindersEnabled, isTrue);

      final invalid = {...library, 'places': []};
      await expectLater(
        state.replaceLibrary(invalid),
        throwsA(isA<RangeError>()),
      );
      expect(state.exportLibrary(), library);
    },
  );
}
