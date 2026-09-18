import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../models/app_role.dart';

class AppUser {
  final int id;
  final String username;
  final String passwordHash;
  final String passwordSalt;
  final String displayName;
  final AppRole role;
  final bool mustChangePassword;
  final int failedAttempts;
  final String? lockedUntil;
  final int? memberId;
  final String? cloudUserId;
  final bool isActive;

  const AppUser({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.passwordSalt,
    required this.displayName,
    this.role = AppRole.organizationSecretary,
    required this.mustChangePassword,
    required this.failedAttempts,
    this.lockedUntil,
    this.memberId,
    this.cloudUserId,
    this.isActive = true,
  });

  factory AppUser.fromMap(Map<String, Object?> map) => AppUser(
        id: map['id'] as int,
        username: map['username'] as String,
        passwordHash: map['password_hash'] as String,
        passwordSalt: map['password_salt'] as String,
        displayName: map['display_name'] as String,
        role: AppRoleX.fromKey(map['role'] as String?),
        mustChangePassword: (map['must_change_password'] as int) == 1,
        failedAttempts: map['failed_attempts'] as int? ?? 0,
        lockedUntil: map['locked_until'] as String?,
        memberId: map['member_id'] as int?,
        cloudUserId: map['cloud_user_id'] as String?,
        isActive: (map['is_active'] as int? ?? 1) == 1,
      );
}

class UserRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<AppUser?> getByUsername(String username) async {
    final db = await _db;
    final rows =
        await db.query('users', where: 'username = ?', whereArgs: [username]);
    if (rows.isEmpty) return null;
    return AppUser.fromMap(rows.first);
  }


  Future<AppUser?> getById(int id) async {
    final db = await _db;
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return AppUser.fromMap(rows.first);
  }

  Future<void> recordFailedAttempt(int userId, int attempts,
      {String? lockedUntil}) async {
    final db = await _db;
    await db.update(
      'users',
      {'failed_attempts': attempts, 'locked_until': lockedUntil},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> resetFailedAttempts(int userId) async {
    final db = await _db;
    await db.update(
      'users',
      {'failed_attempts': 0, 'locked_until': null},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> updatePassword({
    required int userId,
    required String passwordHash,
    required String passwordSalt,
  }) async {
    final db = await _db;
    await db.update(
      'users',
      {
        'password_hash': passwordHash,
        'password_salt': passwordSalt,
        'must_change_password': 0,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<bool> verifyLocalPassword(AppUser user, String password) async {
    final salt = user.passwordSalt;
    final hash = _hash(password, salt);
    return hash == user.passwordHash;
  }

  Future<void> updateLocalPassword(int userId, String password) async {
    final salt = _generateSalt();
    await updatePassword(
      userId: userId,
      passwordHash: _hash(password, salt),
      passwordSalt: salt,
    );
  }

  Future<AppUser> cacheCloudUser({
    required String cloudUserId,
    required String username,
    required String displayName,
    required AppRole role,
    int? memberId,
    bool isActive = true,
    bool mustChangePassword = false,
  }) async {
    final db = await _db;
    final existing = await db.query(
      'users',
      where: 'cloud_user_id = ?',
      whereArgs: [cloudUserId],
      limit: 1,
    );
    final now = DateTime.now().toIso8601String();
    if (existing.isEmpty) {
      final salt = _generateSalt();
      final id = await db.insert('users', {
        'username': username,
        'password_hash': _hash('', salt),
        'password_salt': salt,
        'display_name': displayName,
        'role': role.key,
        'must_change_password': mustChangePassword ? 1 : 0,
        'failed_attempts': 0,
        'locked_until': null,
        'member_id': memberId,
        'cloud_user_id': cloudUserId,
        'is_active': isActive ? 1 : 0,
        'created_at': now,
      });
      return (await getById(id))!;
    }
    final id = existing.first['id'] as int;
    await db.update('users', {
      'username': username,
      'display_name': displayName,
      'role': role.key,
      'must_change_password': mustChangePassword ? 1 : 0,
      'member_id': memberId,
      'is_active': isActive ? 1 : 0,
    }, where: 'id = ?', whereArgs: [id]);
    return (await getById(id))!;
  }


  Future<AppUser?> getByMemberId(int memberId) async {
    final db = await _db;
    final rows = await db.query('users', where: 'member_id = ?', whereArgs: [memberId], limit: 1);
    if (rows.isEmpty) return null;
    return AppUser.fromMap(rows.first);
  }

  static String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt $password')).toString();

  static String _generateSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// يضمن وجود حساب دخول ذاتي للمنتسب — يُستدعى تلقائيًا عند إضافة
  /// منتسب أو تعديله (من MemberRepository)، وليس عملية يدوية.
  ///
  /// - عند الإنشاء الأول: اسم المستخدم = الدليل المالي، كلمة المرور =
  ///   رقم الهاتف (مُجزّأة بنفس آلية AuthService)، والدور "منتسب".
  /// - عند أي استدعاء لاحق: يُحدَّث اسم المستخدم فقط إن تغيّر الدليل
  ///   المالي — لا تُلمَس كلمة المرور مطلقًا حتى لا نُلغي تغييرًا
  ///   يدويًا قام به المنتسب لاحقًا عبر "تغيير كلمة المرور".
  /// - إن كان الدليل المالي أو الهاتف فارغَين عند الإنشاء الأول، لا
  ///   يُنشأ حساب حتى تتوفر البيانات لاحقًا.
  /// - أي تعارض (دليل مالي مكرر بالخطأ بين منتسبَين) يُتجاهل بصمت
  ///   حتى لا يمنع حفظ بيانات المنتسب نفسها.
  Future<void> ensureMemberAccount({
    required int memberId,
    required String displayName,
    String? guide,
    String? phone,
  }) async {
    final cleanGuide = guide?.trim();
    if (cleanGuide == null || cleanGuide.isEmpty) return;

    final db = await _db;
    try {
      final existing = await getByMemberId(memberId);
      if (existing == null) {
        final cleanPhone = phone?.trim();
        if (cleanPhone == null || cleanPhone.isEmpty) return;
        final salt = _generateSalt();
        await db.insert('users', {
          'username': cleanGuide,
          'password_hash': _hash(cleanPhone, salt),
          'password_salt': salt,
          'display_name': displayName,
          'role': AppRole.member.key,
          'must_change_password': 0,
          'failed_attempts': 0,
          'member_id': memberId,
          'created_at': DateTime.now().toIso8601String(),
        });
      } else if (existing.username != cleanGuide || existing.displayName != displayName) {
        await db.update(
          'users',
          {'username': cleanGuide, 'display_name': displayName},
          where: 'id = ?',
          whereArgs: [existing.id],
        );
      }
    } catch (_) {
      // تعارض اسم مستخدم أو أي خطأ غير متوقع — لا يجب أن يمنع حفظ المنتسب.
    }
  }
}
