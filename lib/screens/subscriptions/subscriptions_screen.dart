import 'package:flutter/material.dart';

import '../../models/app_role.dart';
import '../../models/member.dart';
import '../../models/payment_method.dart';
import '../../models/subscription_payment.dart';
import '../../repositories/member_repository.dart';
import '../../repositories/subscription_repository.dart';
import '../../services/permission_service.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});
  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final _subRepo = SubscriptionRepository();
  int _year = DateTime.now().year;
  late Future<List<SubscriptionPayment>> _future;

  @override
  void initState() { super.initState(); _reload(); }
  void _reload() => _future = _subRepo.paymentsForYear(_year);
  void _changeYear(int delta) => setState(() { _year += delta; _reload(); });

  @override
  Widget build(BuildContext context) {
    final canAdd = PermissionService.can(Permission.addPayments);
    final canEdit = PermissionService.can(Permission.editPayments);
    final canDelete = PermissionService.can(Permission.deletePayments);
    return Scaffold(
      appBar: AppBar(
        title: Text(PermissionService.role == AppRole.financeSecretary ? 'الدفعات — أمين المالية' : 'الاشتراكات'),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(48), child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: () => _changeYear(-1), icon: const Icon(Icons.chevron_right)),
            Text('سنة $_year', style: Theme.of(context).textTheme.titleMedium),
            IconButton(onPressed: () => _changeYear(1), icon: const Icon(Icons.chevron_left)),
          ]),
        )),
      ),
      floatingActionButton: canAdd ? FloatingActionButton.extended(
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const _PaymentFormScreen()));
          if (saved == true) setState(_reload);
        }, icon: const Icon(Icons.add), label: const Text('إضافة دفعة')) : null,
      body: FutureBuilder<List<SubscriptionPayment>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final payments = snapshot.data!;
          final total = payments.fold<double>(0, (sum, p) => sum + p.totalAmount);
          return Column(children: [
            Padding(padding: const EdgeInsets.all(12), child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('${payments.length} دفعة'), Text('${total.toStringAsFixed(0)} أوقية')])))),
            Expanded(child: payments.isEmpty
              ? const Center(child: Text('لا توجد دفعات في هذه السنة'))
              : ListView.builder(itemCount: payments.length, itemBuilder: (context, index) {
                  final p = payments[index];
                  return Card(child: ListTile(
                    title: Text(p.memberName ?? 'منتسب #${p.memberId}'),
                    subtitle: Text('${p.paymentDate ?? ''} • ${PaymentMethod.labelOf(p.paymentMethod)} • ${p.totalAmount.toStringAsFixed(0)} أوقية${p.paymentReference?.isNotEmpty == true ? ' • ${p.paymentReference}' : ''}'),
                    trailing: canEdit ? PopupMenuButton<String>(onSelected: (v) async {
                      if (v == 'edit') {
                        final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _PaymentFormScreen(payment: p)));
                        if (saved == true && mounted) setState(_reload);
                      } else if (v == 'delete' && canDelete) {
                        final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('حذف الدفعة؟'), content: const Text('سيتم تسجيل عملية الحذف في سجل التدقيق.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف'))]));
                        if (ok == true) { await _subRepo.deletePayment(p.id!); if (mounted) setState(_reload); }
                      }
                    }, itemBuilder: (_) => [
                      if (canEdit) const PopupMenuItem(value: 'edit', child: Text('تعديل/تصحيح')),
                      if (canDelete) const PopupMenuItem(value: 'delete', child: Text('حذف')),
                    ]) : null,
                  ));
                })),
          ]);
        },
      ),
    );
  }
}

class _PaymentFormScreen extends StatefulWidget {
  final SubscriptionPayment? payment;
  const _PaymentFormScreen({this.payment});
  @override State<_PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends State<_PaymentFormScreen> {
  final _memberRepo = MemberRepository();
  final _subRepo = SubscriptionRepository();
  final _formKey = GlobalKey<FormState>();
  final _searchCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _cardFeeCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  Member? _selectedMember;
  List<Member> _suggestions = [];
  int _year = DateTime.now().year;
  DateTime _date = DateTime.now();
  String _method = PaymentMethod.cash.key;
  bool _directToExecutive = false;
  bool _saving = false;

  bool get _editing => widget.payment != null;

  @override
  void initState() {
    super.initState();
    final p = widget.payment;
    _amountCtrl.text = p?.subscriptionAmount.toStringAsFixed(0) ?? '';
    _cardFeeCtrl.text = p?.cardFee.toStringAsFixed(0) ?? '0';
    _referenceCtrl.text = p?.paymentReference ?? '';
    _notesCtrl.text = p?.notes ?? '';
    _year = p?.paymentYear ?? _year;
    _method = p?.paymentMethod ?? PaymentMethod.cash.key;
    _directToExecutive = p?.directToExecutive ?? false;
    if (p != null) { _searchCtrl.text = p.memberName ?? ''; _selectedMember = Member(id: p.memberId, districtId: 0, institutionId: 0, name: p.memberName ?? '', guide: p.financialGuide, cardNo: p.cardNo, createdAt: p.createdAt, updatedAt: p.createdAt); }
  }

  Future<void> _search(String value) async {
    if (value.trim().length < 2) { setState(() => _suggestions = []); return; }
    final results = await _memberRepo.search(query: value, limit: 10);
    if (mounted) setState(() => _suggestions = results);
  }

  Future<void> _save() async {
    if (_selectedMember == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر المنتسب أولًا'))); return; }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final settings = await _subRepo.getSettings();
      final subAmount = double.tryParse(_amountCtrl.text) ?? settings['monthly_amount'] ?? 0;
      final cardFee = double.tryParse(_cardFeeCtrl.text) ?? 0;
      final now = DateTime.now().toIso8601String();
      final p = SubscriptionPayment(
        id: widget.payment?.id,
        memberId: _selectedMember!.id,
        memberName: _selectedMember!.name,
        financialGuide: _selectedMember!.guide,
        cardNo: _selectedMember!.cardNo,
        paymentYear: _year,
        paymentMonth: _date.month,
        paymentDate: _date.toIso8601String().substring(0, 10),
        subscriptionAmount: subAmount,
        cardFee: cardFee,
        totalAmount: subAmount + cardFee,
        source: 'manual',
        paymentMethod: _method,
        paymentReference: _referenceCtrl.text.trim().isEmpty ? null : _referenceCtrl.text.trim(),
        directToExecutive: _directToExecutive,
        notes: _notesCtrl.text.trim(),
        createdAt: widget.payment?.createdAt ?? now,
      );
      if (_editing) await _subRepo.updatePayment(p); else await _subRepo.recordPayment(p);
      if (mounted) Navigator.pop(context, true);
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_editing ? 'تصحيح الدفعة' : 'إضافة دفعة')),
    body: Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: _searchCtrl, onChanged: _search, readOnly: _editing, decoration: const InputDecoration(labelText: 'المنتسب *', prefixIcon: Icon(Icons.search))),
      ..._suggestions.map((m) => ListTile(title: Text(m.name), subtitle: Text(m.guide ?? ''), onTap: () => setState(() { _selectedMember = m; _searchCtrl.text = m.name; _suggestions = []; }))),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _method,
        decoration: const InputDecoration(labelText: 'طريقة السداد *'),
        items: [for (final m in PaymentMethod.all) DropdownMenuItem(value: m.key, child: Text(m.label))],
        onChanged: (v) => setState(() { _method = v ?? _method; if (PaymentMethod.isCash(_method)) _referenceCtrl.clear(); }),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _referenceCtrl,
        enabled: PaymentMethod.isElectronic(_method),
        decoration: InputDecoration(
          labelText: PaymentMethod.isCash(_method) ? 'رقم العملية غير مطلوب للنقد' : 'رقم العملية/المرجع *',
        ),
        validator: (v) => PaymentMethod.isElectronic(_method) && (v == null || v.trim().isEmpty) ? 'أدخل رقم العملية أو المرجع' : null,
      ),
      const SizedBox(height: 12),
      TextFormField(controller: _amountCtrl, decoration: const InputDecoration(labelText: 'قيمة الاشتراك المدفوعة (أوقية)'), keyboardType: TextInputType.number, validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'أدخل قيمة صحيحة' : null),
      const SizedBox(height: 4),
      const Text('سيتم توزيع مبلغ الاشتراك تلقائيًا على أقدم الأشهر غير المسددة في السنة المختارة، ويمكن أن تغطي الدفعة شهرًا أو عدة أشهر أو السنة كاملة. الدفعة الجزئية تُوزع تلقائيًا.', style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 12),
      TextFormField(controller: _cardFeeCtrl, decoration: const InputDecoration(labelText: 'رسم البطاقة (أوقية)'), keyboardType: TextInputType.number),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(value: _year, decoration: const InputDecoration(labelText: 'سنة الاستحقاق'), items: [for (var y = DateTime.now().year - 5; y <= DateTime.now().year + 1; y++) DropdownMenuItem(value: y, child: Text('$y'))], onChanged: (v) => setState(() => _year = v ?? _year)),
      const SizedBox(height: 12),
      SwitchListTile(value: _directToExecutive, onChanged: (v) => setState(() => _directToExecutive = v), title: const Text('دفعة مباشرة للتنفيذي (بلا توزيع)')),
      TextFormField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'ملاحظات'), maxLines: 2),
      const SizedBox(height: 24),
      FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_editing ? 'حفظ التصحيح' : 'حفظ الدفعة')),
    ])),
  );
}
