import '../models/fund_year_summary.dart';
import '../models/regional_expense.dart';
import '../repositories/fund_repository.dart';
import '../repositories/subscription_repository.dart';

class FundService {
  FundService({
    FundRepository? fundRepository,
    SubscriptionRepository? subscriptionRepository,
  })  : _fundRepo = fundRepository ?? FundRepository(),
        _subRepo =
            subscriptionRepository ?? SubscriptionRepository();

  final FundRepository _fundRepo;
  final SubscriptionRepository _subRepo;

  Future<FundYearSummary> summaryForYear(int year) async {
    final chain = await yearsChain(upTo: year);
    return chain.last;
  }

  Future<List<FundYearSummary>> yearsChain({
    required int upTo,
  }) async {
    final earliest =
        await _fundRepo.earliestActivityYear();

    final startYear = earliest ?? upTo;

    final settings = await _subRepo.getSettings();

    final regionalPct =
        (settings['regional_share_percent'] ?? 30.0)
            .toDouble();

    final results = <FundYearSummary>[];

    double runningBalance = 0;

    for (var year = startYear;
        year <= upTo;
        year++) {
      final manualOpening =
          await _fundRepo.openingOverrideForYear(year);

      final opening =
          manualOpening ?? runningBalance;

      final income =
          await _subRepo.regionalShareIncomeForYear(
        year,
        regionalSharePercent: regionalPct,
      );

      final expenses =
          await _fundRepo.totalExpensesForYear(year);

      final summary = FundYearSummary(
        year: year,
        openingBalance: opening,
        income: income,
        expenses: expenses,
        openingIsManualOverride:
            manualOpening != null,
      );

      results.add(summary);

      runningBalance =
          summary.closingBalance;
    }

    return results;
  }

  Future<FundDetailedReport>
      detailedReportForYear(int year) async {
    final chain =
        await yearsChain(upTo: year);

    final summary = chain.last;

    final settings =
        await _subRepo.getSettings();

    final regionalPct =
        (settings['regional_share_percent'] ?? 30.0)
            .toDouble();

    final executivePct =
        (settings['executive_share_percent'] ?? 70.0)
            .toDouble();

    final monthlyIncome =
        await _subRepo.regionalShareIncomeByMonth(
      year,
      regionalSharePercent: regionalPct,
    );

    final monthlyExpenses =
        await _fundRepo.expensesByMonthForYear(year);

    final categoryBreakdown =
        await _fundRepo.expensesByCategoryForYear(year);

    final composition =
        await _subRepo.incomeCompositionForYear(
      year,
      regionalSharePercent: regionalPct,
      executiveSharePercent: executivePct,
    );

    final expenses =
        await _fundRepo.expensesForYear(year);

    return FundDetailedReport(
      summary: summary,
      yearsChain: chain,
      monthlyIncome: monthlyIncome,
      monthlyExpenses: monthlyExpenses,
      categoryBreakdown: categoryBreakdown,
      totalCollected: composition.totalCollected,
      directToExecutive:
          composition.directToExecutive,
      regionalEligible:
          composition.regionalEligible,
      executiveShare:
          composition.executiveShare,
      expenses: expenses,
    );
  }
}

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
