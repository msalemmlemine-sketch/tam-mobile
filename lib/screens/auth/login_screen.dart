import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../root_shell.dart';
import 'change_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  final _usernameCtrl = TextEditingController(text: 'admin');
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final outcome = await _auth.login(_usernameCtrl.text, _passwordCtrl.text);
    if (!mounted) return;
    setState(() => _loading = false);

    switch (outcome.result) {
      case LoginResult.success:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RootShell()),
        );
        break;
      case LoginResult.mustChangePassword:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChangePasswordScreen(userId: outcome.user!.id),
          ),
        );
        break;
      case LoginResult.wrongPassword:
        setState(() => _error = 'اسم المستخدم أو كلمة المرور غير صحيحة');
        break;
      case LoginResult.locked:
        setState(() =>
            _error = 'تم قفل الحساب مؤقتًا بسبب محاولات فاشلة متكررة — حاول لاحقًا');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_balance,
                    size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text('نقابة تحالف أساتذة موريتانيا',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'مطلوب' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'كلمة المرور', prefixIcon: Icon(Icons.lock_outline)),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'مطلوب' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('دخول'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
