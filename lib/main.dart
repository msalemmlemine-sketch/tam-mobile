import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'screens/auth_gate.dart';
import 'services/cloud_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تشخيص مؤقت: نسخة release تعرض عادة مربعًا رماديًا فاضيًا عند أي
  // خطأ أثناء البناء، بدل رسالة الخطأ. هذا السطر يجبرها على عرض نص
  // الخطأ الفعلي بدل الفراغ، لمعرفة سبب الشاشة الفاضية بعد الدخول.
  ErrorWidget.builder = (details) => Material(
        color: Colors.red.shade50,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            details.exceptionAsString(),
            style: const TextStyle(color: Colors.red, fontSize: 12),
            textDirection: TextDirection.ltr,
          ),
        ),
      );

  await CloudService.initialize();
  runApp(const TamApp());
}

class TamApp extends StatelessWidget {
  const TamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تام — سجل المنتسبين',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AuthGate(),
    );
  }
}
