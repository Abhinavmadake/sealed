import 'dart:math';

class PasswordOptions {
  const PasswordOptions({
    this.length = 20,
    this.lower = true,
    this.upper = true,
    this.digits = true,
    this.symbols = true,
    this.avoidAmbiguous = false,
  });

  final int length;
  final bool lower;
  final bool upper;
  final bool digits;
  final bool symbols;
  final bool avoidAmbiguous;

  PasswordOptions copyWith({int? length, bool? lower, bool? upper, bool? digits, bool? symbols, bool? avoidAmbiguous}) =>
      PasswordOptions(
        length: length ?? this.length,
        lower: lower ?? this.lower,
        upper: upper ?? this.upper,
        digits: digits ?? this.digits,
        symbols: symbols ?? this.symbols,
        avoidAmbiguous: avoidAmbiguous ?? this.avoidAmbiguous,
      );

  List<String> get classes {
    String strip(String s) => avoidAmbiguous ? s.replaceAll(RegExp('[Il1O0o]'), '') : s;
    return [
      if (lower) strip('abcdefghijklmnopqrstuvwxyz'),
      if (upper) strip('ABCDEFGHIJKLMNOPQRSTUVWXYZ'),
      if (digits) strip('0123456789'),
      if (symbols) '!@#\$%^&*()-_=+[]{};:,.?/~',
    ];
  }

  double get bits {
    final pool = classes.fold<int>(0, (n, c) => n + c.length);
    return pool < 2 ? 0 : length * log(pool) / ln2;
  }
}

class Generator {
  Generator([Random? random]) : _random = random ?? Random.secure();

  final Random _random;

  String password(PasswordOptions o) {
    final classes = o.classes;
    if (classes.isEmpty) throw ArgumentError('choose at least one character type');
    if (o.length < classes.length) throw ArgumentError('too short for the chosen character types');
    final all = classes.join();
    final chars = [
      for (final c in classes) c[_random.nextInt(c.length)],
      for (var i = classes.length; i < o.length; i++) all[_random.nextInt(all.length)],
    ];
    for (var i = chars.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final t = chars[i];
      chars[i] = chars[j];
      chars[j] = t;
    }
    return chars.join();
  }

  String passphrase(List<String> words,
      {int count = 5, String separator = '-', bool capitalize = false, bool number = false}) {
    if (words.length < 2 || count < 1) throw ArgumentError('need a wordlist and at least one word');
    final picked = [
      for (var i = 0; i < count; i++)
        () {
          final w = words[_random.nextInt(words.length)];
          return capitalize ? '${w[0].toUpperCase()}${w.substring(1)}' : w;
        }(),
    ];
    if (number) picked[_random.nextInt(count)] += '${_random.nextInt(10)}';
    return picked.join(separator);
  }

  static double passphraseBits(int count, int listSize, {bool number = false}) =>
      count * log(listSize) / ln2 + (number ? log(10 * count) / ln2 : 0);
}
