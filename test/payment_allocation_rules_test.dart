import 'package:flutter_test/flutter_test.dart';
import 'package:tam_mobile/services/subscription_calculator.dart';

void main() {
  const c = SubscriptionCalculator();
  test('yearly due from January 2026 through September is 9 months', () {
    expect(c.monthsElapsed(firstDueDate: DateTime(2026,1,1), referenceDate: DateTime(2026,9,16), isActive: true), 9);
  });
  test('partial payment leaves a positive balance', () {
    expect(c.remainingBalance(totalDue: 600, totalPaid: 250), 350);
  });
  test('prepaid amount never creates negative remaining balance', () {
    expect(c.remainingBalance(totalDue: 1200, totalPaid: 1500), 0);
  });
}
