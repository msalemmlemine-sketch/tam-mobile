import 'package:flutter/material.dart';

import '../../models/institution.dart';
import '../../models/member.dart';
import '../../models/app_role.dart';
import '../../services/permission_service.dart';
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
          if (PermissionService.can(Permission.manageMembers)) IconButton(
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
                        if (m.isArchived) _row('الأرشفة', 'مؤرشف', valueColor: Colors.orange.shade800),
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
                FutureBuilder<List<Map<String, Object?>>>(
                  future: _subRepo.monthlyStatus(m.id!, DateTime.now().year),
                  builder: (context, snap) {
                    if (!snap.hasData) return const SizedBox.shrink();
                    final rows = snap.data!;
                    const names = ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('تفصيل اشتراكات ${DateTime.now().year}', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          ...rows.map((r) {
                            final month = (r['due_month'] as int) - 1;
                            final due = (r['amount'] as num).toDouble();
                            final paid = (r['paid'] as num).toDouble();
                            final full = paid >= due - 0.001;
                            final partial = paid > 0 && !full;
                            return ListTile(
                              dense: true,
                              leading: Icon(full ? Icons.check_circle : partial ? Icons.timelapse : Icons.radio_button_unchecked, color: full ? Colors.green : partial ? Colors.orange : Colors.grey),
                              title: Text(names[month]),
                              trailing: Text('${paid.toStringAsFixed(0)} / ${due.toStringAsFixed(0)}'),
                            );
                          }),
                        ]),
                      ),
                    );
                  },
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

                if (PermissionService.can(Permission.freezeMembers) || PermissionService.can(Permission.deleteMembers)) ...[
                  const SizedBox(height: 12),
                  Card(child: Column(children: [
                    if (PermissionService.can(Permission.freezeMembers)) ListTile(
                      leading: Icon(m.membershipStatus == 'suspended' ? Icons.lock_open : Icons.lock_outline),
                      title: Text(m.membershipStatus == 'suspended' ? 'إلغاء تجميد الانتساب' : 'تجميد الانتساب'),
                      subtitle: const Text('يوقف احتساب الاستحقاقات دون إخفاء المنتسب من القوائم'),
                      onTap: () async {
                        final next = m.membershipStatus == 'suspended' ? 'active' : 'suspended';
                        await _memberRepo.update(m.copyWith(membershipStatus: next, statusDate: DateTime.now().toIso8601String().substring(0,10), updatedAt: DateTime.now().toIso8601String()));
                        setState(() { _changed = true; _future = _load(); });
                      },
                    ),
                    if (PermissionService.can(Permission.freezeMembers)) ListTile(
                      leading: Icon(m.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
                      title: Text(m.isArchived ? 'إلغاء الأرشفة' : 'أرشفة المنتسب'),
                      subtitle: Text(m.isArchived ? 'إعادة إظهاره في قوائم المنتسبين النشطة' : 'إخفاؤه من القوائم النشطة مع الاحتفاظ الكامل ببياناته وسجله المالي، ويمكن التراجع لاحقاً'),
                      onTap: () async {
                        final now = DateTime.now().toIso8601String();
                        if (m.isArchived) {
                          await _memberRepo.unarchive(m.id!, now);
                        } else {
                          final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                            title: const Text('أرشفة المنتسب؟'),
                            content: const Text('سيختفي من قوائم المنتسبين النشطة، لكن بياناته وسجل دفعاته يبقيان محفوظين بالكامل ويمكن استرجاعه في أي وقت.'),
                            actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('أرشفة'))],
                          ));
                          if (ok != true) return;
                          await _memberRepo.archive(m.id!, now);
                        }
                        if (mounted) { _changed = true; setState(() => _future = _load()); }
                      },
                    ),
                    if (PermissionService.can(Permission.deleteMembers)) ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('حذف المنتسب نهائياً'),
                      subtitle: const Text('يُسمح فقط إذا لم توجد له أي دفعة مالية مسجَّلة'),
                      onTap: () async {
                        final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                          title: const Text('حذف المنتسب نهائياً؟'),
                          content: const Text('سيُحذف السجل نهائياً ولا يمكن التراجع عن هذا الإجراء. سيُرفض الحذف تلقائياً إذا كانت له دفعات مالية مسجَّلة، حمايةً للسجل المالي — استخدم الأرشفة بدلاً من ذلك في تلك الحالة.'),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف نهائي'))],
                        ));
                        if (ok != true) return;
                        try {
                          await _memberRepo.hardDelete(m.id!);
                          if (mounted) Navigator.pop(context, true);
                        } catch (_) {
                          if (!mounted) return;
                          final archiveInstead = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                            title: const Text('تعذّر الحذف النهائي'),
                            content: const Text('توجد دفعات مالية مرتبطة بهذا المنتسب، لذلك لا يمكن حذفه نهائياً حمايةً للسجل المالي. هل تريد أرشفته بدلاً من ذلك؟ سيختفي من القوائم النشطة مع الاحتفاظ ببياناته وسجله المالي.'),
                            actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('أرشفة بدلاً منه'))],
                          ));
                          if (archiveInstead == true) {
                            await _memberRepo.archive(m.id!, DateTime.now().toIso8601String());
                            if (mounted) { _changed = true; setState(() => _future = _load()); }
                          }
                        }
                      },
                    ),
                  ])),
                ],
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
