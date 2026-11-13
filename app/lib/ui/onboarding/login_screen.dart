import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/vault_service.dart';
import '../widgets/common.dart';
import 'recover_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.server});

  final String server;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<VaultService>().login(widget.server, _email.text.trim(), _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FormPage(
        title: 'Sign in',
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
            validator: (v) => (v ?? '').isEmpty ? 'Enter your master password' : null,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          BusyButton(label: 'Sign in', busyLabel: 'Deriving keys…', busy: _busy, onPressed: _submit),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => RecoverScreen(server: widget.server))),
            child: const Text('Forgot your master password?'),
          ),
        ],
      );
}
