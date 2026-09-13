import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../models/subscription_payment.dart';
import '../../repositories/member_repository.dart';
import '../../repositories/subscription_repository.dart';

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
  void initState() {
    super.initState();
    _future = _subRepo.paymentsForYear(_year);
  }

  void _changeYear(int delta) {
    setState(() {
      _year += delta;
      _future = _subRepo.paymentsForYear(_year);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الاشتراكات'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    onPressed: () => _changeYear(-1),
                    icon: const Icon(Icons.chevron_right)),
                Text('سنة $_year',
                    style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                    onPressed: () => _changeYear(1),
                    icon: const Icon(Icons.chevron_left)),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const _RecordPaymentScreen()),
          );
          if (saved == true) {
            setState(() => _future = _subRepo.paymentsForYear(_year));
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('تسجيل دفعة'),
      ),
      body: FutureBuilder<List<SubscriptionPayment>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final payments = snapshot.data!;
          if (payments.isEmpty) {
            return const Center(child: Text('لا توجد دفعات في هذه السنة'));
          }
          final total = payments.fold<double>(
              0, (sum, p) => sum + p.subscriptionAmount + p.cardFee);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('عدد الدفعات: ${payments.length}'),
                        Text('الإجمالي: ${total.toStringAsFixed(0)} أوقية'),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: payments.length,
                  itemBuilder: (context, index) {
                    final p = payments[index];
                    return ListTile(
                      title: Text(p.memberName ?? 'منتسب #${p.memberId}'),
                      subtitle: Text(
                          '${p.paymentDate ?? ''} — اشتراك ${p.subscriptionAmount.toStringAsFixed(0)}'
                          '${p.cardFee > 0 ? ' + بطاقة ${p.cardFee.toStringAsFixed(0)}' : ''}'),
                      trailing: p.directToExecutive
                          ? const Icon(Icons.arrow_upward, size: 18)
                          : null,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecordPaymentScreen extends StatefulWidget {
  const _RecordPaymentScreen();

  @override
  State<_RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<_RecordPaymentScreen> {
  final _memberRepo = MemberRepository();
  final _subRepo = SubscriptionRepository();
  final _formKey = GlobalKey<FormState>();

  final _searchCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _cardFeeCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();

  Member? _selectedMember;
  List<Member> _suggestions = [];
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  DateTime _date = DateTime.now();
  bool _directToExecutive = false;
  bool _saving = false;

  Future<void> _search(String value) async {
    if (value.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    final results = await _memberRepo.search(query: value, limit: 10);
    setState(() => _suggestions = results);
  }

  Future<void> _save() async {
    if (_selectedMember == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اختر المنتسب أولًا')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final settings = await _subRepo.getSettings();
    final subAmount = double.tryParse(_amountCtrl.text) ??
        settings['monthly_amount'] ??
        0;
    final cardFee = double.tryParse(_cardFeeCtrl.text) ?? 0;

    final payment = SubscriptionPayment(
      memberId: _selectedMember!.id!,
      memberName: _selectedMember!.name,
      financialGuide: _selectedMember!.guide,
      cardNo: _selectedMember!.cardNo,
      paymentYear: _year,
      paymentMonth: _month,
      paymentDate: _date.toIso8601String().substring(0, 10),
      subscriptionAmount: subAmount,
      cardFee: cardFee,
      totalAmount: subAmount + cardFee,
      source: 'manual',
      directToExecutive: _directToExecutive,
      notes: _notesCtrl.text.trim(),
      createdAt: DateTime.now().toIso8601String(),
    );
    await _subRepo.recordPayment(payment);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل دفعة اشتراك')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: _search,
              decoration: InputDecoration(
                labelText: 'اختر المنتسب *',
                prefixIcon: const Icon(Icons.search),
                suffixText: _selectedMember?.name,
              ),
            ),
            ..._suggestions.map((m) => ListTile(
                  title: Text(m.name),
                  subtitle: Text(m.guide ?? ''),
                  onTap: () {
                    setState(() {
                      _selectedMember = m;
                      _suggestions = [];
                      _searchCtrl.text = m.name;
                    });
                  },
                )),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              decoration:
                  const InputDecoration(labelText: 'قيمة الاشتراك (أوقية)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cardFeeCtrl,
              decoration: const InputDecoration(labelText: 'رسم البطاقة (أوقية)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _year,
                    decoration: const InputDecoration(labelText: 'السنة'),
                    items: [
                      for (var y = DateTime.now().year - 5;
                          y <= DateTime.now().year + 1;
                          y++)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (v) => setState(() => _year = v ?? _year),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _month,
                    decoration: const InputDecoration(labelText: 'الشهر'),
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(value: m, child: Text('$m')),
                    ],
                    onChanged: (v) => setState(() => _month = v ?? _month),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _directToExecutive,
              onChanged: (v) => setState(() => _directToExecutive = v),
              title: const Text('دفعة مباشرة للتنفيذي (بلا توزيع)'),
            ),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'ملاحظات'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('حفظ الدفعة'),
            ),
          ],
        ),
      ),
    );
  }
}
