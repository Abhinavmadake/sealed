import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/vault_service.dart';
import '../widgets/common.dart';

class RecoveryKeyScreen extends StatefulWidget {
  const RecoveryKeyScreen({super.key, required this.recoveryKey});

  final String recoveryKey;

  @override
  State<RecoveryKeyScreen> createState() => _RecoveryKeyScreenState();
}

class _RecoveryKeyScreenState extends State<RecoveryKeyScreen> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = widget.recoveryKey.split('-');
    final lines = [for (var i = 0; i < groups.length; i += 4) groups.skip(i).take(4).join('  ')];
    return PopScope(
      canPop: false,
      child: FormPage(
        title: 'Your recovery key',
        children: [
          const Text(
            'If you ever forget your master password, this key is the only way to get your vault back. '
            'Write it down or store it somewhere safe and offline. It will not be shown again.',
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: SelectableText(
              lines.join('\n'),
              key: const Key('recovery-key'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 18, height: 1.6, letterSpacing: 1),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.recoveryKey));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Copied. Paste it somewhere safe, then clear it.')));
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
          gap,
          CheckboxListTile(
            value: _saved,
            onChanged: (v) => setState(() => _saved = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('I have saved my recovery key'),
          ),
          gap,
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _saved ? () => context.read<VaultService>().acknowledgeRecoveryKey() : null,
            child: const Text('Open my vault'),
          ),
        ],
      ),
    );
  }
}
