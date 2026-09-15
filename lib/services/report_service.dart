import '../models/member.dart';
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

/// يبني تقارير المنتسبين/المتأخرات — يعتمد على نفس
/// SubscriptionCalculator المستخدم في تفاصيل المنتسب والـ Dashboard
/// حتى تتطابق الأرقام في كل مكان كما اشتُرط.
class ReportService {
  ReportService({
    MemberRepository? memberRepository,
    InstitutionRepository? institutionRepository,
    SubscriptionRepository? subscriptionRepository,
  })  : _memberRepo = memberRepository ?? MemberRepository(),
        _institutionRepo = institutionRepository ?? InstitutionRepository(),
        _subRepo = subscriptionRepository ?? SubscriptionRepository();

  final MemberRepository _memberRepo;
  final InstitutionRepository _institutionRepo;
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
      final firstDateStr = await _subRepo.firstPaymentDate(member.id!);
      final totalPaid = await _subRepo.totalSubscriptionPaidByMember(member.id!);

      double totalDue = 0;
      if (firstDateStr != null) {
        final firstDate = DateTime.parse(firstDateStr);
        final months = _calculator.monthsElapsed(
          firstDueDate: DateTime(firstDate.year, firstDate.month, 1),
          referenceDate: refDate,
          statusDate: member.statusDate != null ? DateTime.parse(member.statusDate!) : null,
          isActive: member.membershipStatus == 'active',
        );
        totalDue = _calculator.totalDue(monthsElapsed: months, monthlyAmount: monthlyAmount);
      }
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

  /// تقرير المنتسبين مع اسم المؤسسة، بتصفية اختيارية حسب المؤسسة.
  Future<List<({Member member, String institutionName})>> membersReport({
    int? institutionId,
  }) async {
    final members = await _memberRepo.search(
      institutionId: institutionId,
      limit: 100000,
      offset: 0,
    );
    final institutions = await _institutionRepo.getAll();
    final institutionsById = {for (final i in institutions) i.id: i.name};
    return members
        .map((m) => (member: m, institutionName: institutionsById[m.institutionId] ?? '—'))
        .toList();
  }
}
