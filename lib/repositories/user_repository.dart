import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';

class AppUser {
  final int id;
  final String username;
  final String passwordHash;
  final String passwordSalt;
  final String displayName;
  final bool mustChangePassword;
  final int failedAttempts;
  final String? lockedUntil;

  const AppUser({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.passwordSalt,
    required this.displayName,
    required this.mustChangePassword,
    required this.failedAttempts,
    this.lockedUntil,
  });

  factory AppUser.fromMap(Map<String, Object?> map) => AppUser(
        id: map['id'] as int,
        username: map['username'] as String,
        passwordHash: map['password_hash'] as String,
        passwordSalt: map['password_salt'] as String,
        displayName: map['display_name'] as String,
        mustChangePassword: (map['must_change_password'] as int) == 1,
        failedAttempts: map['failed_attempts'] as int? ?? 0,
        lockedUntil: map['locked_until'] as String?,
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
}
