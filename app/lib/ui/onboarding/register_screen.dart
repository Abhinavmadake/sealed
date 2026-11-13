import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/vault_service.dart';
import '../widgets/common.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.server});

  final String server;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
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
      await context.read<VaultService>().register(widget.server, _email.text.trim(), _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FormPage(
        title: 'Create account',
        formKey: _form,
        children: [
          ErrorText(_error),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: validateEmail,
          ),
          gap,
          PasswordField(
            controller: _password,
            label: 'Master password',
            showStrength: true,
            validator: validateMasterPassword,
            textInputAction: TextInputAction.next,
          ),
          gap,
          PasswordField(
            controller: _confirm,
            label: 'Confirm master password',
            validator: (v) => v == _password.text ? null : 'Passwords do not match',
            onSubmitted: (_) => _submit(),
          ),
          gap,
          const InfoCard(
            icon: Icons.key_outlined,
            text: 'Your master password never leaves this device and nobody can reset it. '
                'You will get a recovery key next, which is the only other way back in.',
          ),
          const SizedBox(height: 24),
          BusyButton(label: 'Create account', busyLabel: 'Generating keys…', busy: _busy, onPressed: _submit),
        ],
      );
}
