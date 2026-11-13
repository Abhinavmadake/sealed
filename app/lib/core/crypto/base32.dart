import 'dart:typed_data';

const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

String base32Encode(Uint8List data) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in data) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

Uint8List base32Decode(String text, int length) {
  final clean = text.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (clean.length != (length * 8 + 4) ~/ 5) {
    throw const FormatException('wrong length');
  }
  final out = BytesBuilder();
  var buffer = 0;
  var bits = 0;
  for (final char in clean.split('')) {
    final value = _alphabet.indexOf(char);
    if (value < 0) throw FormatException('invalid character $char');
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      out.addByte((buffer >> (bits - 8)) & 0xff);
      bits -= 8;
    }
    buffer &= (1 << bits) - 1;
  }
  if (buffer != 0) throw const FormatException('invalid trailing bits');
  return out.toBytes();
}

String groupEvery(String text, int size) {
  final groups = <String>[];
  for (var i = 0; i < text.length; i += size) {
    groups.add(text.substring(i, i + size > text.length ? text.length : i + size));
  }
  return groups.join('-');
}
