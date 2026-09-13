import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../repositories/user_repository.dart';
import 'secure_kv_store.dart';

enum LoginResult { success, wrongPassword, locked, mustChangePassword }

/// خدمة الدخول: تجزئة كلمة المرور محليًا (sha256 + salt عشوائي)،
/// قفل الحساب بعد 5 محاولات فاشلة (مطابقةً لاشتراط الأمان)، وحفظ
/// حالة الجلسة عبر [SecureKvStore] — تخزين آمن حقيقي على الجهاز
/// (flutter_secure_storage)، أو تنفيذ وهمي في الذاكرة أثناء
/// اختبارات التكامل (انظر lib/services/secure_kv_store.dart).
class AuthService {
  AuthService({UserRepository? userRepository, SecureKvStore? storage})
      : _users = userRepository ?? UserRepository(),
        _storage = storage ?? FlutterSecureKvStore();

  final UserRepository _users;
  final SecureKvStore _storage;

  static const int maxFailedAttempts = 5;
  static const Duration lockDuration = Duration(minutes: 5);
  static const _sessionKey = 'tam_session_user_id';
  static const _lastActivityKey = 'tam_last_activity';

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt $password')).toString();

  String _generateSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }

  Future<({LoginResult result, AppUser? user})> login(
      String username, String password) async {
    final user = await _users.getByUsername(username.trim());
    if (user == null) {
      return (result: LoginResult.wrongPassword, user: null);
    }

    if (user.lockedUntil != null) {
      final lockedUntil = DateTime.tryParse(user.lockedUntil!);
      if (lockedUntil != null && DateTime.now().isBefore(lockedUntil)) {
        return (result: LoginResult.locked, user: user);
      }
    }

    final computedHash = _hash(password, user.passwordSalt);
    if (computedHash != user.passwordHash) {
      final attempts = user.failedAttempts + 1;
      String? lockedUntil;
      if (attempts >= maxFailedAttempts) {
        lockedUntil = DateTime.now().add(lockDuration).toIso8601String();
      }
      await _users.recordFailedAttempt(user.id, attempts,
          lockedUntil: lockedUntil);
      return (
        result: lockedUntil != null ? LoginResult.locked : LoginResult.wrongPassword,
        user: user,
      );
    }

    await _users.resetFailedAttempts(user.id);
    await _storage.write(_sessionKey, user.id.toString());
    await _touchActivity();

    if (user.mustChangePassword) {
      return (result: LoginResult.mustChangePassword, user: user);
    }
    return (result: LoginResult.success, user: user);
  }

  Future<void> changePassword(int userId, String newPassword) async {
    final salt = _generateSalt();
    final hash = _hash(newPassword, salt);
    await _users.updatePassword(
        userId: userId, passwordHash: hash, passwordSalt: salt);
  }

  Future<void> logout() async {
    await _storage.delete(_sessionKey);
    await _storage.delete(_lastActivityKey);
  }

  Future<bool> hasActiveSession() async {
    final id = await _storage.read(_sessionKey);
    return id != null;
  }

  Future<void> _touchActivity() async {
    await _storage.write(_lastActivityKey, DateTime.now().toIso8601String());
  }

  /// يُستدعى دوريًا (مثلًا عند استئناف التطبيق) للتحقق من قفل
  /// الجلسة بعد مدة خمول اختيارية (بالدقائق).
  Future<bool> isSessionExpired({int idleMinutes = 15}) async {
    final lastActivity = await _storage.read(_lastActivityKey);
    if (lastActivity == null) return true;
    final last = DateTime.tryParse(lastActivity);
    if (last == null) return true;
    return DateTime.now().difference(last) > Duration(minutes: idleMinutes);
  }

  Future<void> refreshActivity() => _touchActivity();
}
