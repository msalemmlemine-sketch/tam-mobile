import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tam_mobile/services/auth_service.dart';
import 'package:tam_mobile/services/secure_kv_store.dart';

import 'test_helper.dart';

void main() {
  late Directory tempDir;
  late AuthService auth;

  setUp(() async {
    tempDir = await openFreshTestDatabase();
    // تخزين آمن وهمي في الذاكرة بدل flutter_secure_storage الحقيقي
    // (الذي يحتاج قناة منصّة غير متوفرة في اختبار Dart عادي) — لكن
    // بقية طبقة AuthService/UserRepository حقيقية بالكامل فوق
    // قاعدة بيانات SQLite حقيقية.
    auth = AuthService(storage: InMemorySecureKvStore());
  });

  tearDown(() async {
    await closeTestDatabase(tempDir);
  });

  test('المستخدم الافتراضي admin/admin123 يسجّل الدخول ويُطلَب منه تغيير كلمة المرور',
      () async {
    final outcome = await auth.login('admin', 'admin123');
    expect(outcome.result, LoginResult.mustChangePassword);
    expect(outcome.user, isNotNull);
    expect(await auth.hasActiveSession(), isTrue);
  });

  test('كلمة مرور خاطئة تُرفَض ولا تُنشئ جلسة', () async {
    final outcome = await auth.login('admin', 'كلمة خاطئة');
    expect(outcome.result, LoginResult.wrongPassword);
    expect(await auth.hasActiveSession(), isFalse);
  });

  test('تغيير كلمة المرور يسمح بتسجيل دخول ناجح كامل لاحقًا بلا إجبار على التغيير',
      () async {
    final first = await auth.login('admin', 'admin123');
    await auth.changePassword(first.user!.id, 'كلمة_جديدة_قوية');

    final second = await auth.login('admin', 'كلمة_جديدة_قوية');
    expect(second.result, LoginResult.success);

    // كلمة المرور القديمة لم تعد صالحة بعد التغيير.
    final oldAttempt = await auth.login('admin', 'admin123');
    expect(oldAttempt.result, LoginResult.wrongPassword);
  });

  test('5 محاولات فاشلة متتالية تقفل الحساب مؤقتًا، وحتى كلمة المرور الصحيحة تُرفَض أثناء القفل',
      () async {
    for (var i = 0; i < 4; i++) {
      final outcome = await auth.login('admin', 'خطأ');
      expect(outcome.result, LoginResult.wrongPassword);
    }
    final fifthAttempt = await auth.login('admin', 'خطأ');
    expect(fifthAttempt.result, LoginResult.locked);

    final correctButLocked = await auth.login('admin', 'admin123');
    expect(correctButLocked.result, LoginResult.locked);
  });

  test('تسجيل الخروج يُنهي الجلسة فعليًا', () async {
    await auth.login('admin', 'admin123');
    expect(await auth.hasActiveSession(), isTrue);
    await auth.logout();
    expect(await auth.hasActiveSession(), isFalse);
  });
}
