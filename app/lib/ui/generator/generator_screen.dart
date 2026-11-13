import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/health/generator.dart';
import '../widgets/common.dart';

List<String>? _words;

Future<List<String>> loadWordlist() async => _words ??= (await rootBundle.loadString('assets/wordlist.txt'))
    .split('\n')
    .map((w) => w.trim())
    .where((w) => w.isNotEmpty)
    .toList();

class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({super.key, this.picking = false});

  final bool picking;

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  final _gen = Generator();
  bool _passphrase = false;
  PasswordOptions _options = const PasswordOptions();
  int _words = 5;
  String _separator = '-';
  bool _capitalize = true;
  bool _number = true;
  List<String> _list = const [];
  String _value = '';

  @override
  void initState() {
    super.initState();
    loadWordlist().then((w) {
      if (mounted) setState(() => _list = w);
    });
    _regenerate();
  }

  void _regenerate() {
    setState(() {
      if (_passphrase && _list.isNotEmpty) {
        _value = _gen.passphrase(_list, count: _words, separator: _separator, capitalize: _capitalize, number: _number);
      } else if (!_passphrase && _options.classes.isNotEmpty) {
        _value = _gen.password(_options);
      }
    });
  }

  double get _bits =>
      _passphrase ? Generator.passphraseBits(_words, _list.length, number: _number) : _options.bits;

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: (v) {
          onChanged(v);
          _regenerate();
        },
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabledClasses = [_options.lower, _options.upper, _options.digits, _options.symbols].where((x) => x).length;
    return FormPage(title: 'Generator', children: [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Password')),
          ButtonSegment(value: true, label: Text('Passphrase')),
        ],
        selected: {_passphrase},
        onSelectionChanged: (s) {
          _passphrase = s.first;
          _regenerate();
        },
      ),
      gap,
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
        child: SelectableText(
          _value,
          key: const Key('generated'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 18, height: 1.4),
        ),
      ),
      const SizedBox(height: 6),
      Text('About ${_bits.round()} bits of entropy', textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(onPressed: _regenerate, icon: const Icon(Icons.refresh), label: const Text('New')),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => copySecret(context, _value, 'Password'),
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
        ),
      ]),
      gap,
      if (!_passphrase) ...[
        Text('Length: ${_options.length}'),
        Slider(
          min: 8,
          max: 64,
          divisions: 56,
          value: _options.length.toDouble(),
          label: '${_options.length}',
          onChanged: (v) {
            _options = _options.copyWith(length: v.round());
            _regenerate();
          },
        ),
        _switch('Lowercase (a-z)', _options.lower, (v) {
          if (v || enabledClasses > 1) _options = _options.copyWith(lower: v);
        }),
        _switch('Uppercase (A-Z)', _options.upper, (v) {
          if (v || enabledClasses > 1) _options = _options.copyWith(upper: v);
        }),
        _switch('Digits (0-9)', _options.digits, (v) {
          if (v || enabledClasses > 1) _options = _options.copyWith(digits: v);
        }),
        _switch('Symbols (!@#…)', _options.symbols, (v) {
          if (v || enabledClasses > 1) _options = _options.copyWith(symbols: v);
        }),
        _switch('Avoid look-alikes (l, 1, O, 0)', _options.avoidAmbiguous,
            (v) => _options = _options.copyWith(avoidAmbiguous: v)),
      ] else ...[
        Text('Words: $_words'),
        Slider(
          min: 3,
          max: 10,
          divisions: 7,
          value: _words.toDouble(),
          label: '$_words',
          onChanged: (v) {
            _words = v.round();
            _regenerate();
          },
        ),
        Wrap(spacing: 8, children: [
          for (final sep in ['-', '.', ' ', '_'])
            ChoiceChip(
              label: Text(sep == ' ' ? 'space' : sep),
              selected: _separator == sep,
              onSelected: (_) {
                _separator = sep;
                _regenerate();
              },
            ),
        ]),
        _switch('Capitalise words', _capitalize, (v) => _capitalize = v),
        _switch('Add a number', _number, (v) => _number = v),
        Text('Words from the EFF large wordlist (CC BY 3.0).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
      if (widget.picking) ...[
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _value.isEmpty ? null : () => Navigator.pop(context, _value),
          child: const Text('Use this password'),
        ),
      ],
    ]);
  }
}
