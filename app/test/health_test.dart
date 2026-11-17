import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_app/core/health/breach.dart';
import 'package:sealed_app/core/health/generator.dart';
import 'package:sealed_app/core/health/strength.dart';
import 'package:sealed_app/core/health/vault_health.dart';
import 'package:sealed_app/models/vault_item.dart';

void main() {
  group('strength', () {
    test('common and short passwords are very weak', () {
      for (final p in ['password', 'Password1', '123456', 'qwerty', '1234']) {
        expect(estimateStrength(p).level, Strength.veryWeak, reason: p);
      }
      expect(estimateStrength('password').warning, contains('common'));
    });

    test('patterns cost strength', () {
      expect(estimateStrength('aaaaaaaaaaaa').acceptable, isFalse);
      expect(estimateStrength('abcdefghijkl').acceptable, isFalse);
      expect(estimateStrength('aaaaaaaaaaaa').warning, contains('repeated'));
    });

    test('passphrases from the wordlist are scored per word', () {
      dictionaryWords = {for (var i = 0; i < 7776; i++) 'w$i'}..addAll(['copper', 'meadow', 'quartz', 'tundra', 'falcon']);
      final four = estimateStrength('copper-meadow-quartz-tundra');
      expect(four.bits, closeTo(4 * log(7776) / ln2, 0.5));
      expect(four.level, Strength.fair);
      expect(estimateStrength('Copper-Meadow-Quartz-Tundra-Falcon7').level, Strength.strong);
      expect(estimateStrength('copper-meadow-notaword').bits, greaterThan(100));
      dictionaryWords = const {};
    });

    test('long random passwords and passphrases are strong', () {
      expect(estimateStrength('vT9#qL2!mZ7@wR4x').level.index, greaterThanOrEqualTo(Strength.strong.index));
      expect(estimateStrength('copper-meadow-quartz-tundra-falcon').level, Strength.veryStrong);
    });
  });

  group('generator', () {
    final gen = Generator(Random(42));

    test('respects length and includes every chosen class', () {
      for (var i = 0; i < 200; i++) {
        final p = gen.password(const PasswordOptions(length: 8));
        expect(p.length, 8);
        expect(p, matches(RegExp(r'[a-z]')));
        expect(p, matches(RegExp(r'[A-Z]')));
        expect(p, matches(RegExp(r'[0-9]')));
        expect(p, matches(RegExp(r'[^a-zA-Z0-9]')));
      }
    });

    test('honours exclusions', () {
      const o = PasswordOptions(length: 64, symbols: false, upper: false, avoidAmbiguous: true);
      final p = gen.password(o);
      expect(p, matches(RegExp(r'^[a-z0-9]+$')));
      expect(p, isNot(matches(RegExp('[l1o0]'))));
      expect(() => gen.password(const PasswordOptions(lower: false, upper: false, digits: false, symbols: false)),
          throwsArgumentError);
    });

    test('entropy estimates', () {
      expect(const PasswordOptions(length: 20).bits, closeTo(20 * log(87) / ln2, 0.01));
      expect(Generator.passphraseBits(5, 7776), closeTo(64.6, 0.1));
    });

    test('passphrases', () {
      final words = ['alpha', 'bravo', 'charlie', 'delta'];
      final p = gen.passphrase(words, count: 4, capitalize: true, number: true);
      expect(p.split('-').length, 4);
      expect(p, matches(RegExp(r'^([A-Z][a-z]+\d?-){3}[A-Z][a-z]+\d?$')));
      expect(p, matches(RegExp(r'\d')));
    });
  });

  test('breach check only sends a five character prefix', () {
    final (prefix, suffix) = BreachChecker.split('password');
    expect(prefix, '5BAA6');
    expect(suffix, '1E4C9B93F3F0682250B6CF8331B7EE68FD8');
  });

  test('vault health finds weak and reused passwords', () {
    VaultItem item(String id, String pw, [ItemType type = ItemType.login]) =>
        VaultItem(id: id, title: id, password: pw, type: type, modifiedAt: DateTime(2026));
    final report = analyseVault([
      item('a', 'password'),
      item('b', 'vT9#qL2!mZ7@wR4x'),
      item('c', 'vT9#qL2!mZ7@wR4x'),
      item('d', 'Kp8\$wN3&yB6^hJ1z'),
      item('n', 'password', ItemType.note),
    ]);
    expect(report.checked, 4);
    expect(report.weak.map((w) => w.$1.id), ['a']);
    expect(report.reused.single.map((i) => i.id), ['b', 'c']);
    expect(report.score(), 25);
    expect(report.score(['a']), 25);
    expect(report.score(['a', 'd']), 0);
  });
}
