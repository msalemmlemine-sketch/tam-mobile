/// ملخص الصندوق الجهوي لسنة واحدة — المفهوم الجديد المتفق عليه:
/// كل سنة لها رصيد افتتاحي = الرصيد الختامي للسنة السابقة (أو
/// رصيد افتتاحي يدوي إن كان مسجَّلًا في fund_opening_overrides)،
/// ثم تُضاف إليه مداخيل السنة (حصة الجهوي من الاشتراكات) وتُطرح
/// منه مصاريف السنة (regional_expenses)، فيُحسب الرصيد الختامي،
/// الذي يصبح تلقائيًا الرصيد الافتتاحي للسنة التالية.
class FundYearSummary {
  final int year;
  final double openingBalance;
  final double income;
  final double expenses;
  final bool openingIsManualOverride;

  const FundYearSummary({
    required this.year,
    required this.openingBalance,
    required this.income,
    required this.expenses,
    this.openingIsManualOverride = false,
  });

  double get closingBalance => openingBalance + income - expenses;
}
