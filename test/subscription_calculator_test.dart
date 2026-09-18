import 'package:flutter_test/flutter_test.dart';
import 'package:tam_mobile/services/subscription_calculator.dart';
import 'package:tam_mobile/models/fund_year_summary.dart';

void main() {
  const calc = SubscriptionCalculator();

  group('SubscriptionCalculator.monthsElapsed', () {
    test('يحسب الأشهر شاملة شهر البداية لمنتسب نشط', () {
      final months = calc.monthsElapsed(
        firstDueDate: DateTime(2025, 1, 1),
        referenceDate: DateTime(2025, 4, 15),
        isActive: true,
      );
      expect(months, 4); // يناير، فبراير، مارس، أبريل
    });

    test('يتوقف عند تاريخ التوقف لمنتسب غير نشط', () {
      final months = calc.monthsElapsed(
        firstDueDate: DateTime(2025, 1, 1),
        referenceDate: DateTime(2025, 12, 1),
        statusDate: DateTime(2025, 3, 10),
        isActive: false,
      );
      expect(months, 3);
    });

    test('يعيد صفرًا إذا كان تاريخ الاستحقاق بعد تاريخ المرجع', () {
      final months = calc.monthsElapsed(
        firstDueDate: DateTime(2026, 1, 1),
        referenceDate: DateTime(2025, 6, 1),
        isActive: true,
      );
      expect(months, 0);
    });
  });

  group('SubscriptionCalculator.remainingBalance', () {
    test('لا يقل الرصيد المتبقي عن صفر حتى لو دفع المنتسب زيادة', () {
      final remaining =
          calc.remainingBalance(totalDue: 300, totalPaid: 500);
      expect(remaining, 0);
    });

    test('يحسب المتبقي الصحيح عند دفع جزئي', () {
      final remaining =
          calc.remainingBalance(totalDue: 400, totalPaid: 150);
      expect(remaining, 250);
    });
  });

  group('SubscriptionCalculator.splitPayment', () {
    test('يوزّع الدفعة بين التنفيذي والجهوي حسب النسب', () {
      final result = calc.splitPayment(
        subscriptionAmount: 100,
        directToExecutive: false,
        executiveSharePercent: 70,
        regionalSharePercent: 30,
      );
      expect(result.executiveShare, 70);
      expect(result.regionalShare, 30);
    });

    test('الدفعة المباشرة للتنفيذي لا تُوزَّع على الجهوي إطلاقًا', () {
      final result = calc.splitPayment(
        subscriptionAmount: 100,
        directToExecutive: true,
        executiveSharePercent: 70,
        regionalSharePercent: 30,
      );
      expect(result.executiveShare, 100);
      expect(result.regionalShare, 0);
    });
  });

  group('FundYearSummary — ترحيل الرصيد بين السنوات', () {
    test('الرصيد الختامي لسنة يساوي الافتتاحي + المداخيل - المصاريف', () {
      const year2025 = FundYearSummary(
        year: 2025,
        openingBalance: 1000,
        income: 3000,
        expenses: 1200,
      );
      expect(year2025.closingBalance, 2800);
    });

    test('الرصيد الختامي لسنة يصبح الافتتاحي للسنة التالية (لا يُفقد)', () {
      const year2025 = FundYearSummary(
        year: 2025,
        openingBalance: 1000,
        income: 3000,
        expenses: 1200,
      );
      final year2026 = FundYearSummary(
        year: 2026,
        openingBalance: year2025.closingBalance,
        income: 500,
        expenses: 0,
      );
      expect(year2026.openingBalance, 2800);
      expect(year2026.closingBalance, 3300);
    });
  });
}
