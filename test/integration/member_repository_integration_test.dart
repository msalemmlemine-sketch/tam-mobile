import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tam_mobile/models/district.dart';
import 'package:tam_mobile/models/institution.dart';
import 'package:tam_mobile/models/member.dart';
import 'package:tam_mobile/repositories/district_repository.dart';
import 'package:tam_mobile/repositories/institution_repository.dart';
import 'package:tam_mobile/repositories/member_repository.dart';

import 'test_helper.dart';

void main() {
  late Directory tempDir;
  final districtRepo = DistrictRepository();
  final institutionRepo = InstitutionRepository();
  final memberRepo = MemberRepository();

  setUp(() async {
    tempDir = await openFreshTestDatabase();
  });

  tearDown(() async {
    await closeTestDatabase(tempDir);
  });

  test('ينشئ قاعدة البيانات فارغة بجداولها الأساسية عند أول فتح', () async {
    expect(await memberRepo.countAll(), 0);
    expect(await districtRepo.getAll(), isEmpty);
  });

  test('يضيف مقاطعة ثم مؤسسة تابعة لها ثم منتسبًا فيها', () async {
    final now = DateTime.now().toIso8601String();
    final districtId = await districtRepo.create(
      District(name: 'نواكشوط الغربية', createdAt: now),
    );
    final institutionId = await institutionRepo.create(
      Institution(districtId: districtId, name: 'ثانوية الميناء', createdAt: now),
    );
    final memberId = await memberRepo.create(Member(
      districtId: districtId,
      institutionId: institutionId,
      name: 'أحمد ولد محمد',
      guide: 'AH-001',
      createdAt: now,
      updatedAt: now,
    ));

    final fetched = await memberRepo.getById(memberId);
    expect(fetched, isNotNull);
    expect(fetched!.name, 'أحمد ولد محمد');
    expect(fetched.districtId, districtId);
    expect(fetched.institutionId, institutionId);
    expect(await memberRepo.countAll(), 1);
    expect(await institutionRepo.countMembers(institutionId), 1);
  });

  test('البحث بالاسم الجزئي والدليل المالي يعمل عبر الفهارس', () async {
    final now = DateTime.now().toIso8601String();
    final districtId =
        await districtRepo.create(District(name: 'د1', createdAt: now));
    final institutionId = await institutionRepo.create(
        Institution(districtId: districtId, name: 'م1', createdAt: now));

    for (final entry in [
      ('فاطمة منت أحمد', 'FT-1'),
      ('محمد ولد سيدي', 'MD-2'),
      ('مريم بنت الشيخ', 'MR-3'),
    ]) {
      await memberRepo.create(Member(
        districtId: districtId,
        institutionId: institutionId,
        name: entry.$1,
        guide: entry.$2,
        createdAt: now,
        updatedAt: now,
      ));
    }

    final byName = await memberRepo.search(query: 'محمد');
    expect(byName.map((m) => m.name), contains('محمد ولد سيدي'));

    final byGuide = await memberRepo.search(query: 'FT-1');
    expect(byGuide.single.name, 'فاطمة منت أحمد');

    expect(await memberRepo.countSearch(query: 'منت'), 1);
  });

  test('الأرشفة (الحذف الناعم) تُخفي المنتسب من countAll الافتراضي لكنه يبقى قابلًا للاسترجاع',
      () async {
    final now = DateTime.now().toIso8601String();
    final districtId =
        await districtRepo.create(District(name: 'د', createdAt: now));
    final institutionId = await institutionRepo
        .create(Institution(districtId: districtId, name: 'م', createdAt: now));
    final memberId = await memberRepo.create(Member(
      districtId: districtId,
      institutionId: institutionId,
      name: 'منتسب للأرشفة',
      createdAt: now,
      updatedAt: now,
    ));

    await memberRepo.archive(memberId, DateTime.now().toIso8601String());

    expect(await memberRepo.countAll(), 0);
    expect(await memberRepo.countAll(includeArchived: true), 1);
    final archived = await memberRepo.getById(memberId);
    expect(archived!.isArchived, isTrue);

    await memberRepo.unarchive(memberId, DateTime.now().toIso8601String());
    expect(await memberRepo.countAll(), 1);
  });

  test('حذف مقاطعة بها مؤسسة يفشل بسبب ON DELETE RESTRICT (سلامة العلاقات)',
      () async {
    final now = DateTime.now().toIso8601String();
    final districtId =
        await districtRepo.create(District(name: 'محمية', createdAt: now));
    await institutionRepo
        .create(Institution(districtId: districtId, name: 'مؤسسة', createdAt: now));

    expect(() => districtRepo.delete(districtId), throwsException);
  });
}
