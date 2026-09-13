import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../models/institution.dart';

class InstitutionRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Institution>> getAll({int? districtId}) async {
    final db = await _db;
    final rows = await db.query(
      'institutions',
      where: districtId != null ? 'district_id = ?' : null,
      whereArgs: districtId != null ? [districtId] : null,
      orderBy: 'name ASC',
    );
    return rows.map(Institution.fromMap).toList();
  }

  Future<Institution?> getById(int id) async {
    final db = await _db;
    final rows =
        await db.query('institutions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Institution.fromMap(rows.first);
  }

  Future<int> create(Institution institution) async {
    final db = await _db;
    return db.insert('institutions', institution.toMap());
  }

  Future<int> update(Institution institution) async {
    final db = await _db;
    return db.update('institutions', institution.toMap(),
        where: 'id = ?', whereArgs: [institution.id]);
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete('institutions', where: 'id = ?', whereArgs: [id]);
  }

  /// عدد المنتسبين في كل مؤسسة — يُستخدم في شاشة إحصائيات المؤسسات.
  Future<int> countMembers(int institutionId) async {
    final db = await _db;
    final result = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM members WHERE institution_id = ? AND is_archived = 0',
      [institutionId],
    ));
    return result ?? 0;
  }
}
