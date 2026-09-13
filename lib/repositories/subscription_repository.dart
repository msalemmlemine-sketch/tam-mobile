import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../models/subscription_payment.dart';

class SubscriptionRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  /// إعدادات الاشتراك (مبلغ الاشتراك الشهري، رسم البطاقة، نسبة
  /// التنفيذي/الجهوي) — مطابقة لجدول subscription_settings الأصلي.
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
    await db.update(
      'subscription_settings',
      {'setting_value': value.toString()},
      where: 'setting_key = ?',
      whereArgs: [key],
    );
  }

  Future<int> recordPayment(SubscriptionPayment payment) async {
    final db = await _db;
    return db.insert('subscription_payments', payment.toMap());
  }

  Future<List<SubscriptionPayment>> paymentsForMember(int memberId) async {
    final db = await _db;
    final rows = await db.query(
      'subscription_payments',
      where: 'member_id = ?',
      whereArgs: [memberId],
      orderBy: 'payment_year DESC, payment_month DESC, id DESC',
    );
    return rows.map(SubscriptionPayment.fromMap).toList();
  }

  Future<List<SubscriptionPayment>> paymentsForYear(int year) async {
    final db = await _db;
    final rows = await db.query(
      'subscription_payments',
      where: 'payment_year = ?',
      whereArgs: [year],
      orderBy: 'payment_month ASC, id ASC',
    );
    return rows.map(SubscriptionPayment.fromMap).toList();
  }

  /// إجمالي ما دفعه المنتسب من قيمة الاشتراك (بدون رسوم البطاقة) —
  /// يُستخدم في حساب المتبقي/المتأخرات (subscription_calculator.dart).
  Future<double> totalSubscriptionPaidByMember(int memberId) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(subscription_amount), 0) AS total '
      'FROM subscription_payments WHERE member_id = ?',
      [memberId],
    );
    return (result.first['total'] as num).toDouble();
  }

  Future<String?> firstPaymentDate(int memberId) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT MIN(payment_date) AS d FROM subscription_payments '
      'WHERE member_id = ? AND payment_date IS NOT NULL',
      [memberId],
    );
    return result.first['d'] as String?;
  }

  /// مجموع حصة الجهوي من اشتراكات سنة معينة — يُستخدم في حساب
  /// مداخيل الصندوق السنوي (fund_service.dart). المدفوعات ذات
  /// direct_to_executive=1 تُستبعد بالكامل من حصة الجهوي.
  Future<double> regionalShareIncomeForYear(
    int year, {
    required double regionalSharePercent,
  }) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(subscription_amount), 0) AS total '
      'FROM subscription_payments '
      'WHERE payment_year = ? AND direct_to_executive = 0',
      [year],
    );
    final total = (result.first['total'] as num).toDouble();
    return total * (regionalSharePercent / 100);
  }
}
