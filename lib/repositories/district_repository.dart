import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../services/drive_sync_service.dart';
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
    final db = await _db;
    final id = await db.insert('districts', district.toMap());
    await const SyncOutbox().enqueueUpsert(
      db: db,
      table: 'districts',
      localRowId: id,
      row: (await db.query('districts', where: 'id = ?', whereArgs: [id])).first,
    );
    await DriveSyncService().markDirty();
    return id;
  }

  Future<int> update(District district) async {
    final db = await _db;
    final count = await db.update('districts', district.toMap(),
        where: 'id = ?', whereArgs: [district.id]);
    await const SyncOutbox().enqueueUpsert(
      db: db,
      table: 'districts',
      localRowId: district.id!,
      row: district.toMap(),
    );
    await DriveSyncService().markDirty();
    return count;
  }

  /// يفشل بخطأ FK إن كانت هناك مؤسسات مرتبطة — سلوك مقصود لمنع
  /// حذف مقاطعة بها بيانات (Soft-guard عبر ON DELETE RESTRICT).
  Future<int> delete(int id) async {
    final db = await _db;
    final count = await db.delete('districts', where: 'id = ?', whereArgs: [id]);
    await DriveSyncService().markDirty();
    return count;
  }
}
