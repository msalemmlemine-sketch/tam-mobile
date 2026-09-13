import 'package:flutter/material.dart';

import '../../models/fund_year_summary.dart';
import '../../models/regional_expense.dart';
import '../../repositories/fund_repository.dart';
import '../../services/fund_service.dart';

class FundScreen extends StatefulWidget {
  const FundScreen({super.key});

  @override
  State<FundScreen> createState() => _FundScreenState();
}

class _FundScreenState extends State<FundScreen> {
  final _fundService = FundService();
  final _fundRepo = FundRepository();

  int _year = DateTime.now().year;
  late Future<_FundData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_FundData> _load() async {
    final summary = await _fundService.summaryForYear(_year);
    final expenses = await _fundRepo.expensesForYear(_year);
    return _FundData(summary: summary, expenses: expenses);
  }

  void _changeYear(int delta) {
    setState(() {
      _year += delta;
      _future = _load();
    });
  }

  Future<void> _addExpense() async {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime date = DateTime(_year, DateTime.now().month, DateTime.now().day);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('إضافة مصروف — سنة $_year',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ (أوقية)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'الوصف'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text) ?? 0;
                  if (amount <= 0) return;
                  final expense = RegionalExpense(
                    expenseDate: date.toIso8601String().substring(0, 10),
                    amount: amount,
                    description: descCtrl.text.trim(),
                    createdAt: DateTime.now().toIso8601String(),
                  );
                  await _fundRepo.addExpense(expense);
                  if (context.mounted) Navigator.of(context).pop(true);
                },
                child: const Text('حفظ المصروف'),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true) {
      setState(() => _future = _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الصندوق'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                  onPressed: () => _changeYear(-1),
                  icon: const Icon(Icons.chevron_right)),
              Text('سنة $_year', style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                  onPressed: () => _changeYear(1),
                  icon: const Icon(Icons.chevron_left)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpense,
        icon: const Icon(Icons.remove_circle_outline),
        label: const Text('مصروف جديد'),
      ),
      body: FutureBuilder<_FundData>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final s = data.summary;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _line('الرصيد الافتتاحي', s.openingBalance,
                          note: s.openingIsManualOverride
                              ? '(مُدخَل يدويًا)'
                              : '(مرحَّل من ${s.year - 1})'),
                      _line('+ المداخيل (حصة الجهوي)', s.income),
                      _line('− المصاريف', s.expenses),
                      const Divider(),
                      _line('= الرصيد الحالي', s.closingBalance, bold: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('مصاريف سنة $_year',
                  style: Theme.of(context).textTheme.titleMedium),
              if (data.expenses.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('لا توجد مصاريف مسجَّلة'),
                )
              else
                ...data.expenses.map((e) => Card(
                      child: ListTile(
                        title: Text(e.description ?? 'مصروف'),
                        subtitle: Text(e.expenseDate),
                        trailing: Text('${e.amount.toStringAsFixed(0)} أوقية'),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }

  Widget _line(String label, double value, {String? note, bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Text(label,
                  style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
              if (note != null) ...[
                const SizedBox(width: 6),
                Text(note,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ]),
            Text('${value.toStringAsFixed(0)} أوقية',
                style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
          ],
        ),
      );
}

class _FundData {
  final FundYearSummary summary;
  final List<RegionalExpense> expenses;
  _FundData({required this.summary, required this.expenses});
}
