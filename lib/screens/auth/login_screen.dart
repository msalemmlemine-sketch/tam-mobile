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
  bool _obscure = true;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    final outcome = await _auth.login(_usernameCtrl.text.trim(), _passwordCtrl.text);
    if (!mounted) return;
    setState(() => _loading = false);
    switch (outcome.result) {
      case LoginResult.success:
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RootShell()));
        break;
      case LoginResult.mustChangePassword:
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChangePasswordScreen(userId: outcome.user!.id)));
        break;
      case LoginResult.wrongPassword:
        setState(() => _error = 'اسم المستخدم أو كلمة المرور غير صحيحة');
        break;
      case LoginResult.locked:
        setState(() => _error = 'تم قفل الحساب مؤقتًا بسبب محاولات فاشلة متكررة — حاول لاحقًا');
        break;
    }
  }

  @override
  void dispose() { _usernameCtrl.dispose(); _passwordCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                    child: ClipOval(child: Image.asset('assets/icon.png', fit: BoxFit.cover)),
                  ),
                  const SizedBox(height: 20),
                  Text('سجل تحالف أساتذة موريتانيا', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('إدارة المنتسبين والاشتراكات والصندوق', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _usernameCtrl,
                              textDirection: TextDirection.ltr,
                              decoration: const InputDecoration(labelText: 'اسم المستخدم أو الدليل المالي', prefixIcon: Icon(Icons.person_outline)),
                              validator: (v) => v == null || v.trim().isEmpty ? 'أدخل اسم المستخدم' : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordCtrl,
                              obscureText: _obscure,
                              textDirection: TextDirection.ltr,
                              decoration: InputDecoration(labelText: 'كلمة المرور', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
                              validator: (v) => v == null || v.isEmpty ? 'أدخل كلمة المرور' : null,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(14)), child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer))),
                            ],
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _loading ? null : _submit,
                              icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login_rounded),
                              label: Text(_loading ? 'جارٍ التحقق...' : 'تسجيل الدخول'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('بياناتك محفوظة محليًا على الجهاز', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
