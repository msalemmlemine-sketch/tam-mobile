import '../models/member.dart';
import '../repositories/district_repository.dart';
import '../repositories/institution_repository.dart';
import '../repositories/member_repository.dart';
import '../repositories/subscription_repository.dart';
import 'subscription_calculator.dart';

class MemberDebtRow {
  final Member member;
  final String institutionName;
  final double totalDue;
  final double totalPaid;
  final double remaining;

  const MemberDebtRow({
    required this.member,
    required this.institutionName,
    required this.totalDue,
    required this.totalPaid,
    required this.remaining,
  });
}

/// صف تقرير منتسب واحد، مع اسم المؤسسة ومعلومات المقاطعة
/// اللازمة للفرز والتصفية في تقرير المنتسبين.
typedef MembersReportRow = ({
  Member member,
  String institutionName,
  int districtId,
  String districtName,
  int districtSortOrder,
});

/// يبني تقارير المنتسبين/المتأخرات — يعتمد على نفس
/// SubscriptionCalculator المستخدم في تفاصيل المنتسب والـ Dashboard
/// حتى تتطابق الأرقام في كل مكان كما اشتُرط.
class ReportService {
  ReportService({
    MemberRepository? memberRepository,
    InstitutionRepository? institutionRepository,
    DistrictRepository? districtRepository,
    SubscriptionRepository? subscriptionRepository,
  })  : _memberRepo = memberRepository ?? MemberRepository(),
        _institutionRepo = institutionRepository ?? InstitutionRepository(),
        _districtRepo = districtRepository ?? DistrictRepository(),
        _subRepo = subscriptionRepository ?? SubscriptionRepository();

  final MemberRepository _memberRepo;
  final InstitutionRepository _institutionRepo;
  final DistrictRepository _districtRepo;
  final SubscriptionRepository _subRepo;
  static const _calculator = SubscriptionCalculator();

  /// تقرير المتأخرات: كل منتسب له رصيد متبقٍ > 0، مرتّبًا تنازليًا.
  /// ملاحظة أداء: يحسب لكل منتسب على حدة (مقبول لآلاف قليلة من
  /// السجلات لأنه تقرير يُطلَب عند الحاجة لا في كل تحديث للشاشة؛
  /// لأعداد ضخمة جدًا يُفضَّل نقل الحساب لاستعلام SQL مجمَّع لاحقًا).
  Future<List<MemberDebtRow>> overdueReport({DateTime? referenceDate}) async {
    final refDate = referenceDate ?? DateTime.now();
    final members = await _memberRepo.search(limit: 100000, offset: 0);
    final settings = await _subRepo.getSettings();
    final monthlyAmount = settings['monthly_amount'] ?? 0.0;
    final institutions = await _institutionRepo.getAll();
    final institutionsById = {for (final i in institutions) i.id: i.name};

    final rows = <MemberDebtRow>[];
    for (final member in members) {
      final totalPaid = await _subRepo.totalSubscriptionPaidByMember(member.id!, year: 2026);
      final months = _calculator.monthsElapsed(
        firstDueDate: DateTime(2026, 1, 1),
        referenceDate: refDate,
        statusDate: member.statusDate != null ? DateTime.parse(member.statusDate!) : null,
        isActive: member.membershipStatus == 'active',
      );
      final totalDue = _calculator.totalDue(monthsElapsed: months, monthlyAmount: monthlyAmount);
      final remaining = _calculator.remainingBalance(totalDue: totalDue, totalPaid: totalPaid);
      if (remaining > 0) {
        rows.add(MemberDebtRow(
          member: member,
          institutionName: institutionsById[member.institutionId] ?? '—',
          totalDue: totalDue,
          totalPaid: totalPaid,
          remaining: remaining,
        ));
      }
    }
    rows.sort((a, b) => b.remaining.compareTo(a.remaining));
    return rows;
  }

  /// تقرير المنتسبين مع اسم المؤسسة والمقاطعة، بتصفية اختيارية:
  /// - institutionId: يقتصر التقرير على مؤسسة واحدة بعينها.
  /// - districtId: يقتصر التقرير على كل مؤسسات مقاطعة بعينها.
  /// إن أُرسل الاثنان معًا يُعتمَد institutionId ويُتجاهَل
  /// districtId (تصفية أدقّ تفوز).
  Future<List<MembersReportRow>> membersReport({
    int? institutionId,
    int? districtId,
  }) async {
    final institutions = await _institutionRepo.getAll();
    final districts = await _districtRepo.getAll();
    final districtsById = {for (final d in districts) d.id: d};
    final institutionsById = {for (final i in institutions) i.id: i};

    List<Member> members;
    if (institutionId != null) {
      members = await _memberRepo.search(
        institutionId: institutionId,
        limit: 100000,
        offset: 0,
      );
    } else {
      members = await _memberRepo.search(limit: 100000, offset: 0);
      if (districtId != null) {
        final idsInDistrict = institutions
            .where((i) => i.districtId == districtId)
            .map((i) => i.id)
            .toSet();
        members = members.where((m) => idsInDistrict.contains(m.institutionId)).toList();
      }
    }

    return members.map((m) {
      final inst = institutionsById[m.institutionId];
      final dist = inst != null ? districtsById[inst.districtId] : null;
      return (
        member: m,
        institutionName: inst?.name ?? '—',
        districtId: inst?.districtId ?? 0,
        districtName: dist?.name ?? '—',
        districtSortOrder: dist?.sortOrder ?? 0,
      );
    }).toList();
  }
}
