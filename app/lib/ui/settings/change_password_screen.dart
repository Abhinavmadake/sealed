import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/vault_service.dart';
import '../widgets/common.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
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
      await context.read<VaultService>().changePassword(_current.text, _next.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Master password changed. Your other devices were signed out.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FormPage(title: 'Change master password', formKey: _form, children: [
        const InfoCard(
          icon: Icons.info_outline,
          text: 'Only your account key is re-wrapped, so this is instant however large the vault is. '
              'Other devices will need to sign in with the new password.',
        ),
        gap,
        ErrorText(_error),
        PasswordField(controller: _current, label: 'Current master password'),
        gap,
        PasswordField(controller: _next, label: 'New master password', showStrength: true, validator: validateMasterPassword),
        gap,
        PasswordField(
          controller: _confirm,
          label: 'Confirm new master password',
          validator: (v) => v == _next.text ? null : 'Passwords do not match',
        ),
        const SizedBox(height: 24),
        BusyButton(label: 'Change password', busyLabel: 'Re-encrypting keys…', busy: _busy, onPressed: _submit),
      ]);
}
