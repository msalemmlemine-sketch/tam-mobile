import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../models/app_role.dart';
import '../services/permission_service.dart';
import '../services/sync_outbox.dart';
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
    PermissionService.require(Permission.manageInstitutions);
    final db = await _db;
    final id = await db.insert('districts', district.toMap());
    await const SyncOutbox().enqueueUpsert(
      db: db,
      table: 'districts',
      localRowId: id,
      row: (await db.query('districts', where: 'id = ?', whereArgs: [id])).first,
    );
    return id;
  }

  Future<int> update(District district) async {
    PermissionService.require(Permission.manageInstitutions);
    final db = await _db;
    final count = await db.update('districts', {...district.toMap(), 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [district.id]);
    await const SyncOutbox().enqueueUpsert(
      db: db,
      table: 'districts',
      localRowId: district.id!,
      row: (await db.query('districts', where:'id=?', whereArgs:[district.id])).first,
    );
    return count;
  }

  /// يفشل بخطأ FK إن كانت هناك مؤسسات مرتبطة — سلوك مقصود لمنع
  /// حذف مقاطعة بها بيانات (Soft-guard عبر ON DELETE RESTRICT).
  Future<int> delete(int id) async {
    PermissionService.require(Permission.manageInstitutions);
    final db = await _db;
    final existing = await db.query('districts', columns: ['sync_uuid'], where: 'id = ?', whereArgs: [id], limit: 1);
    final syncUuid = existing.isEmpty ? null : existing.first['sync_uuid'] as String?;
    final count = await db.delete('districts', where: 'id = ?', whereArgs: [id]);
    if (count > 0) {
      await const SyncOutbox().enqueueDelete(db: db, table: 'districts', localRowId: id, syncUuid: syncUuid);
    }
    return count;
  }
}
