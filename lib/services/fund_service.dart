import '../models/fund_year_summary.dart';
import '../repositories/fund_repository.dart';
import '../repositories/subscription_repository.dart';

/// يحسب سلسلة الأرصدة السنوية المرحّلة للصندوق الجهوي — المفهوم
/// الجديد المتفق عليه صراحةً مع المستخدم (البند رقم ١ من نقاط
/// الفحص): كل سنة رصيدها الافتتاحي = الرصيد الختامي للسنة السابقة،
/// ولا يُخفي اختيار سنة معينة الرصيد المرحَّل من قبلها.
///
/// الحساب تراكمي وتلقائي بالكامل انطلاقًا من أقدم سنة نشاط، إلا
/// إذا وُجد رصيد افتتاحي يدوي (fund_opening_overrides) لسنة معينة
/// — وعندها يُستخدم كنقطة انطلاق بدل الاعتماد على ما قبلها (يُفيد
/// عند بدء استخدام التطبيق دون تسجيل كل التاريخ المالي القديم).
class FundService {
  FundService({
    FundRepository? fundRepository,
    SubscriptionRepository? subscriptionRepository,
  })  : _fundRepo = fundRepository ?? FundRepository(),
        _subRepo = subscriptionRepository ?? SubscriptionRepository();

  final FundRepository _fundRepo;
  final SubscriptionRepository _subRepo;

  /// يحسب ملخص سنة واحدة، مع بناء كل السنوات السابقة أولًا لضمان
  /// أن الرصيد الافتتاحي صحيح ومرحَّل بشكل متسلسل.
  Future<FundYearSummary> summaryForYear(int year) async {
    final chain = await yearsChain(upTo: year);
    return chain.last;
  }

  /// يبني قائمة بملخصات كل السنوات من أقدم سنة نشاط (أو من أقرب
  /// رصيد افتتاحي يدوي) حتى السنة المطلوبة، بالترتيب الزمني.
  Future<List<FundYearSummary>> yearsChain({required int upTo}) async {
    final earliest = await _fundRepo.earliestActivityYear();
    final startYear = earliest ?? upTo;

    final settings = await _subRepo.getSettings();
    final regionalPct = settings['regional_share_percent'] ?? 30.0;

    final results = <FundYearSummary>[];
    double runningBalance = 0;

    for (var year = startYear; year <= upTo; year++) {
      final override = await _fundRepo.openingOverrideForYear(year);
      final opening = override ?? runningBalance;

      final income = await _subRepo.regionalShareIncomeForYear(
        year,
        regionalSharePercent: regionalPct,
      );
      final expenses = await _fundRepo.totalExpensesForYear(year);

      final summary = FundYearSummary(
        year: year,
        openingBalance: opening,
        income: income,
        expenses: expenses,
        openingIsManualOverride: override != null,
      );
      results.add(summary);
      runningBalance = summary.closingBalance;
    }

    return results;
  }
}
