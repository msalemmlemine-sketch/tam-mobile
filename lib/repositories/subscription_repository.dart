import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../models/subscription_payment.dart';
import '../models/app_role.dart';
import '../services/permission_service.dart';
import '../services/drive_sync_service.dart';

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

  Future<int> recordPayment(SubscriptionPayment payment) async {
    PermissionService.require(Permission.addPayments);
    final db = await _db;
    final id = await db.insert('subscription_payments', payment.toMap());
    await _audit(db, 'create', 'subscription_payment', id,
        'إضافة دفعة: ${payment.paymentMethod} / ${payment.totalAmount}');
    await DriveSyncService().markDirty();
    return id;
  }

  Future<int> updatePayment(SubscriptionPayment payment) async {
    PermissionService.require(Permission.editPayments);
    if (payment.id == null) throw ArgumentError('payment.id is required');
    final db = await _db;
    final count = await db.update('subscription_payments', payment.toMap(),
        where: 'id = ?', whereArgs: [payment.id]);
    await _audit(db, 'update', 'subscription_payment', payment.id,
        'تصحيح دفعة: ${payment.paymentMethod} / ${payment.totalAmount}');
    await DriveSyncService().markDirty();
    return count;
  }

  Future<int> deletePayment(int id) async {
    PermissionService.require(Permission.deletePayments);
    final db = await _db;
    final count = await db.delete('subscription_payments', where: 'id = ?', whereArgs: [id]);
    await _audit(db, 'delete', 'subscription_payment', id, 'حذف دفعة');
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

  Future<double> totalSubscriptionPaidByMember(int memberId) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(subscription_amount), 0) AS total FROM subscription_payments WHERE member_id = ?',
      [memberId],
    );
    return (result.first['total'] as num).toDouble();
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
