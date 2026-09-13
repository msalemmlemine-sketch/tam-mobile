import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../root_shell.dart';

class ChangePasswordScreen extends StatefulWidget {
  final int userId;
  final bool isForced;
  const ChangePasswordScreen({super.key, required this.userId, this.isForced = true});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _newPassCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await _auth.changePassword(widget.userId, _newPassCtrl.text);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RootShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تغيير كلمة المرور'),
        automaticallyImplyLeading: !widget.isForced,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.isForced)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'يجب تغيير كلمة المرور الافتراضية قبل المتابعة.',
                    textAlign: TextAlign.center,
                  ),
                ),
              TextFormField(
                controller: _newPassCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
                validator: (v) => (v == null || v.length < 6)
                    ? 'يجب أن تكون 6 أحرف على الأقل'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
                validator: (v) =>
                    v != _newPassCtrl.text ? 'كلمتا المرور غير متطابقتين' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
