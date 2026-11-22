import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../crypto/compressed_json.dart';

class PharmacyDatabase {
  static const _channel = MethodChannel('com.localpharmacy.app/secure-storage');
  static const _maxRecordBytes = 64 * 1024 * 1024;
  // Keep large records within Android's per-row CursorWindow limit.
  static const _chunkSize = 128 * 1024;
  static const _create =
      'CREATE TABLE pharmacy (id INTEGER PRIMARY KEY, content BLOB NOT NULL)';

  Future<Database>? _database;

  Future<Database> _open() async {
    try {
      return await (_database ??= openDatabase(
        'local_pharmacy.db',
        version: 2,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA secure_delete = ON');
          await db.rawQuery('PRAGMA journal_mode = DELETE');
        },
        onCreate: (db, _) => db.execute(_create),
        onUpgrade: (db, old, _) async {
          if (old != 1) throw StateError('Unsupported store version');
          final previous = await _readLegacy(db);
          final encrypted = previous == null ? null : await _seal(previous);
          await db.execute('DROP TABLE pharmacy');
          await db.execute(_create);
          if (encrypted != null) await _writeChunks(db, encrypted);
          await db.execute(
            'CREATE TABLE compact_after_upgrade (marker INTEGER)',
          );
        },
        onOpen: (db) async {
          final marker = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE name = 'compact_after_upgrade'",
          );
          if (marker.isEmpty) return;
          // Clear pages freed by older versions, including after an interrupted migration.
          await db.execute('VACUUM');
          await db.execute('DROP TABLE compact_after_upgrade');
        },
      ));
    } catch (_) {
      _database = null;
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> _readLegacy(Database db) async {
    final sizes = await db.rawQuery(
      'SELECT length(content) AS size FROM pharmacy WHERE id = 1',
    );
    if (sizes.isEmpty) return null;
    final size = sizes.single['size'] as int;
    if (size > _maxRecordBytes) {
      throw const FormatException('Legacy record is too large');
    }
    final json = StringBuffer();
    for (var offset = 1; offset <= size; offset += 65536) {
      final rows = await db.rawQuery(
        'SELECT substr(content, ?, 65536) AS part FROM pharmacy WHERE id = 1',
        [offset],
      );
      json.write(rows.single['part'] as String);
    }
    return jsonDecode(json.toString()) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> load() async {
    final rows = await (await _open()).query('pharmacy', orderBy: 'id');
    if (rows.isEmpty) return null;
    final encrypted = BytesBuilder(copy: false);
    for (final row in rows) {
      encrypted.add(row['content'] as Uint8List);
    }
    final compressed = await _transform('open', encrypted.takeBytes());
    return compute(_decodeRecord, compressed);
  }

  Future<void> save(Map<String, dynamic> snapshot) async {
    final database = await _open();
    final encrypted = await _seal(snapshot);
    await database.transaction(
      (transaction) => _writeChunks(transaction, encrypted),
    );
  }

  static Future<void> _writeChunks(
    DatabaseExecutor db,
    Uint8List encrypted,
  ) async {
    final batch = db.batch();
    batch.delete('pharmacy');
    for (var offset = 0; offset < encrypted.length; offset += _chunkSize) {
      batch.insert('pharmacy', {
        'id': offset ~/ _chunkSize + 1,
        'content': Uint8List.sublistView(
          encrypted,
          offset,
          min(offset + _chunkSize, encrypted.length),
        ),
      });
    }
    await batch.commit(noResult: true);
  }

  static Uint8List _encodeRecord(Map<String, dynamic> snapshot) =>
      CompressedJson.encode(snapshot, maxBytes: _maxRecordBytes);

  static Map<String, dynamic> _decodeRecord(Uint8List compressed) =>
      CompressedJson.decode(compressed, maxBytes: _maxRecordBytes);

  static Future<Uint8List> _seal(Map<String, dynamic> snapshot) async =>
      _transform('seal', await compute(_encodeRecord, snapshot));

  static Future<Uint8List> _transform(String method, Uint8List data) async {
    final transformed = await _channel.invokeMethod<Uint8List>(method, data);
    if (transformed == null) throw StateError('Encrypted storage unavailable');
    return transformed;
  }
}
