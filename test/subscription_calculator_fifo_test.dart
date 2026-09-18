import 'package:flutter_test/flutter_test.dart';
import 'package:tam_mobile/services/subscription_calculator.dart';

void main() {
  const calc = SubscriptionCalculator();

  group('SubscriptionCalculator.allocatePayment (FIFO, int)', () {
    test('يغلق الأشهر الأقدم بالكامل قبل الانتقال للأحدث', () {
      final dues = [
        const DueLineItem(id: 1, amountDue: 100, amountAlreadyPaid: 0),
        const DueLineItem(id: 2, amountDue: 100, amountAlreadyPaid: 0),
        const DueLineItem(id: 3, amountDue: 100, amountAlreadyPaid: 0),
      ];
      final result = calc.allocatePayment(
        paymentAmount: 150,
        outstandingDuesOldestFirst: dues,
      );
      expect(result.allocations.length, 2);
      expect(result.allocations[0].dueId, 1);
      expect(result.allocations[0].allocatedAmount, 100);
      expect(result.allocations[0].isFullySettled, true);
      expect(result.allocations[1].dueId, 2);
      expect(result.allocations[1].allocatedAmount, 50);
      expect(result.allocations[1].isFullySettled, false);
      expect(result.unallocatedRemainder, 0);
      // شهر 2 متبقٍ منه 50 + شهر 3 كاملًا 100 = 150 متأخرات.
      expect(result.remainingArrearsBalance, 150);
    });

    test('يتخطى الأشهر المسدَّدة بالكامل مسبقًا', () {
      final dues = [
        const DueLineItem(id: 1, amountDue: 100, amountAlreadyPaid: 100),
        const DueLineItem(id: 2, amountDue: 100, amountAlreadyPaid: 0),
      ];
      final result = calc.allocatePayment(
        paymentAmount: 100,
        outstandingDuesOldestFirst: dues,
      );
      expect(result.allocations.length, 1);
      expect(result.allocations.first.dueId, 2);
      expect(result.allocations.first.allocatedAmount, 100);
      expect(result.allocations.first.isFullySettled, true);
      expect(result.remainingArrearsBalance, 0);
    });

    test('يعيد الفائض كمتبقٍّ غير مخصَّص إن غطّت الدفعة كل الأشهر الممرَّرة', () {
      final dues = [
        const DueLineItem(id: 1, amountDue: 100, amountAlreadyPaid: 0),
      ];
      final result = calc.allocatePayment(
        paymentAmount: 250,
        outstandingDuesOldestFirst: dues,
      );
      expect(result.allocations.single.allocatedAmount, 100);
      expect(result.allocations.single.isFullySettled, true);
      expect(result.unallocatedRemainder, 150);
      expect(result.remainingArrearsBalance, 0);
    });

    test('دفعة صفرية أو سالبة لا تخصص شيئًا وتترك كل الأشهر متأخرة', () {
      final dues = [
        const DueLineItem(id: 1, amountDue: 100, amountAlreadyPaid: 0),
        const DueLineItem(id: 2, amountDue: 100, amountAlreadyPaid: 30),
      ];
      final result = calc.allocatePayment(
        paymentAmount: 0,
        outstandingDuesOldestFirst: dues,
      );
      expect(result.allocations, isEmpty);
      expect(result.remainingArrearsBalance, 170); // 100 + (100-30)
    });

    test('لا تتراكم أخطاء فاصلة عائمة عبر عشرات الدفعات الجزئية المتتالية', () {
      // محاكاة 37 دفعة جزئية متتالية على نفس الشهر بمبلغ 2.7 (سيُقرَّب
      // كل واحدة لأقرب عدد صحيح عبر MoneyUtils قبل الوصول هنا، تمامًا
      // كما يفعل SubscriptionRepository._allocatePayment فعليًا).
      var alreadyPaid = 0;
      const dueAmount = 100;
      for (var i = 0; i < 37; i++) {
        final due = DueLineItem(
            id: 1, amountDue: dueAmount, amountAlreadyPaid: alreadyPaid);
        if (due.isFullySettled) break;
        final result = calc.allocatePayment(
          paymentAmount: MoneyUtils.toMinorUnits(2.7),
          outstandingDuesOldestFirst: [due],
        );
        alreadyPaid += result.allocations.isEmpty
            ? 0
            : result.allocations.first.allocatedAmount;
      }
      // 3 (المقرَّب من 2.7) × 34 = 102 ≥ 100 → يُغلق تمامًا عند الدفعة
      // الرابعة والثلاثين بالضبط صفرًا متبقيًا، لا كسرًا وهميًا.
      expect(alreadyPaid >= dueAmount, true);
      final finalDue =
          DueLineItem(id: 1, amountDue: dueAmount, amountAlreadyPaid: alreadyPaid);
      expect(finalDue.openBalance, 0);
      expect(finalDue.isFullySettled, true);
    });
  });
}
