import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../crypto/compressed_json.dart';

const _keyPrefix = 'FPK1';
const _framePrefix = 'FPL1';
const _chunkBytes = 480;
const _maxCompressed = 4 * 1024 * 1024;
const _maxUncompressed = 32 * 1024 * 1024;
const _publicKeyBytes = 32;
const _nonceBytes = 12;
const _macBytes = 16;
const _headerBytes = _publicKeyBytes + _nonceBytes + _macBytes;
const _maxEnvelope = _maxCompressed + _headerBytes;
const _maxFrames = (_maxEnvelope + _chunkBytes - 1) ~/ _chunkBytes;

final _exchange = X25519();
final _cipher = AesGcm.with256bits();
final _derive = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
final _random = Random.secure();

String _encode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
Uint8List _decode(String packed) =>
    base64Url.decode(base64Url.normalize(packed));
String _randomId(int size) =>
    _encode(List.generate(size, (_) => _random.nextInt(256)));

class TransferRequest {
  const TransferRequest._(this.id, this.publicKey);
  final String id;
  final SimplePublicKey publicKey;

  String get qr => '$_keyPrefix.$id.${_encode(publicKey.bytes)}';

  static TransferRequest parse(String value) {
    if (value.length > 80) throw const FormatException('Invalid recipient QR');
    final fields = value.split('.');
    if (fields.length != 3 || fields[0] != _keyPrefix) {
      throw const FormatException('Invalid recipient QR');
    }
    final id = _decode(fields[1]);
    final key = _decode(fields[2]);
    if (id.length != 16 ||
        key.length != _publicKeyBytes ||
        _encode(id) != fields[1] ||
        _encode(key) != fields[2]) {
      throw const FormatException('Invalid recipient QR');
    }
    return TransferRequest._(
      fields[1],
      SimplePublicKey(key, type: KeyPairType.x25519),
    );
  }
}

class LibraryRecipient {
  const LibraryRecipient._(this.request, this._keyPair);
  final TransferRequest request;
  final KeyPair _keyPair;

  static Future<LibraryRecipient> create() async {
    final pair = await _exchange.newKeyPair();
    final publicKey = await pair.extractPublicKey();
    return LibraryRecipient._(
      TransferRequest._(_randomId(16), publicKey),
      pair,
    );
  }

  Future<Map<String, dynamic>> decrypt(ReceivedLibrary received) async {
    if (received.recipientId != request.id ||
        received._bytes.length <= _headerBytes) {
      throw const FormatException('Invalid encrypted library');
    }
    final data = received._bytes;
    final sender = SimplePublicKey(
      Uint8List.sublistView(data, 0, _publicKeyBytes),
      type: KeyPairType.x25519,
    );
    final aad = _context(request, received.transferId, sender);
    final key = await _transferKey(_keyPair, sender, request.id, aad);
    try {
      final box = SecretBox(
        Uint8List.sublistView(data, _headerBytes),
        nonce: Uint8List.sublistView(
          data,
          _publicKeyBytes,
          _publicKeyBytes + _nonceBytes,
        ),
        mac: Mac(
          Uint8List.sublistView(
            data,
            _publicKeyBytes + _nonceBytes,
            _headerBytes,
          ),
        ),
      );
      final clear = await _cipher.decrypt(box, secretKey: key, aad: aad);
      return compute(_decodeLibrary, clear);
    } finally {
      key.destroy();
    }
  }

  void dispose() => _keyPair.destroy();
}

class LibraryTransfer {
  static Future<List<String>> encode(
    TransferRequest recipient,
    Map<String, dynamic> library,
  ) => compute(_encodeLibrary, (recipient.qr, library));
}

Future<List<String>> _encodeLibrary(
  (String, Map<String, dynamic>) input,
) async {
  final (requestQr, library) = input;
  final recipient = TransferRequest.parse(requestQr);
  final compressed = CompressedJson.encode(library, maxBytes: _maxUncompressed);
  if (compressed.length > _maxCompressed) {
    throw const FormatException('Library exceeds QR transfer size');
  }
  final transferId = _randomId(12);
  final sender = await _exchange.newKeyPair();
  try {
    final publicKey = await sender.extractPublicKey();
    final aad = _context(recipient, transferId, publicKey);
    final key = await _transferKey(
      sender,
      recipient.publicKey,
      recipient.id,
      aad,
    );
    try {
      final box = await _cipher.encrypt(compressed, secretKey: key, aad: aad);
      final packed =
          (BytesBuilder(copy: false)
                ..add(publicKey.bytes)
                ..add(box.nonce)
                ..add(box.mac.bytes)
                ..add(box.cipherText))
              .takeBytes();
      final count = (packed.length + _chunkBytes - 1) ~/ _chunkBytes;
      return [
        for (var index = 0; index < count; index++)
          '$_framePrefix.${recipient.id}.$transferId.$index.$count.'
              '${_encode(Uint8List.sublistView(packed, index * _chunkBytes, min(packed.length, (index + 1) * _chunkBytes)))}',
      ];
    } finally {
      key.destroy();
    }
  } finally {
    sender.destroy();
  }
}

Map<String, dynamic> _decodeLibrary(List<int> data) =>
    CompressedJson.decode(data, maxBytes: _maxUncompressed);

List<int> _context(
  TransferRequest recipient,
  String transferId,
  SimplePublicKey sender,
) => utf8.encode(
  // The v1 domain stays stable so existing installations can transfer their library.
  'family-pharmacy/qr/v1.${recipient.id}.$transferId.'
  '${_encode(recipient.publicKey.bytes)}.${_encode(sender.bytes)}',
);

Future<SecretKey> _transferKey(
  KeyPair pair,
  SimplePublicKey other,
  String recipientId,
  List<int> context,
) async {
  final shared = await _exchange.sharedSecretKey(
    keyPair: pair,
    remotePublicKey: other,
  );
  final material = await shared.extractBytes();
  try {
    // RFC 7748 allows the all-zero result to be rejected for small-order keys.
    if (material.every((byte) => byte == 0)) {
      throw const FormatException('Invalid transfer key');
    }
    return await _derive.deriveKey(
      secretKey: shared,
      nonce: _decode(recipientId),
      info: context,
    );
  } finally {
    shared.destroy();
  }
}

class ReceivedLibrary {
  const ReceivedLibrary._(this.recipientId, this.transferId, this._bytes);
  final String recipientId;
  final String transferId;
  final Uint8List _bytes;
}

class LibraryFrames {
  LibraryFrames(this.recipientId);
  final String recipientId;
  String? _transferId;
  int? _total;
  final _parts = <int, Uint8List>{};
  int _size = 0;

  int get received => _parts.length;
  int? get total => _total;

  /// Ignores codes from other sessions and accepts frames in any order.
  ReceivedLibrary? add(String qr) {
    if (qr.length > 750) return null;
    final fields = qr.split('.');
    if (fields.length != 6 ||
        fields[0] != _framePrefix ||
        fields[1] != recipientId) {
      return null;
    }
    final transferId = fields[2];
    final index = int.tryParse(fields[3]);
    final count = int.tryParse(fields[4]);
    if (transferId.length != 16 ||
        index == null ||
        count == null ||
        count < 1 ||
        count > _maxFrames ||
        index < 0 ||
        index >= count) {
      return null;
    }
    if (_transferId != null && (_transferId != transferId || _total != count)) {
      return null;
    }
    final Uint8List part;
    try {
      if (_decode(transferId).length != 12) return null;
      part = _decode(fields[5]);
    } on FormatException {
      return null;
    }
    if (part.isEmpty ||
        part.length > _chunkBytes ||
        (index != count - 1 && part.length != _chunkBytes)) {
      return null;
    }
    if (_parts.containsKey(index) || _size + part.length > _maxEnvelope) {
      return null;
    }

    _transferId = transferId;
    _total = count;
    _parts[index] = part;
    _size += part.length;
    if (_parts.length != count) return null;

    final data = BytesBuilder(copy: false);
    for (var index = 0; index < count; index++) {
      data.add(_parts[index]!);
    }
    return ReceivedLibrary._(recipientId, transferId, data.takeBytes());
  }
}
