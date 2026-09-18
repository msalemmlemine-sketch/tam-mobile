import 'package:flutter/material.dart';

import '../../models/institution.dart';
import '../../models/member.dart';
import '../../models/subscription_payment.dart';
import '../../repositories/institution_repository.dart';
import '../../repositories/member_repository.dart';
import '../../repositories/subscription_repository.dart';
import '../../services/auth_service.dart';
import '../../services/permission_service.dart';
import '../../services/subscription_calculator.dart';
import '../auth/change_password_screen.dart';
import '../auth_gate.dart';

/// شاشة "وضعيتي المالية" — الحساب الذاتي للمنتسب. للقراءة فقط:
/// لا تعديل ولا تجميد ولا أرشفة ولا حذف، فقط عرض نفس الأرقام التي
/// يراها الإداري في تفاصيل المنتسب (المستحق/المدفوع/المتبقي وسجل
/// الدفعات)، لأن هذا الحساب أُنشئ آليًا بالدليل المالي وكلمة مرور
/// هي رقم الهاتف (انظر UserRepository.ensureMemberAccount).
class MemberSelfStatusScreen extends StatefulWidget {
  const MemberSelfStatusScreen({super.key});

  @override
  State<MemberSelfStatusScreen> createState() => _MemberSelfStatusScreenState();
}

class _MemberSelfStatusScreenState extends State<MemberSelfStatusScreen> {
  final _memberRepo = MemberRepository();
  final _institutionRepo = InstitutionRepository();
  final _subRepo = SubscriptionRepository();
  static const _calculator = SubscriptionCalculator();

  late Future<_SelfData?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SelfData?> _load() async {
    final memberId = PermissionService.currentUser?.memberId;
    if (memberId == null) return null;
    final member = await _memberRepo.getById(memberId);
    if (member == null) return null;
    final institution = await _institutionRepo.getById(member.institutionId);
    final payments = await _subRepo.paymentsForMember(memberId);
    final totalPaid = await _subRepo.totalSubscriptionPaidByMember(memberId);
    final firstDateStr = await _subRepo.firstPaymentDate(memberId);
    final settings = await _subRepo.getSettings();
    final monthlyAmount = settings['monthly_amount'] ?? 0;

    double totalDue = 0;
    int months = 0;
    if (firstDateStr != null) {
      final firstDate = DateTime.parse(firstDateStr);
      months = _calculator.monthsElapsed(
        firstDueDate: DateTime(firstDate.year, firstDate.month, 1),
        referenceDate: DateTime.now(),
        statusDate: member.statusDate != null ? DateTime.parse(member.statusDate!) : null,
        isActive: member.membershipStatus == 'active',
      );
      totalDue = _calculator.totalDue(monthsElapsed: months, monthlyAmount: monthlyAmount);
    }
    final remaining = _calculator.remainingBalance(totalDue: totalDue, totalPaid: totalPaid);

    return _SelfData(
      member: member,
      institution: institution,
      payments: payments,
      totalPaid: totalPaid,
      totalDue: totalDue,
      remaining: remaining,
      monthsElapsed: months,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('وضعيتي المالية'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              final user = PermissionService.currentUser;
              if (value == 'password' && user != null) {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChangePasswordScreen(userId: user.id, isForced: false),
                ));
              } else if (value == 'logout') {
                await AuthService().logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthGate()), (route) => false);
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'password', child: Text('تغيير كلمة المرور')),
              PopupMenuItem(value: 'logout', child: Text('تسجيل الخروج')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<_SelfData?>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData && snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('تعذّر العثور على بيانات المنتسب المرتبطة بهذا الحساب.', textAlign: TextAlign.center),
            ));
          }
          final m = data.member;
          return RefreshIndicator(
            onRefresh: () async { final f = _load(); setState(() => _future = f); await f; },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(m.name, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(data.institution?.name ?? '—', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row('الدليل المالي', m.guide ?? '—'),
                        _row('رقم البطاقة', m.cardNo ?? '—'),
                        _row('الهاتف', m.phone ?? '—'),
                        _row('الحالة', _statusLabel(m.membershipStatus)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('حالة الاشتراك', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        _row('الأشهر المستحقة', '${data.monthsElapsed}'),
                        _row('إجمالي المستحق', '${data.totalDue.toStringAsFixed(0)} أوقية'),
                        _row('إجمالي المدفوع', '${data.totalPaid.toStringAsFixed(0)} أوقية'),
                        _row('المتبقي', '${data.remaining.toStringAsFixed(0)} أوقية',
                            valueColor: data.remaining > 0 ? Colors.red.shade700 : Colors.green.shade700),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('سجل الدفعات', style: Theme.of(context).textTheme.titleMedium),
                if (data.payments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('لا توجد دفعات مسجَّلة بعد'),
                  )
                else
                  ...data.payments.map((p) => Card(
                        child: ListTile(
                          title: Text('${p.subscriptionAmount.toStringAsFixed(0)} أوقية'),
                          subtitle: Text('سنة ${p.paymentYear}'
                              '${p.paymentMonth != null ? ' — شهر ${p.paymentMonth}' : ''}'
                              '${p.paymentDate != null ? ' — ${p.paymentDate}' : ''}'),
                          trailing: p.directToExecutive ? const Chip(label: Text('مباشر للتنفيذي')) : null,
                        ),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: valueColor)),
          ],
        ),
      );

  String _statusLabel(String status) => switch (status) {
        'active' => 'نشط',
        'inactive' => 'غير نشط',
        'suspended' => 'موقوف',
        _ => status,
      };
}

class _SelfData {
  final Member member;
  final Institution? institution;
  final List<SubscriptionPayment> payments;
  final double totalPaid;
  final double totalDue;
  final double remaining;
  final int monthsElapsed;

  _SelfData({
    required this.member,
    required this.institution,
    required this.payments,
    required this.totalPaid,
    required this.totalDue,
    required this.remaining,
    required this.monthsElapsed,
  });
}
