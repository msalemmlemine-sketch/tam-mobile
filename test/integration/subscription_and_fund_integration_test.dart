import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tam_mobile/models/district.dart';
import 'package:tam_mobile/models/institution.dart';
import 'package:tam_mobile/models/member.dart';
import 'package:tam_mobile/models/regional_expense.dart';
import 'package:tam_mobile/models/subscription_payment.dart';
import 'package:tam_mobile/repositories/district_repository.dart';
import 'package:tam_mobile/repositories/fund_repository.dart';
import 'package:tam_mobile/repositories/institution_repository.dart';
import 'package:tam_mobile/repositories/member_repository.dart';
import 'package:tam_mobile/repositories/subscription_repository.dart';
import 'package:tam_mobile/services/fund_service.dart';

import 'test_helper.dart';

void main() {
  late Directory tempDir;
  final districtRepo = DistrictRepository();
  final institutionRepo = InstitutionRepository();
  final memberRepo = MemberRepository();
  final subRepo = SubscriptionRepository();
  final fundRepo = FundRepository();
  final fundService = FundService();

  Future<int> createMember(String name) async {
    final now = DateTime.now().toIso8601String();
    final districtId =
        await districtRepo.create(District(name: 'مقاطعة', createdAt: now));
    final institutionId = await institutionRepo
        .create(Institution(districtId: districtId, name: 'مؤسسة', createdAt: now));
    return memberRepo.create(Member(
      districtId: districtId,
      institutionId: institutionId,
      name: name,
      createdAt: now,
      updatedAt: now,
    ));
  }

  setUp(() async {
    tempDir = await openFreshTestDatabase();
  });

  tearDown(() async {
    await closeTestDatabase(tempDir);
  });

  test('إعدادات الاشتراك الافتراضية تُزرع تلقائيًا عند إنشاء القاعدة', () async {
    final settings = await subRepo.getSettings();
    expect(settings['monthly_amount'], 100);
    expect(settings['card_fee'], 200);
    expect(settings['executive_share_percent'], 70);
    expect(settings['regional_share_percent'], 30);
  });

  test('تسجيل دفعات اشتراك يراكم إجمالي المدفوع للمنتسب بشكل صحيح', () async {
    final memberId = await createMember('منتسب الاشتراكات');
    final now = DateTime.now().toIso8601String();

    for (final month in [1, 2, 3]) {
      await subRepo.recordPayment(SubscriptionPayment(
        memberId: memberId,
        paymentYear: 2025,
        paymentMonth: month,
        paymentDate: '2025-0${month.clamp(1, 9)}-01',
        subscriptionAmount: 100,
        createdAt: now,
      ));
    }

    final total = await subRepo.totalSubscriptionPaidByMember(memberId);
    expect(total, 300);

    final payments = await subRepo.paymentsForMember(memberId);
    expect(payments.length, 3);

    final firstDate = await subRepo.firstPaymentDate(memberId);
    expect(firstDate, '2025-01-01');
  });

  test('الصندوق السنوي: يحسب المداخيل من حصة الجهوي فقط، ويستبعد الدفعات المباشرة للتنفيذي',
      () async {
    final memberId = await createMember('دافع الاشتراك');
    final now = DateTime.now().toIso8601String();

    // دفعة عادية 1000 -> حصة الجهوي 30% = 300
    await subRepo.recordPayment(SubscriptionPayment(
      memberId: memberId,
      paymentYear: 2025,
      subscriptionAmount: 1000,
      createdAt: now,
    ));
    // دفعة مباشرة للتنفيذي -> لا تدخل في حصة الجهوي إطلاقًا
    await subRepo.recordPayment(SubscriptionPayment(
      memberId: memberId,
      paymentYear: 2025,
      subscriptionAmount: 500,
      directToExecutive: true,
      createdAt: now,
    ));

    await fundRepo.addExpense(RegionalExpense(
      expenseDate: '2025-06-15',
      amount: 120,
      createdAt: now,
    ));

    final summary = await fundService.summaryForYear(2025);
    expect(summary.openingBalance, 0);
    expect(summary.income, 300); // 1000 * 30% فقط، بدون الدفعة المباشرة
    expect(summary.expenses, 120);
    expect(summary.closingBalance, 180);
  });

  test('الرصيد الختامي لسنة يُرحَّل تلقائيًا كرصيد افتتاحي للسنة التالية',
      () async {
    final memberId = await createMember('دافع متعدد السنوات');
    final now = DateTime.now().toIso8601String();

    await subRepo.recordPayment(SubscriptionPayment(
      memberId: memberId,
      paymentYear: 2024,
      subscriptionAmount: 1000,
      createdAt: now,
    ));
    await fundRepo.addExpense(
        RegionalExpense(expenseDate: '2024-03-01', amount: 100, createdAt: now));

    final summary2024 = await fundService.summaryForYear(2024);
    expect(summary2024.closingBalance, 200); // (1000*30%) - 100 = 200

    await subRepo.recordPayment(SubscriptionPayment(
      memberId: memberId,
      paymentYear: 2025,
      subscriptionAmount: 500,
      createdAt: now,
    ));

    final summary2025 = await fundService.summaryForYear(2025);
    expect(summary2025.openingBalance, 200); // نفس رصيد إغلاق 2024 بالضبط
    expect(summary2025.income, 150); // 500*30%
    expect(summary2025.closingBalance, 350);
  });

  test('رصيد افتتاحي يدوي (fund_opening_overrides) يجعل السنة تبدأ منه بدل الصفر',
      () async {
    await fundRepo.setOpeningOverride(2023, 5000, DateTime.now().toIso8601String());
    final summary = await fundService.summaryForYear(2023);
    expect(summary.openingBalance, 5000);
    expect(summary.openingIsManualOverride, isTrue);
    expect(summary.closingBalance, 5000); // لا مداخيل ولا مصاريف مسجَّلة
  });
}
