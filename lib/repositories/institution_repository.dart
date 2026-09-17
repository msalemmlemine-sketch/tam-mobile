import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../services/drive_sync_service.dart';
import '../services/sync_outbox.dart';
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
    final rows = await db.query('institutions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Institution.fromMap(rows.first);
  }

  Future<int> create(Institution institution) async {
    final db = await _db;
    final id = await db.insert('institutions', institution.toMap());
    await const SyncOutbox().enqueueUpsert(
      db: db,
      table: 'institutions',
      localRowId: id,
      row: (await db.query('institutions', where: 'id = ?', whereArgs: [id])).first,
    );
    await DriveSyncService().markDirty();
    return id;
  }

  Future<int> update(Institution institution) async {
    final db = await _db;
    final count = await db.update('institutions', institution.toMap(),
        where: 'id = ?', whereArgs: [institution.id]);
    await const SyncOutbox().enqueueUpsert(
      db: db,
      table: 'institutions',
      localRowId: institution.id!,
      row: institution.toMap(),
    );
    await DriveSyncService().markDirty();
    return count;
  }

  Future<int> delete(int id) async {
    final db = await _db;
    final count = await db.delete('institutions', where: 'id = ?', whereArgs: [id]);
    await DriveSyncService().markDirty();
    return count;
  }

  Future<int> countMembers(int institutionId) async {
    final db = await _db;
    final result = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM members WHERE institution_id = ? AND is_archived = 0',
      [institutionId],
    ));
    return result ?? 0;
  }

  Future<List<InstitutionAnalytics>> getAnalytics({int? districtId}) async {
    final db = await _db;
    final where = districtId == null ? '' : 'WHERE i.district_id = ?';
    final args = districtId == null ? <Object?>[] : <Object?>[districtId];
    final rows = await db.rawQuery('''
      SELECT i.*, d.name AS district_name,
             COUNT(CASE WHEN m.is_archived = 0 THEN m.id END) AS tam_members
      FROM institutions i
      JOIN districts d ON d.id = i.district_id
      LEFT JOIN members m ON m.institution_id = i.id
      $where
      GROUP BY i.id
      ORDER BY d.sort_order ASC, d.name ASC, i.name ASC
    ''', args);
    return rows.map((row) => InstitutionAnalytics(
          institution: Institution.fromMap(row),
          districtName: row['district_name'] as String,
          tamMembers: (row['tam_members'] as int?) ?? 0,
        )).toList();
  }

  Future<Map<String, int>> globalSummary() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) AS institutions,
        SUM(CASE WHEN total_staff > 0 THEN 1 ELSE 0 END) AS with_staff,
        SUM(CASE WHEN total_staff = 0 THEN 1 ELSE 0 END) AS without_staff,
        SUM(total_staff) AS total_staff,
        SUM(sipes_members) AS sipes,
        SUM(snes_members) AS snes,
        SUM(other_union_members) AS other_union,
        SUM(non_union_staff) AS non_union
      FROM institutions
    ''');
    final r = rows.first;
    return {
      'institutions': (r['institutions'] as int?) ?? 0,
      'with_staff': (r['with_staff'] as int?) ?? 0,
      'without_staff': (r['without_staff'] as int?) ?? 0,
      'total_staff': (r['total_staff'] as int?) ?? 0,
      'sipes': (r['sipes'] as int?) ?? 0,
      'snes': (r['snes'] as int?) ?? 0,
      'other_union': (r['other_union'] as int?) ?? 0,
      'non_union': (r['non_union'] as int?) ?? 0,
    };
  }
}
