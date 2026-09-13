import 'package:flutter/material.dart';

import '../../models/institution.dart';
import '../../models/member.dart';
import '../../models/subscription_payment.dart';
import '../../repositories/institution_repository.dart';
import '../../repositories/member_repository.dart';
import '../../repositories/subscription_repository.dart';
import '../../services/subscription_calculator.dart';
import 'member_form_screen.dart';

class MemberDetailScreen extends StatefulWidget {
  final int memberId;
  const MemberDetailScreen({super.key, required this.memberId});

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  final _memberRepo = MemberRepository();
  final _institutionRepo = InstitutionRepository();
  final _subRepo = SubscriptionRepository();
  static const _calculator = SubscriptionCalculator();

  late Future<_DetailData> _future;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DetailData> _load() async {
    final member = await _memberRepo.getById(widget.memberId);
    if (member == null) throw StateError('المنتسب غير موجود');
    final institution = await _institutionRepo.getById(member.institutionId);
    final payments = await _subRepo.paymentsForMember(widget.memberId);
    final totalPaid = await _subRepo.totalSubscriptionPaidByMember(widget.memberId);
    final firstDateStr = await _subRepo.firstPaymentDate(widget.memberId);
    final settings = await _subRepo.getSettings();
    final monthlyAmount = settings['monthly_amount'] ?? 0;

    double totalDue = 0;
    int months = 0;
    if (firstDateStr != null) {
      final firstDate = DateTime.parse(firstDateStr);
      months = _calculator.monthsElapsed(
        firstDueDate: DateTime(firstDate.year, firstDate.month, 1),
        referenceDate: DateTime.now(),
        statusDate:
            member.statusDate != null ? DateTime.parse(member.statusDate!) : null,
        isActive: member.membershipStatus == 'active',
      );
      totalDue = _calculator.totalDue(monthsElapsed: months, monthlyAmount: monthlyAmount);
    }
    final remaining = _calculator.remainingBalance(totalDue: totalDue, totalPaid: totalPaid);

    return _DetailData(
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
        title: const Text('تفاصيل المنتسب'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final data = await _future;
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => MemberFormScreen(member: data.member),
                ),
              );
              if (saved == true) {
                _changed = true;
                setState(() => _future = _load());
              }
            },
          ),
        ],
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) Navigator.of(context).pop(_changed);
        },
        child: FutureBuilder<_DetailData>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            final m = data.member;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(m.name, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(data.institution?.name ?? '—',
                    style: Theme.of(context).textTheme.bodyMedium),
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
                        Text('حالة الاشتراك',
                            style: Theme.of(context).textTheme.titleMedium),
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
                          trailing: p.directToExecutive
                              ? const Chip(label: Text('مباشر للتنفيذي'))
                              : null,
                        ),
                      )),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Text(value,
                style: TextStyle(fontWeight: FontWeight.w600, color: valueColor)),
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

class _DetailData {
  final Member member;
  final Institution? institution;
  final List<SubscriptionPayment> payments;
  final double totalPaid;
  final double totalDue;
  final double remaining;
  final int monthsElapsed;

  _DetailData({
    required this.member,
    required this.institution,
    required this.payments,
    required this.totalPaid,
    required this.totalDue,
    required this.remaining,
    required this.monthsElapsed,
  });
}
