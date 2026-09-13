import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../models/district.dart';

class DistrictRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<District>> getAll() async {
    final db = await _db;
    final rows =
        await db.query('districts', orderBy: 'sort_order ASC, name ASC');
    return rows.map(District.fromMap).toList();
  }

  Future<District?> getById(int id) async {
    final db = await _db;
    final rows = await db.query('districts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return District.fromMap(rows.first);
  }

  Future<int> create(District district) async {
    final db = await _db;
    return db.insert('districts', district.toMap());
  }

  Future<int> update(District district) async {
    final db = await _db;
    return db.update('districts', district.toMap(),
        where: 'id = ?', whereArgs: [district.id]);
  }

  /// يفشل بخطأ FK إن كانت هناك مؤسسات مرتبطة — سلوك مقصود لمنع
  /// حذف مقاطعة بها بيانات (Soft-guard عبر ON DELETE RESTRICT).
  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete('districts', where: 'id = ?', whereArgs: [id]);
  }
}
