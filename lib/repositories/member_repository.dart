import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../models/member.dart';
import '../models/app_role.dart';
import '../services/permission_service.dart';
import '../services/sync_outbox.dart';
import 'user_repository.dart';

class MemberRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  /// جلب صفحة واحدة من المنتسبين (Pagination) مع بحث اختياري
  /// بالاسم أو الدليل المالي أو رقم البطاقة أو الهاتف، وتصفية
  /// اختيارية حسب المؤسسة/المقاطعة — يعتمد على الفهارس المُعرَّفة
  /// في AppDatabase لتبقى سريعة حتى مع عشرات الآلاف من السجلات.
  Future<List<Member>> search({
    String? query,
    int? districtId,
    int? institutionId,
    bool includeArchived = false,
    int limit = 30,
    int offset = 0,
  }) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];

    if (!includeArchived) {
      where.add('is_archived = 0');
    }
    if (districtId != null) {
      where.add('district_id = ?');
      args.add(districtId);
    }
    if (institutionId != null) {
      where.add('institution_id = ?');
      args.add(institutionId);
    }
    if (query != null && query.trim().isNotEmpty) {
      final like = '%${query.trim()}%';
      where.add('(name LIKE ? OR guide LIKE ? OR card_no LIKE ? OR phone LIKE ?)');
      args.addAll([like, like, like, like]);
    }

    final rows = await db.query(
      'members',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'name ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Member.fromMap).toList();
  }

  Future<int> countSearch({
    String? query,
    int? districtId,
    int? institutionId,
    bool includeArchived = false,
  }) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];

    if (!includeArchived) where.add('is_archived = 0');
    if (districtId != null) {
      where.add('district_id = ?');
      args.add(districtId);
    }
    if (institutionId != null) {
      where.add('institution_id = ?');
      args.add(institutionId);
    }
    if (query != null && query.trim().isNotEmpty) {
      final like = '%${query.trim()}%';
      where.add('(name LIKE ? OR guide LIKE ? OR card_no LIKE ? OR phone LIKE ?)');
      args.addAll([like, like, like, like]);
    }

    final result = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM members${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}',
      args,
    ));
    return result ?? 0;
  }

  Future<Member?> getById(int id) async {
    final db = await _db;
    final rows = await db.query('members', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Member.fromMap(rows.first);
  }

  Future<int> create(Member member) async {
    PermissionService.require(Permission.manageMembers);
    final db = await _db;
    final id = await db.insert('members', member.toMap());
    await UserRepository().ensureMemberAccount(
      memberId: id,
      displayName: member.name,
      guide: member.guide,
      phone: member.phone,
    );
    // Supabase هو مصدر الحقيقة الوحيد للبيانات المشتركة (انظر
    // CloudService)؛ الكتابة المحلية أعلاه تنجح فورًا سواء كان هناك
    // إنترنت أم لا، وهذا السطر فقط يُضيف العملية لصف انتظار الرفع.
    await const SyncOutbox().enqueueUpsert(
      db: db,
      table: 'members',
      localRowId: id,
      row: (await db.query('members', where: 'id = ?', whereArgs: [id])).first,
    );
    return id;
  }

  Future<int> update(Member member) async {
    PermissionService.require(Permission.manageMembers);
    final db = await _db;
    final count = await db.update('members', member.toMap(),
        where: 'id = ?', whereArgs: [member.id]);
    await UserRepository().ensureMemberAccount(
      memberId: member.id!,
      displayName: member.name,
      guide: member.guide,
      phone: member.phone,
    );
    await const SyncOutbox().enqueueUpsert(
      db: db,
      table: 'members',
      localRowId: member.id!,
      row: member.toMap(),
    );
    return count;
  }

  /// حذف ناعم (Soft Delete) — لا نحذف سجل المنتسب فعليًا لأن له
  /// عمليات مالية مرتبطة، بل نؤرشفه فقط، تماشيًا مع اشتراط عدم
  /// الحذف المباشر للسجلات ذات الصلة المالية.
  Future<int> archive(int id, String updatedAt) async {
    PermissionService.require(Permission.freezeMembers);
    final db = await _db;
    final count = await db.update(
      'members',
      {'is_archived': 1, 'updated_at': updatedAt},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count > 0) {
      final row = await db.query('members', where: 'id = ?', whereArgs: [id]);
      if (row.isNotEmpty) {
        await const SyncOutbox().enqueueUpsert(db: db, table: 'members', localRowId: id, row: row.first);
      }
    }
    return count;
  }

  Future<int> unarchive(int id, String updatedAt) async {
    PermissionService.require(Permission.freezeMembers);
    final db = await _db;
    final count = await db.update(
      'members',
      {'is_archived': 0, 'updated_at': updatedAt},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count > 0) {
      final row = await db.query('members', where: 'id = ?', whereArgs: [id]);
      if (row.isNotEmpty) {
        await const SyncOutbox().enqueueUpsert(db: db, table: 'members', localRowId: id, row: row.first);
      }
    }
    return count;
  }

  /// حذف نهائي حقيقي — يُستخدم فقط لمنتسب لا توجد له أي عمليات
  /// مالية مسجَّلة (خطأ إدخال مثلاً)؛ الواجهة تتحقق من هذا الشرط
  /// قبل السماح باستدعائه.
  Future<int> hardDelete(int id) async {
    PermissionService.require(Permission.deleteMembers);
    final db = await _db;
    final existing = await db.query('members', columns: ['sync_uuid'], where: 'id = ?', whereArgs: [id], limit: 1);
    final syncUuid = existing.isEmpty ? null : existing.first['sync_uuid'] as String?;
    final count = await db.delete('members', where: 'id = ?', whereArgs: [id]);
    if (count > 0) {
      await const SyncOutbox().enqueueDelete(db: db, table: 'members', localRowId: id, syncUuid: syncUuid);
    }
    return count;
  }

  Future<int> countAll({bool includeArchived = false}) async {
    final db = await _db;
    final result = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM members${includeArchived ? '' : ' WHERE is_archived = 0'}',
    ));
    return result ?? 0;
  }

  /// كل المنتسبين بلا تصفية أو ترقيم — يُستخدم فقط في مطابقة
  /// الاستيراد (subscription_importer.dart) التي تحتاج القائمة
  /// الكاملة دفعة واحدة، مطابقةً لـ sub_load_members الأصلية.
  Future<List<Member>> getAllForImportMatching() async {
    final db = await _db;
    final rows = await db.query('members', orderBy: 'name ASC');
    return rows.map(Member.fromMap).toList();
  }
}
