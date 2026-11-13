import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/crypto/sealed_crypto.dart';
import '../../core/health/strength.dart';
import '../../models/vault_item.dart';
import '../../services/auth_flow.dart';
import '../../services/sharing.dart';
import '../../services/vault_service.dart';

String friendlyError(Object error) => switch (error) {
      OfflineException() => 'Cannot reach the server. Check your connection and try again.',
      ApiException(:final message) => message[0].toUpperCase() + message.substring(1),
      WrongPassword() => 'Wrong master password',
      DecryptionFailed() => 'Could not decrypt. The data may be damaged or the key is wrong.',
      KeyChanged() => error.toString(),
      FormatException(:final message) => message,
      StateError(:final message) => message,
      ArgumentError(:final message) => '$message',
      _ => 'Something went wrong: $error',
    };

Timer? _clipboardTimer;

Future<void> copySecret(BuildContext context, String value, String label) async {
  final service = context.read<VaultService>();
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: value));
  _clipboardTimer?.cancel();
  final clearAfter = service.clipboardClear;
  if (clearAfter > Duration.zero) {
    _clipboardTimer = Timer(clearAfter, () async {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == value) await Clipboard.setData(const ClipboardData(text: ''));
    });
  }
  messenger.showSnackBar(SnackBar(
    content: Text(clearAfter > Duration.zero
        ? '$label copied. Clipboard clears in ${clearAfter.inSeconds} s.'
        : '$label copied'),
    duration: const Duration(seconds: 2),
  ));
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.showStrength = false,
    this.onGenerate,
    this.validator,
    this.autofocus = false,
    this.onSubmitted,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final bool showStrength;
  final VoidCallback? onGenerate;
  final FormFieldValidator<String>? validator;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: widget.controller,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: false,
      autofocus: widget.autofocus,
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      style: _hidden ? null : const TextStyle(fontFamily: 'monospace'),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
          if (widget.onGenerate != null)
            IconButton(tooltip: 'Generate', icon: const Icon(Icons.casino_outlined), onPressed: widget.onGenerate),
          IconButton(
            tooltip: _hidden ? 'Show' : 'Hide',
            icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _hidden = !_hidden),
          ),
        ]),
      ),
    );
    if (!widget.showStrength) return field;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      field,
      ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => widget.controller.text.isEmpty
            ? const SizedBox(height: 8)
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: StrengthMeter(estimateStrength(widget.controller.text)),
              ),
      ),
    ]);
  }
}

class StrengthMeter extends StatelessWidget {
  const StrengthMeter(this.result, {super.key});

  final StrengthResult result;

  static const labels = ['Very weak', 'Weak', 'Fair', 'Strong', 'Very strong'];

  static Color colorFor(Strength s) => switch (s) {
        Strength.veryWeak => const Color(0xFFC62828),
        Strength.weak => const Color(0xFFEF6C00),
        Strength.fair => const Color(0xFFF9A825),
        Strength.strong => const Color(0xFF2E7D32),
        Strength.veryStrong => const Color(0xFF1B5E20),
      };

  @override
  Widget build(BuildContext context) {
    final color = colorFor(result.level);
    final text = Theme.of(context).textTheme.bodySmall;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: (result.level.index + 1) / labels.length,
          color: color,
          backgroundColor: color.withValues(alpha: 0.15),
          minHeight: 6,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '${labels[result.level.index]} · about ${result.bits.round()} bits'
        '${result.warning == null ? '' : ' · ${result.warning}'}',
        style: text?.copyWith(color: color),
      ),
    ]);
  }
}

class ItemAvatar extends StatelessWidget {
  const ItemAvatar(this.item, {super.key});

  final VaultItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = item.title.trim().isEmpty ? '?' : item.title.trim()[0].toUpperCase();
    return CircleAvatar(
      backgroundColor: item.type == ItemType.note ? scheme.tertiaryContainer : scheme.primaryContainer,
      foregroundColor: item.type == ItemType.note ? scheme.onTertiaryContainer : scheme.onPrimaryContainer,
      child: item.type == ItemType.note ? const Icon(Icons.sticky_note_2_outlined, size: 20) : Text(letter),
    );
  }
}

class ErrorText extends StatelessWidget {
  const ErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
      child: Text(message!, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: scheme.onSecondaryContainer, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(color: scheme.onSecondaryContainer))),
      ]),
    );
  }
}

class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.busy, required this.onPressed, this.busyLabel});

  final String label;
  final String? busyLabel;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        child: busy
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Text(busyLabel ?? label),
              ])
            : Text(label),
      );
}

class FormPage extends StatelessWidget {
  const FormPage({super.key, required this.title, required this.children, this.formKey});

  final String title;
  final List<Widget> children;
  final GlobalKey<FormState>? formKey;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: formKey,
                child: ListView(padding: const EdgeInsets.all(20), children: children),
              ),
            ),
          ),
        ),
      );
}

String? validateEmail(String? v) {
  final value = v?.trim() ?? '';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) return 'Enter a valid email address';
  return null;
}

String? validateMasterPassword(String? v) {
  final value = v ?? '';
  if (value.length < 10) return 'Use at least 10 characters';
  if (!estimateStrength(value).acceptable) return 'Too easy to guess. Try a longer passphrase.';
  return null;
}

const gap = SizedBox(height: 16);
