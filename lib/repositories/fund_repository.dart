import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../services/drive_sync_service.dart';
import '../models/regional_expense.dart';

class FundRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<int> addExpense(RegionalExpense expense) async {
    final db = await _db;
    final id = await db.insert('regional_expenses', expense.toMap());
    await DriveSyncService().markDirty();
    return id;
  }

  Future<int> updateExpense(RegionalExpense expense) async {
    final db = await _db;
    final count = await db.update('regional_expenses', expense.toMap(),
        where: 'id = ?', whereArgs: [expense.id]);
    await DriveSyncService().markDirty();
    return count;
  }

  Future<int> deleteExpense(int id) async {
    final db = await _db;
    final count = await db.delete('regional_expenses', where: 'id = ?', whereArgs: [id]);
    await DriveSyncService().markDirty();
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
    final db = await _db;
    await db.insert(
      'fund_opening_overrides',
      {
        'year': year,
        'amount': amount,
        'notes': notes,
        'created_at': createdAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await DriveSyncService().markDirty();
  }
}
