import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';

/// صف انتظار العمليات غير المتصلة (Outbox Pattern).
///
/// كل تعديل على جدول "مشترك" بين الأجهزة الثلاثة (مثل members أو
/// subscription_payments) يُسجَّل هنا فور نجاح الكتابة المحلية، بدل
/// محاولة رفعه فورًا لـ Supabase (الذي قد يكون غير متاح إن لم يوجد
/// إنترنت في تلك اللحظة). [CloudSyncEngine] يقرأ هذا الصف لاحقًا
/// ويرفع كل سطر، مع إعادة محاولة عند الفشل دون فقدان العملية أو
/// تكرارها (upsert بمفتاح ثابت عبر sync_uuid في سكيما Supabase).
class SyncOutbox {
  const SyncOutbox();

  Future<Database> get _db => AppDatabase.instance.database;

  /// يُسجِّل عملية "إضافة/تعديل" على صف محلي — [row] هي القيم
  /// الكاملة الحالية للصف (map عمود→قيمة) وقت الاستدعاء.
  Future<void> enqueueUpsert({
    required DatabaseExecutor db,
    required String table,
    required int localRowId,
    required Map<String, Object?> row,
  }) async {
    final payload = Map<String, Object?>.from(row);
    if (_sharedTables.contains(table)) {
      var syncUuid = payload['sync_uuid'] as String?;
      if (syncUuid == null || syncUuid.isEmpty) {
        final current = await db.query(table, columns: ['sync_uuid'], where: 'id = ?', whereArgs: [localRowId], limit: 1);
        syncUuid = current.isNotEmpty ? current.first['sync_uuid'] as String? : null;
      }
      syncUuid ??= _uuidV4();
      await db.update(table, {'sync_uuid': syncUuid}, where: 'id = ?', whereArgs: [localRowId]);
      payload['sync_uuid'] = syncUuid;
    }
    await db.insert('sync_outbox', {
      'table_name': table,
      'local_row_id': localRowId,
      'operation': 'upsert',
      'payload_json': jsonEncode(payload),
      'attempt_count': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static const _sharedTables = {
    'districts',
    'institutions',
    'members',
    'subscription_payments',
    'regional_expenses',
    'fund_opening_overrides',
  };

  /// يُعالج فجوة: صفوف أُنشئت بإدخال SQLite مباشر خارج طبقة
  /// المستودعات (كالمؤسسات/المقاطعات/المنتسبين المُنشأة ضمنيًا أثناء
  /// استيراد CSV) فبقيت بلا sync_uuid ولم تدخل صف الانتظار إطلاقًا،
  /// أي أنها لن تصل لـ Supabase أبدًا رغم نجاح كتابتها محليًا. يجب
  /// استدعاؤها بعد أي عملية استيراد جماعي، بترتيب الجداول الأب قبل
  /// الابن (districts ثم institutions ثم members) لضمان أن أي مرجع
  /// (district_id/institution_id) يُحل لاحقًا بشكل صحيح في CloudService.
  Future<int> backfillMissingSyncUuids(String table) async {
    final db = await _db;
    final rows = await db.query(table, where: 'sync_uuid IS NULL OR sync_uuid = ?', whereArgs: ['']);
    var count = 0;
    for (final row in rows) {
      final id = row['id'] as int;
      final uuid = _uuidV4();
      await db.update(table, {'sync_uuid': uuid}, where: 'id = ?', whereArgs: [id]);
      final full = Map<String, Object?>.from(row);
      full['sync_uuid'] = uuid;
      await enqueueUpsert(db: db, table: table, localRowId: id, row: full);
      count++;
    }
    return count;
  }

  static String _uuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2,'0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20,32)}';
  }

  /// يُسجِّل عملية "حذف" — يلتقط sync_uuid الصف *قبل* حذفه محليًا
  /// (مرَّره المستدعي في [syncUuid])، لأن الصف نفسه لن يكون موجودًا
  /// محليًا بعد الآن عندما يُعالَج هذا الصف من صف الانتظار لاحقًا —
  /// فلا يمكن الاعتماد على البحث عنه وقتها بواسطة id محلي.
  Future<void> enqueueDelete({
    required DatabaseExecutor db,
    required String table,
    required int localRowId,
    String? syncUuid,
  }) async {
    await db.insert('sync_outbox', {
      'table_name': table,
      'local_row_id': localRowId,
      'operation': 'delete',
      'payload_json': syncUuid == null ? null : jsonEncode({'sync_uuid': syncUuid}),
      'attempt_count': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> pending({int limit = 100}) async {
    final db = await _db;
    return db.query(
      'sync_outbox',
      where: 'synced_at IS NULL',
      orderBy: 'id ASC',
      limit: limit,
    );
  }

  Future<void> markSynced(int outboxId) async {
    final db = await _db;
    await db.update(
      'sync_outbox',
      {'synced_at': DateTime.now().toIso8601String(), 'last_error': null},
      where: 'id = ?',
      whereArgs: [outboxId],
    );
  }

  Future<void> markFailed(int outboxId, String error) async {
    final db = await _db;
    await db.rawUpdate(
      'UPDATE sync_outbox SET attempt_count = attempt_count + 1, last_error = ? WHERE id = ?',
      [error, outboxId],
    );
  }

  /// يُستدعى بعد أي استعادة نسخة احتياطية محلية (BackupService) أو أي
  /// استبدال كامل لجداول القاعدة من مصدر خارجي (كالاستعادة القديمة
  /// من Drive). المحتوى المُستعاد قد يكون أقدم من الحالة السحابية،
  /// أو قد يعيد استخدام أرقام id محلية سبق دفعها لـ Supabase بمحتوى
  /// مختلف تمامًا — فرفع outbox القديم كما هو قد يكتب بيانات خاطئة أو
  /// يخلق تعارض مفاتيح. الحل الآمن: إسقاط كل عمليات outbox المعلَّقة
  /// غير المرفوعة بعد (لأنها تعبّر عن حالة محلية لم تعد موثوقة)، ورفع
  /// علم "يلزم مزامنة كاملة" حتى يبدأ الجهاز من سحب طازج (Pull) من
  /// Supabase قبل أي دفع جديد — بدل الكتابة فوق البيانات السحابية
  /// الحديثة بنسخة محلية قديمة.
  Future<void> clearPendingAndRequireFullResync() async {
    final db = await _db;
    await db.delete('sync_outbox', where: 'synced_at IS NULL');
    await db.insert(
      'settings',
      {'setting_key': 'needs_full_cloud_resync', 'setting_value': '1'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> needsFullResync() async {
    final db = await _db;
    final rows = await db.query('settings',
        where: 'setting_key = ?',
        whereArgs: ['needs_full_cloud_resync'],
        limit: 1);
    return rows.isNotEmpty && rows.first['setting_value'] == '1';
  }

  Future<void> clearFullResyncFlag() async {
    final db = await _db;
    await db.delete('settings',
        where: 'setting_key = ?', whereArgs: ['needs_full_cloud_resync']);
  }
  /// آخر أخطاء الرفع المسجَّلة للعمليات المعلقة.
  Future<List<Map<String, Object?>>> failedWithErrors({int limit = 20}) async {
    final db = await _db;
    return db.query(
      'sync_outbox',
      columns: ['id', 'table_name', 'operation', 'attempt_count', 'last_error'],
      where: 'synced_at IS NULL AND last_error IS NOT NULL',
      orderBy: 'id ASC',
      limit: limit,
    );
  }

  static const _syncOrder = [
    'districts',
    'institutions',
    'members',
    'subscription_payments',
    'regional_expenses',
    'fund_opening_overrides',
  ];

  /// يعيد بناء عمليات الرفع المعلقة من الجداول المحلية بترتيب الآباء أولاً.
  /// لا يحذف أي بيانات محلية؛ يستبدل فقط عمليات upsert المعلقة بنسخ حديثة.
  Future<int> enqueueAllLocalRows() async {
    final db = await _db;
    var count = 0;
    await db.transaction((txn) async {
      await txn.delete('sync_outbox',
          where: "synced_at IS NULL AND operation = 'upsert'");
      for (final table in _syncOrder) {
        final rows = await txn.query(table);
        for (final row in rows) {
          final id = row['id'] as int;
          final clean = Map<String, Object?>.from(row)
            ..removeWhere((k, v) =>
                v == null && (k == 'created_at' || k == 'updated_at'));
          await enqueueUpsert(
            db: txn,
            table: table,
            localRowId: id,
            row: clean,
          );
          count++;
        }
      }
    });
    return count;
  }
}
