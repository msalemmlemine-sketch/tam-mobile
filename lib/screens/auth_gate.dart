import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'auth/login_screen.dart';
import 'root_shell.dart';

/// يقرر عند فتح التطبيق: هل هناك جلسة نشطة (يذهب للواجهة الرئيسية)
/// أم يجب تسجيل الدخول من جديد (لا توجد جلسة، أو انتهت بسبب الخمول).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final _auth = AuthService();
  late Future<bool> _sessionValid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionValid = _check();
  }

  Future<bool> _check() async {
    final hasSession = await _auth.hasActiveSession();
    if (!hasSession) return false;
    final expired = await _auth.isSessionExpired();
    if (expired) {
      await _auth.logout();
      return false;
    }
    await _auth.refreshActivity();
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _sessionValid = _check());
    } else if (state == AppLifecycleState.paused) {
      _auth.refreshActivity();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _sessionValid,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data! ? const RootShell() : const LoginScreen();
      },
    );
  }
}
