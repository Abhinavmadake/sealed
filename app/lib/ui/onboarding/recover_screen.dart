import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/vault_service.dart';
import '../widgets/common.dart';

class RecoverScreen extends StatefulWidget {
  const RecoverScreen({super.key, required this.server});

  final String server;

  @override
  State<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends State<RecoverScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _key = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context
          .read<VaultService>()
          .recover(widget.server, _email.text.trim(), _key.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FormPage(
        title: 'Recover account',
        formKey: _form,
        children: [
          const InfoCard(
            icon: Icons.info_outline,
            text: 'Enter the recovery key you saved when you created your account, then choose a new '
                'master password. Your other devices will be signed out.',
          ),
          gap,
          ErrorText(_error),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: validateEmail,
          ),
          gap,
          TextFormField(
            controller: _key,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(labelText: 'Recovery key', hintText: 'ABCD-EFGH-…'),
            validator: (v) => (v ?? '').replaceAll(RegExp(r'[\s-]'), '').length == 52
                ? null
                : 'A recovery key has 52 letters and digits',
          ),
          gap,
          PasswordField(
            controller: _password,
            label: 'New master password',
            showStrength: true,
            validator: validateMasterPassword,
          ),
          gap,
          PasswordField(
            controller: _confirm,
            label: 'Confirm new master password',
            validator: (v) => v == _password.text ? null : 'Passwords do not match',
          ),
          const SizedBox(height: 24),
          BusyButton(label: 'Recover vault', busyLabel: 'Recovering…', busy: _busy, onPressed: _submit),
        ],
      );
}
