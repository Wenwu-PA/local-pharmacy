import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class CompressedJson {
  static Uint8List encode(Map<String, dynamic> value, {int? maxBytes}) {
    final json = utf8.encode(jsonEncode(value));
    if (maxBytes != null && json.length > maxBytes) {
      throw const FormatException('Uncompressed data limit exceeded');
    }
    return Uint8List.fromList(gzip.encode(json));
  }

  static Map<String, dynamic> decode(List<int> bytes, {required int maxBytes}) {
    final sink = _BoundedBytes(maxBytes);
    gzip.decoder.startChunkedConversion(sink)
      ..add(bytes)
      ..close();
    final decoded = jsonDecode(utf8.decode(sink.builder.takeBytes()));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid JSON record');
    }
    return decoded;
  }
}

class _BoundedBytes implements Sink<List<int>> {
  _BoundedBytes(this.maxBytes);
  final int maxBytes;
  final builder = BytesBuilder(copy: false);

  @override
  void add(List<int> data) {
    if (data.length > maxBytes - builder.length) {
      throw const FormatException('Uncompressed data limit exceeded');
    }
    builder.add(data);
  }

  @override
  void close() {}
}
