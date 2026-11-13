import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vault_item.dart';
import '../../services/vault_service.dart';
import '../generator/generator_screen.dart';
import '../widgets/common.dart';

class ItemEditScreen extends StatefulWidget {
  const ItemEditScreen({super.key, this.existing, this.newType = ItemType.login});

  final VaultItem? existing;
  final ItemType newType;

  @override
  State<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends State<ItemEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _username = TextEditingController(text: widget.existing?.username);
  late final _password = TextEditingController(text: widget.existing?.password);
  late final _url = TextEditingController(text: widget.existing?.url);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late ItemType _type = widget.existing?.type ?? widget.newType;
  bool _busy = false;

  Future<void> _generate() async {
    final value = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const GeneratorScreen(picking: true)));
    if (value != null) _password.text = value;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final service = context.read<VaultService>();
    final base = widget.existing ??
        VaultItem(id: service.repo.newId(), modifiedAt: DateTime.now());
    try {
      await service.save(base.copyWith(
        type: _type,
        title: _title.text.trim(),
        username: _type == ItemType.login ? _username.text.trim() : '',
        password: _type == ItemType.login ? _password.text : '',
        url: _type == ItemType.login ? _url.text.trim() : '',
        notes: _notes.text,
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return FormPage(
      title: isNew ? (_type == ItemType.login ? 'New login' : 'New note') : 'Edit',
      formKey: _form,
      children: [
        if (isNew) ...[
          SegmentedButton<ItemType>(
            segments: const [
              ButtonSegment(value: ItemType.login, icon: Icon(Icons.password), label: Text('Login')),
              ButtonSegment(value: ItemType.note, icon: Icon(Icons.sticky_note_2_outlined), label: Text('Note')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          gap,
        ],
        TextFormField(
          controller: _title,
          autofocus: isNew,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Title'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Give it a name' : null,
        ),
        gap,
        if (_type == ItemType.login) ...[
          TextFormField(
            controller: _username,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Username or email'),
          ),
          gap,
          PasswordField(controller: _password, showStrength: true, onGenerate: _generate),
          gap,
          TextFormField(
            controller: _url,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Website', hintText: 'example.com'),
          ),
          gap,
        ],
        TextFormField(
          controller: _notes,
          minLines: _type == ItemType.note ? 8 : 3,
          maxLines: 20,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Notes', alignLabelWithHint: true),
        ),
        const SizedBox(height: 24),
        BusyButton(label: 'Save', busy: _busy, onPressed: _save),
      ],
    );
  }
}
