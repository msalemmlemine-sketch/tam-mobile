import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../models/subscription_payment.dart';
import '../models/app_role.dart';
import '../services/permission_service.dart';
import '../services/drive_sync_service.dart';
import '../services/subscription_calculator.dart';
import '../services/sync_outbox.dart';

class SubscriptionRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<Map<String, double>> getSettings() async {
    final db = await _db;
    final rows = await db.query('subscription_settings');
    final map = <String, double>{};
    for (final row in rows) {
      map[row['setting_key'] as String] =
          double.tryParse(row['setting_value'] as String? ?? '0') ?? 0;
    }
    return map;
  }

  Future<void> updateSetting(String key, double value) async {
    final db = await _db;
    await db.update('subscription_settings', {'setting_value': value.toString()},
        where: 'setting_key = ?', whereArgs: [key]);
    await DriveSyncService().markDirty();
  }

  Future<void> _ensureDues(DatabaseExecutor db, int memberId, int year, double fallbackAmount) async {
    final now = DateTime.now().toIso8601String();
    for (var month = 1; month <= 12; month++) {
      final rate = await db.query('subscription_rates', where: 'due_year = ? AND due_month = ?', whereArgs: [year, month], limit: 1);
      final amount = rate.isEmpty ? fallbackAmount : (rate.first['amount'] as num).toDouble();
      await db.insert('subscription_dues', {'member_id': memberId, 'due_year': year, 'due_month': month, 'amount': amount, 'created_at': now}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// يعيد تخصيص دفعة واحدة على الأشهر المستحقة وفق قاعدة الوارد
  /// أولاً يُصرف أولاً (FIFO)، عبر [SubscriptionCalculator.allocatePayment].
  ///
  /// ⚠️ القرار الحسابي (من هو الشهر المسدَّد بالكامل، وكم تبقّى) يُجرى
  /// بأعداد صحيحة حصرًا لمنع أخطاء تراكم الفاصلة العائمة عند تعدد
  /// الدفعات الجزئية على نفس الشهر؛ التخزين في subscription_dues /
  /// payment_allocations يبقى بعمود REAL للتوافق مع بقية النظام، لكن
  /// القيمة المكتوبة هي دائمًا عدد صحيح تام (لا كسور) بعد هذا الإصلاح.
  Future<void> _allocatePayment(DatabaseExecutor db, int paymentId) async {
    final rows = await db.query('subscription_payments', where: 'id = ?', whereArgs: [paymentId], limit: 1);
    if (rows.isEmpty) return;
    final p = rows.first;
    final memberId = p['member_id'] as int?;
    if (memberId == null) return;
    final year = p['payment_year'] as int;
    final rawAmount = (p['subscription_amount'] as num?)?.toDouble() ?? 0;
    final amount = MoneyUtils.toMinorUnits(rawAmount);
    final setting = await db.query('subscription_settings', where: 'setting_key = ?', whereArgs: ['monthly_amount'], limit: 1);
    final fallback = setting.isEmpty ? 100.0 : double.tryParse(setting.first['setting_value'] as String? ?? '') ?? 100.0;
    await _ensureDues(db, memberId, year, fallback);
    await db.delete('payment_allocations', where: 'payment_id = ?', whereArgs: [paymentId]);
    if (amount <= 0) return;

    final dueRows = await db.rawQuery('''SELECT d.id,d.amount,COALESCE((SELECT SUM(a.allocated_amount) FROM payment_allocations a WHERE a.due_id=d.id AND a.payment_id<>?),0) paid FROM subscription_dues d WHERE d.member_id=? AND d.due_year=? ORDER BY d.due_month''', [paymentId, memberId, year]);

    final lineItems = dueRows
        .map((d) => DueLineItem(
              id: d['id'] as int,
              amountDue: MoneyUtils.toMinorUnits((d['amount'] as num).toDouble()),
              amountAlreadyPaid: MoneyUtils.toMinorUnits((d['paid'] as num).toDouble()),
            ))
        .toList();

    const calculator = SubscriptionCalculator();
    final result = calculator.allocatePayment(
      paymentAmount: amount,
      outstandingDuesOldestFirst: lineItems,
    );

    final now = DateTime.now().toIso8601String();
    for (final allocation in result.allocations) {
      await db.insert('payment_allocations', {
        'payment_id': paymentId,
        'due_id': allocation.dueId,
        'allocated_amount': allocation.allocatedAmount, // عدد صحيح تام دومًا
        'created_at': now,
      });
    }
    // result.unallocatedRemainder: أي جزء متبقٍ من الدفعة لم يجد شهرًا
    // مستحقًا (منشأً بالفعل) ليُغطّيه — يبقى محفوظًا ضمنيًا كفارق بين
    // مجموع الدفعات ومجموع التخصيصات لهذا المنتسب، ويُستهلك تلقائيًا
    // حين تُنشأ أشهر لاحقة عبر _ensureDues في نفس السنة أو ما بعدها.
  }

  Future<int> recordPayment(SubscriptionPayment payment) async {
    PermissionService.require(Permission.addPayments);
    final db = await _db;
    final id = await db.insert('subscription_payments', payment.toMap());
    await _allocatePayment(db, id);
    await _audit(db, 'create', 'subscription_payment', id,
        'إضافة دفعة: ${payment.paymentMethod} / ${payment.totalAmount}');
    // يُزامن مع Supabase كإدخال (insert) فقط — جدول الدفعات هناك غير
    // قابل للتعديل أو الحذف عمدًا (انظر supabase/001_tam_schema_and_rls.sql
    // وتعليق updatePayment/deletePayment أدناه لسبب عدم مزامنتهما).
    await const SyncOutbox().enqueueUpsert(
      db: db,
      table: 'subscription_payments',
      localRowId: id,
      row: (await db.query('subscription_payments', where: 'id = ?', whereArgs: [id])).first,
    );
    await DriveSyncService().markDirty();
    return id;
  }

  Future<int> updatePayment(SubscriptionPayment payment) async {
    PermissionService.require(Permission.editPayments);
    if (payment.id == null) throw ArgumentError('payment.id is required');
    final db = await _db;
    final count = await db.update('subscription_payments', payment.toMap(),
        where: 'id = ?', whereArgs: [payment.id]);
    await _allocatePayment(db, payment.id!);
    await _audit(db, 'update', 'subscription_payment', payment.id,
        'تصحيح دفعة: ${payment.paymentMethod} / ${payment.totalAmount}');
    // ⚠️ عمدًا: لا تُضاف هذه العملية لصف انتظار مزامنة Supabase.
    // سياسات RLS الجديدة (item 5) تمنع UPDATE/DELETE على
    // subscription_payments هناك نهائيًا — أي تصحيح مالي مصدره
    // الحقيقة الوحيدة (Supabase) يجب أن يمر عبر حركة تصحيحية جديدة
    // (سطر دفعة إضافي موجب/سالب) وليس تعديل السطر الأصلي. محليًا ما
    // زال التعديل المباشر مسموحًا (كما كان)، لكن مزامنته السحابية
    // كـ"حركة تصحيحية" تلقائية غير مُنفَّذة بعد — يبقى هذا التصحيح
    // محليًا فقط حتى تُبنى هذه الميزة (موثَّق في CLOUD_SETUP.md).
    await DriveSyncService().markDirty();
    return count;
  }

  Future<int> deletePayment(int id) async {
    PermissionService.require(Permission.deletePayments);
    final db = await _db;
    final count = await db.delete('subscription_payments', where: 'id = ?', whereArgs: [id]);
    await _audit(db, 'delete', 'subscription_payment', id, 'حذف دفعة');
    // لا مزامنة سحابية لهذا الحذف لنفس سبب updatePayment أعلاه —
    // Supabase يمنع حذف الدفعات نهائيًا؛ الحذف المحلي يبقى استثناءً
    // إداريًا محليًا فقط (مثلاً لإصلاح خطأ إدخال فوري لم يُزامَن بعد).
    await DriveSyncService().markDirty();
    return count;
  }

  Future<List<SubscriptionPayment>> paymentsForMember(int memberId) async {
    final db = await _db;
    final rows = await db.query('subscription_payments', where: 'member_id = ?',
        whereArgs: [memberId], orderBy: 'payment_year DESC, payment_month DESC, id DESC');
    return rows.map(SubscriptionPayment.fromMap).toList();
  }

  Future<List<SubscriptionPayment>> paymentsForYear(int year) async {
    final db = await _db;
    final rows = await db.query('subscription_payments', where: 'payment_year = ?',
        whereArgs: [year], orderBy: 'payment_month ASC, id ASC');
    return rows.map(SubscriptionPayment.fromMap).toList();
  }

  Future<double> totalSubscriptionPaidByMember(int memberId, {int? year}) async {
    final db = await _db;
    final result = await db.rawQuery(
      year == null
          ? 'SELECT COALESCE(SUM(subscription_amount), 0) AS total FROM subscription_payments WHERE member_id = ?'
          : 'SELECT COALESCE(SUM(subscription_amount), 0) AS total FROM subscription_payments WHERE member_id = ? AND payment_year = ?',
      year == null ? [memberId] : [memberId, year],
    );
    return (result.first['total'] as num).toDouble();
  }

  Future<List<Map<String, Object?>>> monthlyStatus(int memberId, int year) async {
    final db = await _db;
    final settings = await getSettings();
    await _ensureDues(db, memberId, year, settings['monthly_amount'] ?? 100);
    return db.rawQuery('''SELECT d.id,d.due_year,d.due_month,d.amount,COALESCE(SUM(a.allocated_amount),0) paid FROM subscription_dues d LEFT JOIN payment_allocations a ON a.due_id=d.id WHERE d.member_id=? AND d.due_year=? GROUP BY d.id ORDER BY d.due_month''', [memberId,year]);
  }

  Future<String?> firstPaymentDate(int memberId) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT MIN(payment_date) AS d FROM subscription_payments WHERE member_id = ? AND payment_date IS NOT NULL',
      [memberId],
    );
    return result.first['d'] as String?;
  }

  Future<double> regionalShareIncomeForYear(int year, {required double regionalSharePercent}) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(subscription_amount), 0) AS total FROM subscription_payments WHERE payment_year = ? AND direct_to_executive = 0',
      [year],
    );
    final total = (result.first['total'] as num).toDouble();
    return total * (regionalSharePercent / 100);
  }

  /// حصة الجهوي من المداخيل مقسَّمة شهريًا لسنة معينة — تُستخدم في
  /// التقرير التحليلي المفصَّل للصندوق.
  Future<Map<int, double>> regionalShareIncomeByMonth(int year, {required double regionalSharePercent}) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''SELECT payment_month, COALESCE(SUM(subscription_amount), 0) AS total
         FROM subscription_payments
         WHERE payment_year = ? AND direct_to_executive = 0 AND payment_month IS NOT NULL
         GROUP BY payment_month''',
      [year],
    );
    final result = <int, double>{for (var m = 1; m <= 12; m++) m: 0};
    for (final row in rows) {
      final month = row['payment_month'] as int?;
      if (month == null || month < 1 || month > 12) continue;
      result[month] = (row['total'] as num).toDouble() * (regionalSharePercent / 100);
    }
    return result;
  }

  /// تركيبة مداخيل الاشتراكات لسنة معينة: الإجمالي المُحصَّل، ما
  /// ذهب مباشرة للتنفيذي، وما تبقى وخضع لتوزيع تنفيذي/جهوي.
  Future<({double totalCollected, double directToExecutive, double regionalEligible, double regionalShare, double executiveShare})>
      incomeCompositionForYear(int year, {required double regionalSharePercent, required double executiveSharePercent}) async {
    final db = await _db;
    final totalRow = await db.rawQuery(
      'SELECT COALESCE(SUM(subscription_amount), 0) AS total FROM subscription_payments WHERE payment_year = ?',
      [year],
    );
    final directRow = await db.rawQuery(
      'SELECT COALESCE(SUM(subscription_amount), 0) AS total FROM subscription_payments WHERE payment_year = ? AND direct_to_executive = 1',
      [year],
    );
    final total = (totalRow.first['total'] as num).toDouble();
    final direct = (directRow.first['total'] as num).toDouble();
    final eligible = total - direct;
    return (
      totalCollected: total,
      directToExecutive: direct,
      regionalEligible: eligible,
      regionalShare: eligible * (regionalSharePercent / 100),
      executiveShare: direct + eligible * (executiveSharePercent / 100),
    );
  }

  Future<void> _audit(Database db, String action, String entity, int? entityId, String details) async {
    await db.insert('audit_log', {
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'details': details,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
