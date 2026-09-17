import '../models/fund_year_summary.dart';
import '../models/regional_expense.dart';
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

  /// يبني تقريرًا تفصيليًا تحليليًا شاملًا لسنة معينة: الملخص
  /// السنوي، التفصيل الشهري للمداخيل والمصاريف، توزيع المصاريف
  /// حسب الفئة، تركيبة المداخيل (مباشر للتنفيذي/حصة جهوية/حصة
  /// تنفيذي)، وسلسلة الأرصدة عبر كل السنوات للمقارنة التاريخية.
  Future<FundDetailedReport> detailedReportForYear(int year) async {
    final chain = await yearsChain(upTo: year);
    final summary = chain.last;

    final settings = await _subRepo.getSettings();
    final regionalPct = settings['regional_share_percent'] ?? 30.0;
    final executivePct = settings['executive_share_percent'] ?? 70.0;

    final monthlyIncome = await _subRepo.regionalShareIncomeByMonth(year, regionalSharePercent: regionalPct);
    final monthlyExpenses = await _fundRepo.expensesByMonthForYear(year);
    final categoryBreakdown = await _fundRepo.expensesByCategoryForYear(year);
    final composition = await _subRepo.incomeCompositionForYear(
      year,
      regionalSharePercent: regionalPct,
      executiveSharePercent: executivePct,
    );
    final expenses = await _fundRepo.expensesForYear(year);

    return FundDetailedReport(
      summary: summary,
      yearsChain: chain,
      monthlyIncome: monthlyIncome,
      monthlyExpenses: monthlyExpenses,
      categoryBreakdown: categoryBreakdown,
      totalCollected: composition.totalCollected,
      directToExecutive: composition.directToExecutive,
      regionalEligible: composition.regionalEligible,
      executiveShare: composition.executiveShare,
      expenses: expenses,
    );
  }
}

/// حزمة بيانات التقرير التحليلي الشامل للصندوق — سنة واحدة مع كل
/// أبعاد التحليل المطلوبة (شهري، فئوي، تركيبة المداخيل، تاريخي).
class FundDetailedReport {
  final FundYearSummary summary;
  final List<FundYearSummary> yearsChain;
  final Map<int, double> monthlyIncome;
  final Map<int, double> monthlyExpenses;
  final Map<String, double> categoryBreakdown;
  final double totalCollected;
  final double directToExecutive;
  final double regionalEligible;
  final double executiveShare;
  final List<RegionalExpense> expenses;

  const FundDetailedReport({
    required this.summary,
    required this.yearsChain,
    required this.monthlyIncome,
    required this.monthlyExpenses,
    required this.categoryBreakdown,
    required this.totalCollected,
    required this.directToExecutive,
    required this.regionalEligible,
    required this.executiveShare,
    required this.expenses,
  });
}
