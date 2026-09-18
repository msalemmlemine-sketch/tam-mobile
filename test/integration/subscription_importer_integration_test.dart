import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tam_mobile/models/district.dart';
import 'package:tam_mobile/models/import_models.dart';
import 'package:tam_mobile/models/institution.dart';
import 'package:tam_mobile/models/member.dart';
import 'package:tam_mobile/repositories/district_repository.dart';
import 'package:tam_mobile/repositories/institution_repository.dart';
import 'package:tam_mobile/repositories/member_repository.dart';
import 'package:tam_mobile/repositories/subscription_repository.dart';
import 'package:tam_mobile/services/subscription_importer.dart';

import 'test_helper.dart';

void main() {
  late Directory tempDir;
  final districtRepo = DistrictRepository();
  final institutionRepo = InstitutionRepository();
  final memberRepo = MemberRepository();
  final subRepo = SubscriptionRepository();
  final importer = SubscriptionImporter();

  late int existingMemberId;

  setUp(() async {
    tempDir = await openFreshTestDatabase();

    final now = DateTime.now().toIso8601String();
    final districtId =
        await districtRepo.create(District(name: 'مقاطعة الاستيراد', createdAt: now));
    final institutionId = await institutionRepo
        .create(Institution(districtId: districtId, name: 'مؤسسة الاستيراد', createdAt: now));
    existingMemberId = await memberRepo.create(Member(
      districtId: districtId,
      institutionId: institutionId,
      name: 'أحمد ولد محمد',
      guide: 'AH-1',
      createdAt: now,
      updatedAt: now,
    ));
  });

  tearDown(() async {
    await closeTestDatabase(tempDir);
  });

  Future<String> writeCsv(String content) async {
    final file = File('${tempDir.path}/import.csv');
    await file.writeAsBytes(utf8.encode(content));
    return file.path;
  }

  test('يطابق منتسبًا موجودًا بالاسم + الدليل المالي، ويحسب أشهر سنة كاملة تلقائيًا',
      () async {
    const csv = 'الاسم,الدليل المالي,المبلغ,السنه,تفاصيل الاشتراك\n'
        'أحمد ولد محمد,AH-1,1200,2025,سنة كاملة\n';
    final path = await writeCsv(csv);

    final analysis = await importer.analyze(path);
    expect(analysis.error, isNull);
    expect(analysis.items.length, 1);
    expect(analysis.items.first.matchType, ImportMatchType.exact);
    expect(analysis.items.first.autoMatchedMember?.id, existingMemberId);

    final result = await importer.confirm(analysis.items);
    expect(result.success, isTrue);
    expect(result.added, 1);
    expect(result.total, 1200);

    final payments = await subRepo.paymentsForMember(existingMemberId);
    expect(payments.single.subscriptionAmount, 1200);

    // "سنة كاملة" = 12 شهرًا بلا رسوم بطاقة (التفاصيل لا تذكر "بطاقة").
    expect(payments.single.cardFee, 0);
  });

  test('سجل غير مطابق لأي منتسب حالي يُصنَّف تاريخيًا ولا يُدرَج كدفعة فعلية',
      () async {
    const csv = 'الاسم,المبلغ,السنه\n'
        'شخص غير موجود في اللائحة,500,2025\n';
    final path = await writeCsv(csv);

    final analysis = await importer.analyze(path);
    expect(analysis.items.single.matchType, ImportMatchType.historical);

    final result = await importer.confirm(analysis.items);
    expect(result.success, isTrue);
    expect(result.added, 0);
    expect(result.historical, 1);
  });

  test('تفصيل "بطاقة" في التفاصيل يفصل رسم البطاقة عن قيمة الاشتراك', () async {
    const csv = 'الاسم,الدليل المالي,المبلغ,السنه,تفاصيل الاشتراك\n'
        'أحمد ولد محمد,AH-1,300,2025,اشتراك شهر + رسوم بطاقة\n';
    final path = await writeCsv(csv);

    final analysis = await importer.analyze(path);
    final item = analysis.items.single;
    expect(item.cardFeeCalc, 200); // إعداد card_fee الافتراضي
    expect(item.subscriptionAmountCalc, 100); // 300 - 200
  });

  test('إعادة اعتماد نفس ملف CSV مرتين لا يكرّر السجلات (منع التكرار عبر row_hash)',
      () async {
    const csv = 'الاسم,الدليل المالي,المبلغ,السنه,تفاصيل الاشتراك\n'
        'أحمد ولد محمد,AH-1,1200,2025,سنة كاملة\n';
    final path = await writeCsv(csv);

    final firstAnalysis = await importer.analyze(path);
    final firstResult = await importer.confirm(firstAnalysis.items);
    expect(firstResult.added, 1);

    final secondAnalysis = await importer.analyze(path);
    final secondResult = await importer.confirm(secondAnalysis.items);
    expect(secondResult.added, 0); // نفس row_hash بالضبط -> تجاهل

    final payments = await subRepo.paymentsForMember(existingMemberId);
    expect(payments.length, 1);
  });

  test('الربط اليدوي (manualOverrides) يربط سجلًا غير مطابق تلقائيًا بمنتسب محدَّد',
      () async {
    const csv = 'الاسم,المبلغ,السنه\n'
        'اسم مكتوب بشكل مختلف,400,2025\n';
    final path = await writeCsv(csv);

    final analysis = await importer.analyze(path);
    expect(analysis.items.single.matchType, ImportMatchType.historical);

    final result = await importer.confirm(
      analysis.items,
      manualOverrides: {0: existingMemberId},
    );
    expect(result.added, 1);

    final payments = await subRepo.paymentsForMember(existingMemberId);
    expect(payments.any((p) => p.totalAmount == 400), isTrue);
  });
}
