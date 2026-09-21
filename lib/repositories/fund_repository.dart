import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../models/app_role.dart';
import '../services/permission_service.dart';
import '../models/regional_expense.dart';
import '../services/sync_outbox.dart';

class FundRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<int> addExpense(RegionalExpense expense) async {
    PermissionService.require(Permission.manageFund);
    final db = await _db;
    final id = await db.insert('regional_expenses', expense.toMap());
    await const SyncOutbox().enqueueUpsert(
      db: db, table: 'regional_expenses', localRowId: id,
      row: (await db.query('regional_expenses', where:'id=?', whereArgs:[id])).first,
    );
    return id;
  }

  Future<int> updateExpense(RegionalExpense expense) async {
    PermissionService.require(Permission.manageFund);
    final db = await _db;
    final count = await db.update('regional_expenses', {...expense.toMap(), 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [expense.id]);
    if (count > 0) {
      await const SyncOutbox().enqueueUpsert(db: db, table:'regional_expenses', localRowId: expense.id!,
        row:(await db.query('regional_expenses', where:'id=?', whereArgs:[expense.id])).first);
    }
    return count;
  }

  Future<int> deleteExpense(int id) async {
    PermissionService.require(Permission.manageFund);
    final db = await _db;
    final existing = await db.query('regional_expenses', columns:['sync_uuid'], where:'id=?', whereArgs:[id], limit:1);
    final syncUuid = existing.isEmpty ? null : existing.first['sync_uuid'] as String?;
    final count = await db.delete('regional_expenses', where: 'id = ?', whereArgs: [id]);
    if (count > 0) await const SyncOutbox().enqueueDelete(db:db, table:'regional_expenses', localRowId:id, syncUuid:syncUuid);
    return count;
  }

  Future<List<RegionalExpense>> expensesForYear(int year) async {
    final db = await _db;
    final rows = await db.query(
      'regional_expenses',
      where: "expense_date LIKE ?",
      whereArgs: ['$year%'],
      orderBy: 'expense_date ASC',
    );
    return rows.map(RegionalExpense.fromMap).toList();
  }

  Future<double> totalExpensesForYear(int year) async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) AS total FROM regional_expenses "
      "WHERE expense_date LIKE ?",
      ['$year%'],
    );
    return (result.first['total'] as num).toDouble();
  }

  /// توزيع مصاريف سنة معينة حسب الفئة — تُرتَّب تنازليًا حسب المبلغ.
  Future<Map<String, double>> expensesByCategoryForYear(int year) async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT category, COALESCE(SUM(amount), 0) AS total FROM regional_expenses "
      "WHERE expense_date LIKE ? GROUP BY category ORDER BY total DESC",
      ['$year%'],
    );
    return {for (final r in rows) (r['category'] as String? ?? 'أخرى'): (r['total'] as num).toDouble()};
  }

  /// توزيع مصاريف سنة معينة شهريًا (1..12).
  Future<Map<int, double>> expensesByMonthForYear(int year) async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT CAST(SUBSTR(expense_date, 6, 2) AS INTEGER) AS m, COALESCE(SUM(amount), 0) AS total "
      "FROM regional_expenses WHERE expense_date LIKE ? GROUP BY m",
      ['$year%'],
    );
    final result = <int, double>{for (var m = 1; m <= 12; m++) m: 0};
    for (final row in rows) {
      final m = row['m'] as int?;
      if (m == null || m < 1 || m > 12) continue;
      result[m] = (row['total'] as num).toDouble();
    }
    return result;
  }

  /// أقدم سنة بها أي نشاط مالي (اشتراكات أو مصاريف) — تُستخدم
  /// كنقطة بداية عند حساب سلسلة الأرصدة السنوية المرحّلة.
  Future<int?> earliestActivityYear() async {
    final db = await _db;
    final subYear = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT MIN(payment_year) FROM subscription_payments',
    ));
    final expRows = await db.rawQuery(
      "SELECT MIN(CAST(SUBSTR(expense_date,1,4) AS INTEGER)) AS y FROM regional_expenses",
    );
    final expYear = expRows.first['y'] as int?;
    final overrideYears = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT MIN(year) FROM fund_opening_overrides',
    ));

    final candidates =
        [subYear, expYear, overrideYears].whereType<int>().toList();
    if (candidates.isEmpty) return null;
    candidates.sort();
    return candidates.first;
  }

  Future<double?> openingOverrideForYear(int year) async {
    final db = await _db;
    final rows = await db.query('fund_opening_overrides',
        where: 'year = ?', whereArgs: [year]);
    if (rows.isEmpty) return null;
    return (rows.first['amount'] as num).toDouble();
  }

  Future<void> setOpeningOverride(int year, double amount, String createdAt,
      {String? notes}) async {
    PermissionService.require(Permission.manageFund);
    final db = await _db;
    final existing = await db.query('fund_opening_overrides', where:'year=?', whereArgs:[year], limit:1);
    final id = existing.isEmpty
        ? await db.insert('fund_opening_overrides', {'year':year,'amount':amount,'notes':notes,'created_at':createdAt,'updated_at':createdAt})
        : (await db.update('fund_opening_overrides', {'amount':amount,'notes':notes,'updated_at':createdAt}, where:'year=?', whereArgs:[year]) > 0 ? existing.first['id'] as int : 0);
    if (id > 0) await const SyncOutbox().enqueueUpsert(db:db, table:'fund_opening_overrides', localRowId:id, row:(await db.query('fund_opening_overrides', where:'id=?', whereArgs:[id])).first);
  }
}
