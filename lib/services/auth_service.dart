import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_role.dart';
import '../core/database/app_database.dart';
import '../repositories/user_repository.dart';
import 'cloud_config.dart';
import 'permission_service.dart';
import 'secure_kv_store.dart';
import 'supabase_service.dart';
import 'cloud_realtime_sync.dart';
import 'cloud_sync_engine.dart';

enum LoginResult { success, wrongPassword, locked, mustChangePassword }

/// دخول مركزي عبر Supabase Auth عند تفعيل السحابة، مع إبقاء الدخول
/// المحلي كخطة توافق فقط عندما يكون البناء غير متصل بالسحابة.
class AuthService {
  AuthService({UserRepository? userRepository, SecureKvStore? storage})
      : _users = userRepository ?? UserRepository(),
        _storage = storage ?? FlutterSecureKvStore();

  final UserRepository _users;
  final SecureKvStore _storage;
  static const _sessionKey = 'tam_session_user_id';
  static const _lastActivityKey = 'tam_last_activity';

  /// آخر رسالة خطأ تقنية حقيقية (وليست الرسالة المبسّطة للمستخدم).
  /// تُستخدم مؤقتًا لتشخيص مشاكل تسجيل الدخول أثناء التطوير — يمكن
  /// عرضها في واجهة تسجيل الدخول كنص صغير تحت الرسالة العادية.
  String? lastError;

  String _emailForUsername(String value) {
    final v = value.trim().toLowerCase();
    return v.contains('@') ? v : '$v@tam.local';
  }

  /// يحدد إن كان الاستثناء ناتجًا عن تعذّر الوصول إلى الشبكة/الخادم
  /// (بلا إنترنت، DNS، مهلة اتصال، Supabase غير قابل للوصول) بدل
  /// خطأ حقيقي متعلق ببيانات الدخول نفسها. فقط في هذه الحالة نلجأ
  /// لمسار الدخول المحلي كخطة بديلة — أي فشل آخر (بيانات خاطئة،
  /// حساب مؤكَّد بشكل خاطئ، إلخ) يجب أن يبقى بلا تجاوز إلى المحلي.
  bool _isNetworkFailure(Object e) {
    if (e is AuthRetryableFetchException) return true; // فشل شبكة من supabase_flutter نفسها
    if (e is SocketException) return true;
    if (e is TimeoutException) return true;
    if (e is HttpException) return true;
    // بعض حزم الشبكة (dio/http) ترمي أنواعًا أخرى لا تُصنَّف ضمن ما
    // سبق؛ نتحقق أيضًا من نص الخطأ كخط دفاع أخير غير مثالي لكنه
    // عملي وآمن (لا يُسقِط بيانات دخول خاطئة كفشل شبكة لأن رسائل
    // Supabase لبيانات الدخول الخاطئة لا تحتوي هذه العبارات).
    final text = e.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('connection timed out') ||
        text.contains('timeoutexception') ||
        text.contains('clientexception');
  }

  Future<({LoginResult result, AppUser? user})> login(
      String username, String password) async {
    lastError = null;
    if (CloudConfig.enabled) {
      try {
        final res = await SupabaseService.client.auth.signInWithPassword(
          email: _emailForUsername(username),
          password: password,
        );
        final authUser = res.user;
        if (authUser == null) {
          lastError = 'Supabase لم يُرجع مستخدمًا بعد signInWithPassword (بلا استثناء).';
          return (result: LoginResult.wrongPassword, user: null);
        }
        final user = await _loadCloudProfile(authUser.id);
        if (user == null || !user.isActive) {
          lastError = user == null
              ? 'تم الدخول في Supabase Auth لكن لا يوجد صف مطابق في جدول profiles لهذا المستخدم (${authUser.id}).'
              : 'الحساب موجود لكنه معطّل (is_active = false).';
          await SupabaseService.client.auth.signOut();
          return (result: LoginResult.locked, user: user);
        }
        await _storage.write(_sessionKey, user.id.toString());
        await _touchActivity();
        PermissionService.currentUser = user;
        await CloudRealtimeSync.instance.start();
        await CloudSyncEngine().sync();
        if (user.mustChangePassword) {
          return (result: LoginResult.mustChangePassword, user: user);
        }
        return (result: LoginResult.success, user: user);
      } on AuthException catch (e) {
        // خطأ صادر فعليًا عن منطق المصادقة في Supabase (بيانات دخول
        // خاطئة، بريد غير مؤكَّد، مستخدم غير موجود). هذا ليس فشل
        // شبكة، فلا داعي لتجربة الدخول المحلي — الخطأ حقيقي ويجب
        // إظهاره كما هو.
        lastError = 'AuthException: ${e.message} (status: ${e.statusCode})';
        return (result: LoginResult.wrongPassword, user: null);
      } catch (e) {
        if (!_isNetworkFailure(e)) {
          // خطأ غير متوقع لكنه ليس فشل شبكة واضحًا (مثل خطأ برمجي
          // داخلي) — نُبقي السلوك القديم بإرجاع فشل فورًا بدل
          // إخفائه خلف مسار محلي قد يُخفي علة حقيقية.
          lastError = '${e.runtimeType}: $e';
          return (result: LoginResult.wrongPassword, user: null);
        }
        // فشل شبكة فعلي (لا إنترنت، DNS، مهلة اتصال، إلخ): هذا هو
        // الإصلاح الجوهري — بدل إرجاع فشل فوري بلا أي محاولة أخرى،
        // ننتقل تلقائيًا لمسار الدخول المحلي عبر SQLite أدناه، بنفس
        // الأسلوب المستخدم أصلًا في وضع "السحابة معطّلة كليًا".
        lastError = 'فشل الاتصال بالشبكة (${e.runtimeType}: $e) — المتابعة بالدخول المحلي.';
      }
    }

    // وضع الدخول المحلي — يُستخدم إما لأن السحابة معطّلة كليًا في
    // هذا البناء، أو لأن محاولة الدخول السحابي فشلت بسبب انعدام
    // الشبكة تحديدًا (انظر الفرع أعلاه).
    final user = await _users.getByUsername(username.trim());
    if (user == null) {
      lastError ??= 'لا يوجد مستخدم محلي بهذا الاسم في SQLite.';
      return (result: LoginResult.wrongPassword, user: null);
    }
    if (!user.isActive) {
      lastError = 'الحساب معطّل محليًا (is_active = false).';
      return (result: LoginResult.locked, user: user);
    }
    final ok = await _users.verifyLocalPassword(user, password);
    if (!ok) {
      lastError = 'كلمة المرور المحلية غير مطابقة (SQLite).';
      return (result: LoginResult.wrongPassword, user: user);
    }
    await _storage.write(_sessionKey, user.id.toString());
    await _touchActivity();
    PermissionService.currentUser = user;
    return (
      result: user.mustChangePassword
          ? LoginResult.mustChangePassword
          : LoginResult.success,
      user: user,
    );
  }

  Future<AppUser?> _loadCloudProfile(String authId) async {
    final row = await SupabaseService.client
        .from('profiles')
        .select('id,username,display_name,role,member_id,member_sync_uuid,is_active,must_change_password')
        .eq('id', authId)
        .maybeSingle();
    if (row == null) return null;
    int? localMemberId = row['member_id'] as int?;
    final memberSync = row['member_sync_uuid'] as String?;
    if (localMemberId == null && memberSync != null) {
      final db = await AppDatabase.instance.database;
      final member = await db.query('members', where: 'sync_uuid = ?', whereArgs: [memberSync], limit: 1);
      if (member.isNotEmpty) localMemberId = member.first['id'] as int;
    }
    return _users.cacheCloudUser(
      cloudUserId: authId,
      username: (row['username'] as String?) ?? authId,
      displayName: (row['display_name'] as String?) ?? '',
      role: AppRoleX.fromKey(row['role'] as String?),
      memberId: localMemberId,
      isActive: row['is_active'] as bool? ?? true,
      mustChangePassword: row['must_change_password'] as bool? ?? false,
    );
  }

  Future<void> changePassword(int userId, String newPassword) async {
    if (CloudConfig.enabled) {
      await SupabaseService.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      final authId = SupabaseService.user?.id;
      if (authId != null) {
        await SupabaseService.client
            .from('profiles')
            .update({'must_change_password': false})
            .eq('id', authId);
      }
      if (PermissionService.currentUser != null) {
        final u = PermissionService.currentUser!;
        PermissionService.currentUser = AppUser(
          id: u.id, username: u.username, passwordHash: u.passwordHash,
          passwordSalt: u.passwordSalt, displayName: u.displayName, role: u.role,
          mustChangePassword: false, failedAttempts: u.failedAttempts,
          lockedUntil: u.lockedUntil, memberId: u.memberId,
          cloudUserId: u.cloudUserId, isActive: u.isActive,
        );
      }
      return;
    }
    await _users.updateLocalPassword(userId, newPassword);
  }

  Future<void> logout() async {
    if (CloudConfig.enabled && SupabaseService.session != null) {
      try {
        await SupabaseService.client.auth.signOut();
      } catch (_) {
        // بلا إنترنت: لا نمنع الخروج المحلي بسبب فشل استدعاء الشبكة.
      }
    }
    PermissionService.currentUser = null;
    await _storage.delete(_sessionKey);
    await _storage.delete(_lastActivityKey);
  }

  /// المستخدم المحفوظ محلياً من آخر دخول ناجح — يُستخدم كخطة بديلة
  /// عندما لا يمكن الوصول إلى Supabase (بلا إنترنت).
  Future<AppUser?> _cachedUser() async {
    final id = await _storage.read(_sessionKey);
    final userId = int.tryParse(id ?? '');
    if (userId == null) return null;
    final user = await _users.getById(userId);
    PermissionService.currentUser = user;
    return user;
  }

  Future<AppUser?> currentUser() async {
    if (CloudConfig.enabled) {
      final authUser = SupabaseService.user;
      if (authUser != null) {
        try {
          final user = await _loadCloudProfile(authUser.id);
          PermissionService.currentUser = user;
          return user;
        } catch (_) {
          // بلا إنترنت: نرجع للمستخدم المحفوظ محلياً بدل تعليق الشاشة.
        }
      }
      return _cachedUser();
    }
    return _cachedUser();
  }

  Future<bool> hasActiveSession() async {
    if (CloudConfig.enabled) {
      if (SupabaseService.session != null) return true;
      // جلسة Supabase قد تكون غير مُهيَّأة بعد بسبب غياب الإنترنت
      // عند بدء التشغيل؛ نعتمد على وجود مستخدم محفوظ محلياً بدلاً
      // من اعتبار الجهاز بلا جلسة على الإطلاق.
      return (await _storage.read(_sessionKey)) != null;
    }
    return (await _storage.read(_sessionKey)) != null;
  }

  Future<void> _touchActivity() async =>
      _storage.write(_lastActivityKey, DateTime.now().toIso8601String());

  Future<bool> isSessionExpired({int idleMinutes = 15}) async {
    // Supabase نفسها تدير صلاحية access/refresh token. هذا الاختبار
    // يمنع ترك واجهة الحساب مفتوحة بلا نشاط فترة طويلة.
    final lastActivity = await _storage.read(_lastActivityKey);
    if (lastActivity == null) return false;
    final last = DateTime.tryParse(lastActivity);
    if (last == null) return false;
    return DateTime.now().difference(last) > Duration(minutes: idleMinutes);
  }

  Future<void> refreshActivity() => _touchActivity();
}
