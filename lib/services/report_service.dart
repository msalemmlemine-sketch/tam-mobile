import '../models/member.dart';
import '../models/institution.dart';
import '../repositories/institution_repository.dart';
import '../repositories/member_repository.dart';
import '../repositories/subscription_repository.dart';
import '../repositories/district_repository.dart';
import 'subscription_calculator.dart';

class MemberDebtRow {
  final Member member;
  final String institutionName;
  final String districtName;
  final double totalDue;
  final double totalPaid;
  final double remaining;

  const MemberDebtRow({
    required this.member,
    required this.institutionName,
    required this.districtName,
    required this.totalDue,
    required this.totalPaid,
    required this.remaining,
  });
}

class MemberReportRow {
  final Member member;
  final String institutionName;
  final String districtName;

  const MemberReportRow({
    required this.member,
    required this.institutionName,
    required this.districtName,
  });
}

class InstitutionMemberReport {
  final Institution institution;
  final String districtName;
  final List<Member> members;

  const InstitutionMemberReport({
    required this.institution,
    required this.districtName,
    required this.members,
  });

  int get memberCount => members.length;

  int get totalStaff => institution.totalStaff;

  double? get membershipRate {
    if (totalStaff <= 0) return null;
    return memberCount * 100 / totalStaff;
  }
}

class DistrictMemberReport {
  final int? districtId;
  final String districtName;
  final List<InstitutionMemberReport> institutions;

  const DistrictMemberReport({
    required this.districtId,
    required this.districtName,
    required this.institutions,
  });

  int get institutionCount => institutions.length;

  int get memberCount =>
      institutions.fold(0, (sum, item) => sum + item.memberCount);
}

class MembersGroupedReport {
  final List<DistrictMemberReport> districts;

  const MembersGroupedReport({
    required this.districts,
  });

  int get districtCount => districts.length;

  int get institutionCount =>
      districts.fold(0, (sum, district) => sum + district.institutionCount);

  int get memberCount =>
      districts.fold(0, (sum, district) => sum + district.memberCount);

  List<InstitutionMemberReport> get allInstitutions => [
        for (final district in districts) ...district.institutions,
      ];
}

class InstitutionReportRow {
  final Institution institution;
  final String districtName;
  final int tamMembers;

  const InstitutionReportRow({
    required this.institution,
    required this.districtName,
    required this.tamMembers,
  });

  int get totalStaff => institution.totalStaff;

  double? get tamPercentage {
    if (totalStaff <= 0) return null;
    return tamMembers * 100 / totalStaff;
  }

  int get classifiedStaff =>
      tamMembers +
      institution.sipesMembers +
      institution.snesMembers +
      institution.otherUnionMembers +
      institution.nonUnionStaff;

  int get unclassifiedStaff {
    final value = totalStaff - classifiedStaff;
    return value < 0 ? 0 : value;
  }

  bool get hasNoMembers => tamMembers == 0;

  bool get hasStaffData => totalStaff > 0;
}

class InstitutionsReport {
  final List<InstitutionReportRow> rows;

  const InstitutionsReport({
    required this.rows,
  });

  int get institutionCount => rows.length;

  int get institutionsWithMembers =>
      rows.where((row) => row.tamMembers > 0).length;

  int get institutionsWithoutMembers =>
      rows.where((row) => row.tamMembers == 0).length;

  int get totalStaff =>
      rows.fold(0, (sum, row) => sum + row.totalStaff);

  int get totalTamMembers =>
      rows.fold(0, (sum, row) => sum + row.tamMembers);

  int get totalSipes =>
      rows.fold(0, (sum, row) => sum + row.institution.sipesMembers);

  int get totalSnes =>
      rows.fold(0, (sum, row) => sum + row.institution.snesMembers);

  int get totalOtherUnion =>
      rows.fold(0, (sum, row) => sum + row.institution.otherUnionMembers);

  int get totalNonUnion =>
      rows.fold(0, (sum, row) => sum + row.institution.nonUnionStaff);

  int get totalUnclassified =>
      rows.fold(0, (sum, row) => sum + row.unclassifiedStaff);

  double? get tamPercentage {
    if (totalStaff <= 0) return null;
    return totalTamMembers * 100 / totalStaff;
  }
}

class ReportAnalysis {
  final int totalMembers;
  final int totalInstitutions;
  final int totalDistricts;
  final int institutionsWithMembers;
  final int institutionsWithoutMembers;
  final int institutionsWithoutStaffData;
  final int totalStaff;
  final int totalTamMembers;
  final double? overallMembershipRate;

  const ReportAnalysis({
    required this.totalMembers,
    required this.totalInstitutions,
    required this.totalDistricts,
    required this.institutionsWithMembers,
    required this.institutionsWithoutMembers,
    required this.institutionsWithoutStaffData,
    required this.totalStaff,
    required this.totalTamMembers,
    required this.overallMembershipRate,
  });

  List<String> get recommendations {
    final result = <String>[];

    if (institutionsWithoutMembers > 0) {
      result.add(
        'مراجعة المؤسسات التي لا يوجد بها منتسبون مسجلون والتحقق من صحة البيانات.',
      );
    }

    if (institutionsWithoutStaffData > 0) {
      result.add(
        'استكمال بيانات عدد العاملين في المؤسسات التي لا تتوفر لها بيانات الطاقم.',
      );
    }

    if (overallMembershipRate != null &&
        overallMembershipRate! < 50) {
      result.add(
        'تكثيف المتابعة التنظيمية في المؤسسات ذات نسبة الانتساب المحدودة.',
      );
    }

    if (totalMembers == 0) {
      result.add(
        'لا توجد بيانات منتسبين مسجلة حاليًا، ويُنصح بمراجعة سجل العضوية.',
      );
    }

    if (result.isEmpty) {
      result.add(
        'تُظهر البيانات الحالية تغطية جيدة للمؤسسات المسجلة، مع الاستمرار في تحديث السجل.',
      );
    }

    return result;
  }
}

class ReportService {
  ReportService({
    MemberRepository? memberRepository,
    InstitutionRepository? institutionRepository,
    SubscriptionRepository? subscriptionRepository,
    DistrictRepository? districtRepository,
  })  : _memberRepo = memberRepository ?? MemberRepository(),
        _institutionRepo =
            institutionRepository ?? InstitutionRepository(),
        _subRepo =
            subscriptionRepository ?? SubscriptionRepository(),
        _districtRepo =
            districtRepository ?? DistrictRepository();

  final MemberRepository _memberRepo;
  final InstitutionRepository _institutionRepo;
  final SubscriptionRepository _subRepo;
  final DistrictRepository _districtRepo;

  static const _calculator = SubscriptionCalculator();

  Future<List<MemberReportRow>> membersReport({
    int? institutionId,
    int? districtId,
    bool includeArchived = false,
  }) async {
    final members = await _memberRepo.search(
      institutionId: institutionId,
      districtId: districtId,
      includeArchived: includeArchived,
      limit: 100000,
      offset: 0,
    );

    final institutions = await _institutionRepo.getAll();
    final districts = await _districtRepo.getAll();

    final institutionsById = {
      for (final item in institutions)
        if (item.id != null) item.id!: item,
    };

    final districtsById = {
      for (final item in districts)
        if (item.id != null) item.id!: item.name,
    };

    final result = members
        .map(
          (member) => MemberReportRow(
            member: member,
            institutionName:
                institutionsById[member.institutionId]?.name ?? 'غير محددة',
            districtName:
                districtsById[member.districtId] ?? 'غير محددة',
          ),
        )
        .toList();

    result.sort((a, b) {
      final district = a.districtName.compareTo(b.districtName);
      if (district != 0) return district;

      final institution =
          a.institutionName.compareTo(b.institutionName);
      if (institution != 0) return institution;

      return a.member.name.compareTo(b.member.name);
    });

    return result;
  }

  Future<MembersGroupedReport> membersGroupedReport({
    int? institutionId,
    int? districtId,
    bool includeArchived = false,
    bool includeEmptyInstitutions = true,
  }) async {
    final members = await _memberRepo.search(
      institutionId: institutionId,
      districtId: districtId,
      includeArchived: includeArchived,
      limit: 100000,
      offset: 0,
    );

    final institutions = await _institutionRepo.getAll(
      districtId: districtId,
    );

    final districts = await _districtRepo.getAll();

    final districtNames = {
      for (final district in districts)
        if (district.id != null) district.id!: district.name,
    };

    final membersByInstitution = <int, List<Member>>{};

    for (final member in members) {
      membersByInstitution
          .putIfAbsent(member.institutionId, () => [])
          .add(member);
    }

    for (final list in membersByInstitution.values) {
      list.sort(
        (a, b) => a.name.compareTo(b.name),
      );
    }

    final institutionReports = <InstitutionMemberReport>[];

    for (final institution in institutions) {
      if (institution.id == null) continue;

      final institutionMembers =
          membersByInstitution[institution.id!] ?? <Member>[];

      if (!includeEmptyInstitutions &&
          institutionMembers.isEmpty) {
        continue;
      }

      institutionReports.add(
        InstitutionMemberReport(
          institution: institution,
          districtName:
              districtNames[institution.districtId] ??
                  'غير محددة',
          members: List<Member>.unmodifiable(
            institutionMembers,
          ),
        ),
      );
    }

    institutionReports.sort((a, b) {
      final district =
          a.districtName.compareTo(b.districtName);

      if (district != 0) return district;

      return a.institution.name.compareTo(
        b.institution.name,
      );
    });

    final grouped = <String, List<InstitutionMemberReport>>{};

    for (final report in institutionReports) {
      grouped
          .putIfAbsent(
            report.districtName,
            () => [],
          )
          .add(report);
    }

    final districtOrder = <String>[
      for (final district in districts) district.name,
    ];

    final orderedDistrictNames = <String>[
      ...districtOrder.where(grouped.containsKey),
      ...grouped.keys.where(
        (name) => !districtOrder.contains(name),
      ),
    ];

    final districtReports = <DistrictMemberReport>[];

    for (final name in orderedDistrictNames) {
      final reports = grouped[name];

      if (reports == null || reports.isEmpty) continue;

      int? id;

      for (final report in reports) {
        final matchingDistrict = districts.where(
          (district) => district.name == report.districtName,
        );

        if (matchingDistrict.isNotEmpty) {
          id = matchingDistrict.first.id;
          break;
        }
      }

      districtReports.add(
        DistrictMemberReport(
          districtId: id,
          districtName: name,
          institutions: List.unmodifiable(reports),
        ),
      );
    }

    return MembersGroupedReport(
      districts: List.unmodifiable(districtReports),
    );
  }

  Future<InstitutionsReport> institutionsReport({
    int? districtId,
  }) async {
    final analytics =
        await _institutionRepo.getAnalytics(
      districtId: districtId,
    );

    final rows = analytics
        .map(
          (item) => InstitutionReportRow(
            institution: item.institution,
            districtName: item.districtName,
            tamMembers: item.tamMembers,
          ),
        )
        .toList();

    rows.sort((a, b) {
      final district =
          a.districtName.compareTo(b.districtName);

      if (district != 0) return district;

      return a.institution.name.compareTo(
        b.institution.name,
      );
    });

    return InstitutionsReport(
      rows: List.unmodifiable(rows),
    );
  }

  Future<ReportAnalysis> membersAnalysis({
    int? districtId,
  }) async {
    final grouped = await membersGroupedReport(
      districtId: districtId,
      includeEmptyInstitutions: true,
    );

    final institutions =
        await institutionsReport(
      districtId: districtId,
    );

    final institutionsWithoutStaffData =
        institutions.rows
            .where((row) => row.totalStaff <= 0)
            .length;

    final totalStaff = institutions.totalStaff;
    final totalMembers = grouped.memberCount;

    final overallRate = totalStaff > 0
        ? totalMembers * 100 / totalStaff
        : null;

    return ReportAnalysis(
      totalMembers: totalMembers,
      totalInstitutions:
          grouped.institutionCount,
      totalDistricts:
          grouped.districtCount,
      institutionsWithMembers:
          institutions.institutionsWithMembers,
      institutionsWithoutMembers:
          institutions.institutionsWithoutMembers,
      institutionsWithoutStaffData:
          institutionsWithoutStaffData,
      totalStaff: totalStaff,
      totalTamMembers:
          institutions.totalTamMembers,
      overallMembershipRate: overallRate,
    );
  }

  Future<List<MemberDebtRow>> overdueReport({
    DateTime? referenceDate,
    int year = 2026,
    int? institutionId,
    int? districtId,
  }) async {
    final refDate =
        referenceDate ?? DateTime.now();

    final members = await _memberRepo.search(
      institutionId: institutionId,
      districtId: districtId,
      limit: 100000,
      offset: 0,
    );

    final settings =
        await _subRepo.getSettings();

    final monthlyAmount =
        settings['monthly_amount'] ?? 0.0;

    final institutions =
        await _institutionRepo.getAll();

    final districts =
        await _districtRepo.getAll();

    final institutionsById = {
      for (final institution in institutions)
        if (institution.id != null)
          institution.id!: institution.name,
    };

    final districtsById = {
      for (final district in districts)
        if (district.id != null)
          district.id!: district.name,
    };

    final rows = <MemberDebtRow>[];

    for (final member in members) {
      if (member.id == null) continue;

      final totalPaid =
          await _subRepo.totalSubscriptionPaidByMember(
        member.id!,
        year: year,
      );

      final statusDate =
          member.statusDate == null
              ? null
              : DateTime.tryParse(
                  member.statusDate!,
                );

      final months =
          _calculator.monthsElapsed(
        firstDueDate: DateTime(year, 1, 1),
        referenceDate: refDate,
        statusDate: statusDate,
        isActive:
            member.membershipStatus == 'active',
      );

      final totalDue =
          _calculator.totalDue(
        monthsElapsed: months,
        monthlyAmount: monthlyAmount,
      );

      final remaining =
          _calculator.remainingBalance(
        totalDue: totalDue,
        totalPaid: totalPaid,
      );

      if (remaining <= 0) continue;

      rows.add(
        MemberDebtRow(
          member: member,
          institutionName:
              institutionsById[member.institutionId] ??
                  'غير محددة',
          districtName:
              districtsById[member.districtId] ??
                  'غير محددة',
          totalDue: totalDue,
          totalPaid: totalPaid,
          remaining: remaining,
        ),
      );
    }

    rows.sort((a, b) {
      final district =
          a.districtName.compareTo(b.districtName);

      if (district != 0) return district;

      final institution =
          a.institutionName.compareTo(
        b.institutionName,
      );

      if (institution != 0) return institution;

      final debt =
          b.remaining.compareTo(a.remaining);

      if (debt != 0) return debt;

      return a.member.name.compareTo(
        b.member.name,
      );
    });

    return rows;
  }

  Future<List<MemberDebtRow>> membersWithNoPayment({
    int year = 2026,
    int? institutionId,
    int? districtId,
  }) async {
    final members = await _memberRepo.search(
      institutionId: institutionId,
      districtId: districtId,
      limit: 100000,
      offset: 0,
    );

    final institutions =
        await _institutionRepo.getAll();

    final districts =
        await _districtRepo.getAll();

    final institutionsById = {
      for (final institution in institutions)
        if (institution.id != null)
          institution.id!: institution.name,
    };

    final districtsById = {
      for (final district in districts)
        if (district.id != null)
          district.id!: district.name,
    };

    final result = <MemberDebtRow>[];

    for (final member in members) {
      if (member.id == null) continue;

      final paid =
          await _subRepo.totalSubscriptionPaidByMember(
        member.id!,
        year: year,
      );

      if (paid > 0) continue;

      result.add(
        MemberDebtRow(
          member: member,
          institutionName:
              institutionsById[member.institutionId] ??
                  'غير محددة',
          districtName:
              districtsById[member.districtId] ??
                  'غير محددة',
          totalDue: 0,
          totalPaid: 0,
          remaining: 0,
        ),
      );
    }

    result.sort((a, b) {
      final district =
          a.districtName.compareTo(b.districtName);

      if (district != 0) return district;

      final institution =
          a.institutionName.compareTo(
        b.institutionName,
      );

      if (institution != 0) return institution;

      return a.member.name.compareTo(
        b.member.name,
      );
    });

    return result;
  }

  Future<Map<String, int>> membersCountByInstitution({
    int? districtId,
  }) async {
    final grouped = await membersGroupedReport(
      districtId: districtId,
      includeEmptyInstitutions: true,
    );

    final result = <String, int>{};

    for (final district in grouped.districts) {
      for (final institution
          in district.institutions) {
        result[
          institution.institution.name
        ] = institution.memberCount;
      }
    }

    return result;
  }
}
