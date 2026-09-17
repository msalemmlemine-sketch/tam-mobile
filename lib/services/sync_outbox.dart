import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';

/// صف انتظار العمليات غير المتصلة (Outbox Pattern).
///
/// كل تعديل على جدول "مشترك" بين الأجهزة الثلاثة (مثل members أو
/// subscription_payments) يُسجَّل هنا فور نجاح الكتابة المحلية، بدل
/// محاولة رفعه فورًا لـ Supabase (الذي قد يكون غير متاح إن لم يوجد
/// إنترنت في تلك اللحظة). [CloudSyncEngine] يقرأ هذا الصف لاحقًا
/// ويرفع كل سطر، مع إعادة محاولة عند الفشل دون فقدان العملية أو
/// تكرارها (upsert بمفتاح ثابت — انظر عمود legacy_id في سكيما
/// Supabase).
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
    await db.insert('sync_outbox', {
      'table_name': table,
      'local_row_id': localRowId,
      'operation': 'upsert',
      'payload_json': jsonEncode(row),
      'attempt_count': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// يُسجِّل عملية "حذف" — لا حاجة لمحتوى الصف، فقط مفتاحه.
  Future<void> enqueueDelete({
    required DatabaseExecutor db,
    required String table,
    required int localRowId,
  }) async {
    await db.insert('sync_outbox', {
      'table_name': table,
      'local_row_id': localRowId,
      'operation': 'delete',
      'payload_json': null,
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
}
