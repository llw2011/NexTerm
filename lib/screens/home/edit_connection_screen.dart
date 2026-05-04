import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/connection.dart';
import '../../providers/connections_provider.dart';
import '../../utils/secure_storage.dart';

class EditConnectionScreen extends StatefulWidget {
  final ConnectionType type;
  final Connection? existing;
  const EditConnectionScreen({super.key, required this.type, this.existing});

  @override
  State<EditConnectionScreen> createState() => _EditConnectionScreenState();
}

class _EditConnectionScreenState extends State<EditConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _host, _port, _user, _pass, _domain;
  bool _obscurePass = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name   = TextEditingController(text: e?.name ?? '');
    _host   = TextEditingController(text: e?.host ?? '');
    _port   = TextEditingController(
        text: (e?.port ?? (widget.type == ConnectionType.rdp ? 3389 : 22)).toString());
    _user   = TextEditingController(text: e?.username ?? '');
    _pass   = TextEditingController();
    _domain = TextEditingController(text: e?.domain ?? '');
    if (e != null) _loadPassword(e.id);
  }

  Future<void> _loadPassword(String id) async {
    _pass.text = await loadPassword(id);
  }

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _user, _pass, _domain]) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRdp = widget.type == ConnectionType.rdp;
    final isEdit = widget.existing != null;

    return Scaffold(
      appBar: AppBar(title: Text('${isEdit ? 'Edit' : 'New'} ${isRdp ? 'RDP' : 'SSH'}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _field(_name, 'Display Name', Icons.label_outline, required: true),
            const SizedBox(height: 12),
            _field(_host, 'Host / IP', Icons.dns_outlined, required: true),
            const SizedBox(height: 12),
            _field(_port, 'Port', Icons.numbers, numeric: true, required: true),
            const SizedBox(height: 12),
            _field(_user, 'Username', Icons.person_outline, required: true),
            const SizedBox(height: 12),
            _passwordField(),
            const SizedBox(height: 12),
            if (isRdp) ...[
              _field(_domain, 'Domain (optional)', Icons.business_outlined),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(isEdit ? 'Save' : 'Add Connection'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool required = false,
    bool numeric = false,
  }) =>
      TextFormField(
        controller: ctrl,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        inputFormatters: numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
      );

  Widget _passwordField() => TextFormField(
        controller: _pass,
        obscureText: _obscurePass,
        decoration: InputDecoration(
          labelText: 'Password',
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscurePass = !_obscurePass),
          ),
        ),
      );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final id = widget.existing?.id ?? const Uuid().v4();
    final conn = Connection(
      id: id,
      name: _name.text.trim(),
      host: _host.text.trim(),
      port: int.parse(_port.text),
      username: _user.text.trim(),
      type: widget.type,
      domain: _domain.text.trim().isEmpty ? null : _domain.text.trim(),
    );
    await savePassword(id, _pass.text);
    if (!mounted) return;
    final provider = context.read<ConnectionsProvider>();
    if (widget.existing != null) {
      provider.update(conn);
    } else {
      provider.add(conn);
    }
    context.pop();
  }
}
