/// منطق حساب مستحقات ومتأخرات الاشتراك — منقول حرفيًا من
/// subscriptions.php / member_account.php الأصليين، ومعزول هنا في
/// طبقة Business Logic واحدة حتى تتطابق النتيجة في كل مكان
/// (Dashboard / التقارير / تفاصيل المنتسب) كما اشتُرط.
///
/// هذه الدوال نقيّة (pure) — لا تتعامل مع قاعدة البيانات مباشرة،
/// بل تستقبل المدخلات الجاهزة من الـ Repositories، مما يجعلها
/// قابلة للاختبار بسهولة (انظر test/subscription_calculator_test.dart).
class SubscriptionCalculator {
  const SubscriptionCalculator();

  /// عدد الأشهر المستحقة على المنتسب منذ أول شهر يُفترض دفعه
  /// (firstDueDate) وحتى تاريخ المرجع (referenceDate) — أو حتى
  /// statusDate إن كان المنتسب غير نشط (توقف عن الاستحقاق).
  int monthsElapsed({
    required DateTime firstDueDate,
    required DateTime referenceDate,
    DateTime? statusDate,
    required bool isActive,
  }) {
    final effectiveEnd = (!isActive && statusDate != null)
        ? statusDate
        : referenceDate;
    if (effectiveEnd.isBefore(firstDueDate)) return 0;

    final months = (effectiveEnd.year - firstDueDate.year) * 12 +
        (effectiveEnd.month - firstDueDate.month) +
        1; // شامل شهر البداية
    return months < 0 ? 0 : months;
  }

  /// إجمالي المستحق = عدد الأشهر × قيمة الاشتراك الشهري.
  double totalDue({
    required int monthsElapsed,
    required double monthlyAmount,
  }) =>
      monthsElapsed * monthlyAmount;

  /// المتبقي على المنتسب = المستحق − المدفوع فعليًا (لا يقل عن صفر).
  double remainingBalance({
    required double totalDue,
    required double totalPaid,
  }) {
    final remaining = totalDue - totalPaid;
    return remaining < 0 ? 0.0 : remaining;
  }

  /// عدد الأشهر المغطاة فعليًا بالمدفوعات (يُستخدم لعرض "مسدد حتى
  /// شهر كذا" في تفاصيل المنتسب).
  int monthsCovered({
    required double totalPaid,
    required double monthlyAmount,
  }) {
    if (monthlyAmount <= 0) return 0;
    return (totalPaid / monthlyAmount).floor();
  }

  /// توزيع دفعة اشتراك واحدة بين التنفيذي والجهوي حسب النسب
  /// المعتمدة في subscription_settings. دفعة "مباشرة للتنفيذي"
  /// (directToExecutive) تذهب بالكامل للتنفيذي بلا توزيع.
  ({double executiveShare, double regionalShare}) splitPayment({
    required double subscriptionAmount,
    required bool directToExecutive,
    required double executiveSharePercent,
    required double regionalSharePercent,
  }) {
    if (directToExecutive) {
      return (executiveShare: subscriptionAmount, regionalShare: 0);
    }
    return (
      executiveShare: subscriptionAmount * (executiveSharePercent / 100),
      regionalShare: subscriptionAmount * (regionalSharePercent / 100),
    );
  }
}
