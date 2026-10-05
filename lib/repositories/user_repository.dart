import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/database/app_database.dart';
import '../models/app_role.dart';
import '../services/cloud_config.dart';

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
    final rows =
        await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return AppUser.fromMap(rows.first);
  }

  /// كل الحسابات — تُستخدم من شاشة إدارة الحسابات (المدير فقط).
  /// الحسابات الإدارية أولًا ثم المنتسبون، وأبجديًا داخل كل مجموعة.
  Future<List<AppUser>> getAll() async {
    final db = await _db;
    final rows = await db.query('users',
        orderBy: 'role = "member" ASC, display_name COLLATE NOCASE ASC');
    return rows.map(AppUser.fromMap).toList();
  }

  /// يجلب كل الحسابات من Supabase (للأدمن فقط بفضل السياسة
  /// profiles_select_admin) ويخزّنها محليًا لتظهر في شاشة الحسابات.
  Future<void> syncProfilesFromCloud() async {
    if (!CloudConfig.enabled) return;
    final rows = await Supabase.instance.client.from('profiles').select(
        'id,username,display_name,role,member_sync_uuid,is_active,must_change_password');
    final db = await _db;
    for (final r in rows) {
      final username = r['username'] as String?;
      if (username == null || username.isEmpty) continue;
      int? localMemberId;
      final memberSync = r['member_sync_uuid'] as String?;
      if (memberSync != null) {
        final m = await db.query('members',
            where: 'sync_uuid = ?', whereArgs: [memberSync], limit: 1);
        if (m.isNotEmpty) localMemberId = m.first['id'] as int;
      }
      try {
        await cacheCloudUser(
          cloudUserId: r['id'] as String,
          username: username,
          displayName: (r['display_name'] as String?) ?? username,
          role: AppRoleX.fromKey(r['role'] as String?),
          memberId: localMemberId,
          isActive: r['is_active'] as bool? ?? true,
          mustChangePassword: r['must_change_password'] as bool? ?? false,
        );
      } catch (_) {
        // صف واحد معطوب لا يوقف بقية المزامنة.
      }
    }
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

  Future<void> clearMustChangePassword(int userId) async {
    final db = await _db;
    await db.update('users', {'must_change_password': 0},
        where: 'id = ?', whereArgs: [userId]);
  }

  Future<bool> verifyLocalPassword(AppUser user, String password) async {
    final hash = _hash(password, user.passwordSalt);
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

  /// تفعيل/تعطيل حساب: يُكتب في السحابة أولًا ثم محليًا.
  Future<void> setActive(int userId, bool isActive) async {
    final u = await getById(userId);
    if (CloudConfig.enabled && u?.cloudUserId != null) {
      final res = await Supabase.instance.client
          .from('profiles')
          .update({'is_active': isActive})
          .eq('id', u!.cloudUserId!)
          .select();
      if (res.isEmpty) {
        throw Exception('رفضت السحابة التعديل (تحقق من صلاحية الأدمن).');
      }
    }
    final db = await _db;
    await db.update('users', {'is_active': isActive ? 1 : 0},
        where: 'id = ?', whereArgs: [userId]);
  }

  /// تغيير الدور: يُكتب في السحابة أولًا، وإن رفضته يُرمى استثناء
  /// فلا يبدو التغيير ناجحًا محليًا فقط.
  Future<void> updateRole(int userId, AppRole role) async {
    final u = await getById(userId);
    if (CloudConfig.enabled && u?.cloudUserId != null) {
      final res = await Supabase.instance.client
          .from('profiles')
          .update({'role': role.key})
          .eq('id', u!.cloudUserId!)
          .select();
      if (res.isEmpty) {
        throw Exception('رفضت السحابة التعديل (تحقق من صلاحية الأدمن).');
      }
    }
    final db = await _db;
    await db.update('users', {'role': role.key},
        where: 'id = ?', whereArgs: [userId]);
  }

  /// حذف فعلي للحساب المحلي فقط. لا يُستخدم في وضع السحابة؛
  /// استخدم setActive بدلًا منه.
  Future<void> deleteLocalUser(int userId) async {
    final db = await _db;
    await db.delete('users', where: 'id = ?', whereArgs: [userId]);
  }

  Future<AppUser> createLocalUser({
    required String username,
    required String password,
    required String displayName,
    required AppRole role,
    int? memberId,
    bool mustChangePassword = true,
  }) async {
    final db = await _db;
    final salt = _generateSalt();
    final id = await db.insert('users', {
      'username': username.trim(),
      'password_hash': _hash(password, salt),
      'password_salt': salt,
      'display_name': displayName.trim(),
      'role': role.key,
      'must_change_password': mustChangePassword ? 1 : 0,
      'failed_attempts': 0,
      'member_id': memberId,
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
    return (await getById(id))!;
  }

  /// يُنشئ أو يُحدِّث نسخة محلية لمستخدم مُصادَق عليه عبر Supabase.
  /// البحث بـ cloud_user_id أولًا ثم بـ username.
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
    var existing = await db.query(
      'users',
      where: 'cloud_user_id = ?',
      whereArgs: [cloudUserId],
      limit: 1,
    );
    if (existing.isEmpty) {
      existing = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: [username],
        limit: 1,
      );
    }
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
      'member_id': memberId ?? existing.first['member_id'],
      'cloud_user_id': cloudUserId,
      'is_active': isActive ? 1 : 0,
    }, where: 'id = ?', whereArgs: [id]);
    return (await getById(id))!;
  }

  Future<AppUser?> getByMemberId(int memberId) async {
    final db = await _db;
    final rows = await db.query('users',
        where: 'member_id = ?', whereArgs: [memberId], limit: 1);
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

  /// يضمن وجود حساب دخول ذاتي للمنتسب (اسم المستخدم = الدليل المالي،
  /// كلمة المرور الأولى = الهاتف، الدور member). لا يلمس كلمة المرور
  /// عند الاستدعاءات اللاحقة.
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
          'must_change_password': 1,
          'failed_attempts': 0,
          'member_id': memberId,
          'created_at': DateTime.now().toIso8601String(),
        });
      } else if (existing.username != cleanGuide ||
          existing.displayName != displayName) {
        await db.update(
          'users',
          {'username': cleanGuide, 'display_name': displayName},
          where: 'id = ?',
          whereArgs: [existing.id],
        );
      }
    } catch (_) {
      // تعارض اسم مستخدم أو خطأ غير متوقع: لا يمنع حفظ المنتسب.
    }
  }
}
