import 'dart:math';

enum Strength { veryWeak, weak, fair, strong, veryStrong }

class StrengthResult {
  const StrengthResult(this.bits, this.level, [this.warning]);

  final double bits;
  final Strength level;
  final String? warning;

  bool get acceptable => level.index >= Strength.fair.index;
}

const _common = {
  '123456', 'password', '123456789', '12345678', '12345', 'qwerty', '1234567', '111111', '123123',
  'abc123', 'password1', '1234', 'iloveyou', '1q2w3e4r', '000000', 'qwerty123', 'zaq12wsx', 'dragon',
  'sunshine', 'princess', 'letmein', '654321', 'monkey', '1qaz2wsx', '123321', 'qwertyuiop', 'superman',
  'asdfghjkl', 'football', 'baseball', 'welcome', 'admin', 'login', 'passw0rd', 'master', 'hello',
  'freedom', 'whatever', 'trustno1', 'shadow', 'michael', 'jennifer', 'charlie', 'donald', 'password123',
  'qwerty1', 'aa123456', 'starwars', 'computer', 'mustang', 'access', 'flower', 'hottie', 'loveme',
  'zxcvbnm', 'batman', 'killer', 'pokemon', 'cheese', 'ninja', 'azerty', 'solo', 'lovely', 'secret',
  'welcome1', 'admin123', 'p@ssw0rd', 'india123', 'iloveu', 'samsung', 'google', 'apple', 'internet',
  'changeme', 'default', 'test', 'test123', 'guest', 'root', 'toor', 'qazwsx', 'asdf', 'asdf1234',
  '987654321', '112233', '121212', '696969', '7777777', '88888888', '11111111', 'abcd1234', 'abcdef',
  'liverpool', 'arsenal', 'chelsea', 'soccer', 'hockey', 'jordan23', 'michelle', 'daniel', 'thomas',
};

const _sequences = ['abcdefghijklmnopqrstuvwxyz', '01234567890', 'qwertyuiop', 'asdfghjkl', 'zxcvbnm'];

double _log2(num x) => log(x) / ln2;

/// Words an attacker would try as whole units, such as the generator's passphrase list.
Set<String> dictionaryWords = const {};

double? _passphraseBits(String password) {
  if (dictionaryWords.isEmpty) return null;
  final parts = password.split(RegExp(r'[\s\-_.]+')).where((p) => p.isNotEmpty).toList();
  if (parts.length < 2) return null;
  var bits = 0.0;
  for (final part in parts) {
    final word = part.toLowerCase().replaceAll(RegExp(r'[0-9]+$'), '');
    if (!dictionaryWords.contains(word)) return null;
    bits += _log2(dictionaryWords.length);
    if (word.length != part.length) bits += _log2(10);
  }
  if (password.contains(RegExp(r'[A-Z]'))) bits += 1;
  return bits;
}

StrengthResult estimateStrength(String password) {
  if (password.isEmpty) return const StrengthResult(0, Strength.veryWeak);
  final lower = password.toLowerCase();
  if (_common.contains(lower) || _common.contains(lower.replaceAll(RegExp(r'[0-9!.]+$'), ''))) {
    return const StrengthResult(4, Strength.veryWeak, 'This is one of the most common passwords');
  }

  var pool = 0;
  if (RegExp(r'[a-z]').hasMatch(password)) pool += 26;
  if (RegExp(r'[A-Z]').hasMatch(password)) pool += 26;
  if (RegExp(r'[0-9]').hasMatch(password)) pool += 10;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) pool += 33;

  var effective = 0.0;
  String? warning;
  final runes = lower.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final repeated = i >= 2 && runes[i] == runes[i - 1] && runes[i] == runes[i - 2];
    final sequential = i >= 2 && _inSequence(String.fromCharCodes(runes.sublist(i - 2, i + 1)));
    if (repeated) {
      warning ??= 'Avoid repeated characters';
      effective += 0.25;
    } else if (sequential) {
      warning ??= 'Avoid sequences like abc or 123';
      effective += 0.25;
    } else {
      effective += 1;
    }
  }

  var bits = effective * _log2(max(pool, 2));
  final asWords = _passphraseBits(password);
  if (asWords != null && asWords < bits) bits = asWords;
  if (RegExp(r'^[0-9]+$').hasMatch(password) && password.length <= 8) {
    bits = min(bits, 20);
    warning ??= 'Short number-only passwords are easy to guess';
  }
  final level = switch (bits) {
    < 28 => Strength.veryWeak,
    < 36 => Strength.weak,
    < 60 => Strength.fair,
    < 80 => Strength.strong,
    _ => Strength.veryStrong,
  };
  if (level.index < Strength.fair.index && password.length < 12) warning ??= 'Use at least 12 characters';
  return StrengthResult(bits, level, warning);
}

bool _inSequence(String three) {
  final reversed = three.split('').reversed.join();
  return _sequences.any((s) => s.contains(three) || s.contains(reversed));
}
