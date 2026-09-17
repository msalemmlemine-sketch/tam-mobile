import 'package:flutter/material.dart';

import '../../models/app_role.dart';
import '../../models/fund_year_summary.dart';
import '../../models/regional_expense.dart';
import '../../repositories/fund_repository.dart';
import '../../services/export_service.dart';
import '../../services/fund_service.dart';
import '../../services/permission_service.dart';

class FundScreen extends StatefulWidget {
  const FundScreen({super.key});

  @override
  State<FundScreen> createState() => _FundScreenState();
}

class _FundScreenState extends State<FundScreen> {
  final _fundService = FundService();
  final _fundRepo = FundRepository();
  final _exportService = ExportService();

  static const _monthNames = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  int _year = DateTime.now().year;
  late Future<FundDetailedReport> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<FundDetailedReport> _load() {
    return _fundService.detailedReportForYear(_year);
  }

  void _changeYear(int delta) {
    setState(() {
      _year += delta;
      _future = _load();
    });
  }

  Future<void> _editExpense({RegionalExpense? existing}) async {
    final amountCtrl = TextEditingController(
      text: existing == null ? '' : existing.amount.toStringAsFixed(0),
    );
    final descCtrl = TextEditingController(
      text: existing?.description ?? '',
    );

    String category = existing?.category ?? kExpenseCategories.first;

    DateTime date = existing != null
        ? DateTime.parse(existing.expenseDate)
        : DateTime(_year, DateTime.now().month, DateTime.now().day);

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
              Text(
                existing == null
                    ? 'إضافة مصروف — سنة $_year'
                    : 'تعديل مصروف',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'المبلغ (أوقية)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(labelText: 'الفئة'),
                items: kExpenseCategories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setSheetState(() => category = v ?? category);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'الوصف'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  'التاريخ: ${date.toIso8601String().substring(0, 10)}',
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2100),
                  );

                  if (picked != null) {
                    setSheetState(() => date = picked);
                  }
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text) ?? 0;

                  if (amount <= 0) return;

                  final expense = RegionalExpense(
                    id: existing?.id,
                    expenseDate:
                        date.toIso8601String().substring(0, 10),
                    amount: amount,
                    category: category,
                    description: descCtrl.text.trim(),
                    createdAt:
                        existing?.createdAt ??
                        DateTime.now().toIso8601String(),
                  );

                  if (existing == null) {
                    await _fundRepo.addExpense(expense);
                  } else {
                    await _fundRepo.updateExpense(expense);
                  }

                  if (context.mounted) {
                    Navigator.of(context).pop(true);
                  }
                },
                child: Text(
                  existing == null
                      ? 'حفظ المصروف'
                      : 'حفظ التعديلات',
                ),
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

  Future<void> _deleteExpense(RegionalExpense expense) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المصروف؟'),
        content: Text(
          'سيُحذف مصروف "${expense.description ?? expense.category}" '
          'بمبلغ ${expense.amount.toStringAsFixed(0)} أوقية نهائيًا.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _fundRepo.deleteExpense(expense.id!);

      if (mounted) {
        setState(() => _future = _load());
      }
    }
  }

  Future<void> _setOpeningBalance() async {
    final existing =
        await _fundRepo.openingOverrideForYear(_year);

    final amountCtrl = TextEditingController(
      text: existing == null
          ? ''
          : existing.toStringAsFixed(0),
    );

    final notesCtrl = TextEditingController();

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الرصيد الافتتاحي الجهوي — سنة $_year',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'هذا المبلغ يمثل رصيد المكتب الجهوي فقط. '
              'لا تدخل فيه حصة المكتب التنفيذي.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'رصيد المكتب الجهوي (أوقية)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'ملاحظة (اختياري)',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final amount =
                    double.tryParse(amountCtrl.text);

                if (amount == null) return;

                await _fundRepo.setOpeningOverride(
                  _year,
                  amount,
                  DateTime.now().toIso8601String(),
                  notes: notesCtrl.text.trim().isEmpty
                      ? null
                      : notesCtrl.text.trim(),
                );

                if (context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text(
                'حفظ الرصيد الافتتاحي الجهوي',
              ),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      setState(() => _future = _load());
    }
  }

  Future<void> _export(FundDetailedReport r) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.picture_as_pdf_outlined),
              title: const Text(
                'تقرير شامل (PDF)',
              ),
              subtitle: const Text(
                'شهري + مصاريف + سنوات',
              ),
              onTap: () =>
                  Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.table_chart_outlined),
              title: const Text(
                'قائمة المصاريف (CSV)',
              ),
              onTap: () =>
                  Navigator.pop(ctx, 'csv'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    if (choice == 'csv') {
      await _exportService.exportCsv(
        fileName: 'مصاريف_الصندوق_$_year.csv',
        headers: [
          'التاريخ',
          'الفئة',
          'الوصف',
          'المبلغ',
        ],
        rows: r.expenses
            .map(
              (e) => [
                e.expenseDate,
                e.category,
                e.description ?? '',
                e.amount.toStringAsFixed(0),
              ],
            )
            .toList(),
        totalsRow: [
          '',
          '',
          'الإجمالي',
          r.summary.expenses.toStringAsFixed(0),
        ],
      );
      return;
    }

    final monthRows = [
      for (var m = 1; m <= 12; m++)
        [
          _monthNames[m - 1],
          (r.monthlyIncome[m] ?? 0)
              .toStringAsFixed(0),
          (r.monthlyExpenses[m] ?? 0)
              .toStringAsFixed(0),
          ((r.monthlyIncome[m] ?? 0) -
                  (r.monthlyExpenses[m] ?? 0))
              .toStringAsFixed(0),
        ],
    ];

    final totalIncome =
        r.monthlyIncome.values.fold<double>(
      0,
      (a, b) => a + b,
    );

    final totalExpenses =
        r.monthlyExpenses.values.fold<double>(
      0,
      (a, b) => a + b,
    );

    await _exportService.exportPdfTable(
      fileName: 'تقرير_الصندوق_$_year.pdf',
      title:
          'التقرير المالي للصندوق الجهوي — سنة $_year',
      headers: [
        'الشهر',
        'مداخيل الجهوي',
        'مصاريف الجهوي',
        'الصافي',
      ],
      rows: monthRows,
      totalsRow: [
        'الإجمالي',
        totalIncome.toStringAsFixed(0),
        totalExpenses.toStringAsFixed(0),
        (totalIncome - totalExpenses)
            .toStringAsFixed(0),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الصندوق الجهوي — تقرير مالي',
        ),
        actions: [
          if (PermissionService.can(
                Permission.exportLists,
              ) ||
              PermissionService.can(
                Permission.manageFund,
              ))
            FutureBuilder<FundDetailedReport>(
              future: _future,
              builder: (context, snapshot) {
                return IconButton(
                  tooltip: 'تصدير',
                  icon: const Icon(
                    Icons.ios_share_rounded,
                  ),
                  onPressed: snapshot.hasData
                      ? () => _export(snapshot.data!)
                      : null,
                );
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize:
              const Size.fromHeight(48),
          child: Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () =>
                    _changeYear(-1),
                icon: const Icon(
                  Icons.chevron_right,
                ),
              ),
              Text(
                'سنة $_year',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium,
              ),
              IconButton(
                onPressed: () =>
                    _changeYear(1),
                icon: const Icon(
                  Icons.chevron_left,
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton:
          PermissionService.can(
        Permission.manageFund,
      )
              ? FloatingActionButton.extended(
                  onPressed: () =>
                      _editExpense(),
                  icon: const Icon(
                    Icons.remove_circle_outline,
                  ),
                  label: const Text(
                    'مصروف جديد',
                  ),
                )
              : null,
      body: FutureBuilder<FundDetailedReport>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child:
                  CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding:
                    const EdgeInsets.all(20),
                child: Text(
                  'تعذر تحميل التقرير:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: Text(
                'لا توجد بيانات',
              ),
            );
          }

          final r = snapshot.data!;
          final s = r.summary;
          final canManage =
              PermissionService.can(
            Permission.manageFund,
          );

          final totalIncome =
              r.monthlyIncome.values.fold<double>(
            0,
            (a, b) => a + b,
          );

          final totalExpenses =
              r.monthlyExpenses.values.fold<double>(
            0,
            (a, b) => a + b,
          );

          return ListView(
            padding:
                const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'الصندوق الجهوي',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _line(
                        'الرصيد الافتتاحي الجهوي',
                        s.openingBalance,
                        note: s
                                .openingIsManualOverride
                            ? '(مدخل يدويًا)'
                            : '(مرحل من ${s.year - 1})',
                        onEdit: canManage
                            ? _setOpeningBalance
                            : null,
                      ),
                      _line(
                        '+ حصة الجهوي من الاشتراكات',
                        s.income,
                      ),
                      _line(
                        '− مصاريف المكتب الجهوي',
                        s.expenses,
                      ),
                      const Divider(),
                      _line(
                        '= الرصيد الجهوي الحالي',
                        s.closingBalance,
                        bold: true,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _sectionCard(
                context,
                'تركيبة الاشتراكات',
                [
                  _line(
                    'إجمالي الاشتراكات المحصلة',
                    r.totalCollected,
                  ),
                  _line(
                    'المبلغ المباشر للمكتب التنفيذي',
                    r.directToExecutive,
                  ),
                  _line(
                    'المبلغ الخاضع للتوزيع',
                    r.regionalEligible,
                  ),
                  _line(
                    'حصة المكتب الجهوي',
                    s.income,
                  ),
                  _line(
                    'حصة المكتب التنفيذي',
                    r.executiveShare,
                  ),
                  const Divider(),
                  const Text(
                    'حصة المكتب التنفيذي لا تدخل في رصيد الصندوق الجهوي.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              _sectionCard(
                context,
                'التفصيل الشهري لسنة $_year',
                [
                  _monthlyHeader(),
                  for (var m = 1; m <= 12; m++)
                    _monthlyRow(
                      m,
                      r.monthlyIncome[m] ?? 0,
                      r.monthlyExpenses[m] ?? 0,
                    ),
                  const Divider(),
                  _monthlyRow(
                    null,
                    totalIncome,
                    totalExpenses,
                    bold: true,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              _sectionCard(
                context,
                'توزيع المصاريف حسب الفئة',
                [
                  if (r.categoryBreakdown.isEmpty)
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(
                        vertical: 8,
                      ),
                      child: Text(
                        'لا توجد مصاريف مسجلة لهذه السنة',
                      ),
                    )
                  else
                    ...r.categoryBreakdown.entries
                        .map(
                          (e) => _categoryBar(
                            context,
                            e.key,
                            e.value,
                            s.expenses,
                          ),
                        ),
                ],
              ),

              const SizedBox(height: 12),

              _sectionCard(
                context,
                'الرصيد عبر السنوات',
                [
                  _yearsTableHeader(),
                  for (final y in r.yearsChain)
                    _yearsRow(
                      y,
                      highlighted:
                          y.year == _year,
                    ),
                ],
              ),

              const SizedBox(height: 12),

              Text(
                'مصاريف سنة $_year',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium,
              ),

              const SizedBox(height: 6),

              if (r.expenses.isEmpty)
                const Padding(
                  padding:
                      EdgeInsets.symmetric(
                    vertical: 12,
                  ),
                  child: Text(
                    'لا توجد مصاريف مسجلة',
                  ),
                )
              else
                ...r.expenses.map(
                  (e) => Card(
                    child: ListTile(
                      title: Text(
                        e.description
                                    ?.isNotEmpty ==
                                true
                            ? e.description!
                            : e.category,
                      ),
                      subtitle: Text(
                        '${e.category} — ${e.expenseDate}',
                      ),
                      leading: Text(
                        '${e.amount.toStringAsFixed(0)}\nأوقية',
                        textAlign:
                            TextAlign.center,
                        style:
                            const TextStyle(
                          fontSize: 11,
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                      trailing: canManage
                          ? PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') {
                                  _editExpense(
                                    existing: e,
                                  );
                                } else {
                                  _deleteExpense(e);
                                }
                              },
                              itemBuilder: (_) =>
                                  const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text(
                                    'تعديل',
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    'حذف',
                                  ),
                                ),
                              ],
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium,
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _monthlyHeader() {
    return const Padding(
      padding:
          EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'الشهر',
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'مداخيل الجهوي',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'مصاريف',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'الصافي',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthlyRow(
    int? month,
    double income,
    double expenses, {
    bool bold = false,
  }) {
    final net = income - expenses;

    final style = TextStyle(
      fontWeight:
          bold ? FontWeight.bold : null,
    );

    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 3,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              month == null
                  ? 'الإجمالي'
                  : _monthNames[month - 1],
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              income.toStringAsFixed(0),
              textAlign:
                  TextAlign.center,
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              expenses.toStringAsFixed(0),
              textAlign:
                  TextAlign.center,
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              net.toStringAsFixed(0),
              textAlign:
                  TextAlign.center,
              style: style.copyWith(
                color: net < 0
                    ? Colors.red.shade700
                    : Colors.green.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryBar(
    BuildContext context,
    String category,
    double amount,
    double totalExpenses,
  ) {
    final pct = totalExpenses > 0
        ? amount * 100 / totalExpenses
        : 0.0;

    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment
                    .spaceBetween,
            children: [
              Text(category),
              Text(
                '${amount.toStringAsFixed(0)} أوقية '
                '(${pct.toStringAsFixed(0)}%)',
                style:
                    const TextStyle(
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius:
                BorderRadius.circular(6),
            child:
                LinearProgressIndicator(
              value: pct / 100,
              minHeight: 7,
              backgroundColor:
                  Colors.grey.shade200,
            ),
          ),
        ],
      ),
    );
  }

  Widget _yearsTableHeader() {
    return const Padding(
      padding:
          EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'السنة',
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'افتتاحي',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'مداخيل',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'مصاريف',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'ختامي',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _yearsRow(
    FundYearSummary y, {
    bool highlighted = false,
  }) {
    return Container(
      color: highlighted
          ? Colors.teal.withValues(
              alpha: 0.08,
            )
          : null,
      padding:
          const EdgeInsets.symmetric(
        vertical: 3,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '${y.year}',
              style: TextStyle(
                fontWeight: highlighted
                    ? FontWeight.bold
                    : null,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              y.openingBalance
                  .toStringAsFixed(0),
              textAlign:
                  TextAlign.center,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              y.income
                  .toStringAsFixed(0),
              textAlign:
                  TextAlign.center,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              y.expenses
                  .toStringAsFixed(0),
              textAlign:
                  TextAlign.center,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              y.closingBalance
                  .toStringAsFixed(0),
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontWeight: highlighted
                    ? FontWeight.bold
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(
    String label,
    double value, {
    String? note,
    bool bold = false,
    VoidCallback? onEdit,
  }) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment
                .spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: bold
                          ? FontWeight.bold
                          : null,
                    ),
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    note,
                    style:
                        const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                ],
                if (onEdit != null) ...[
                  const SizedBox(width: 2),
                  InkWell(
                    onTap: onEdit,
                    borderRadius:
                        BorderRadius.circular(
                      20,
                    ),
                    child:
                        const Padding(
                      padding:
                          EdgeInsets.all(4),
                      child: Icon(
                        Icons
                            .edit_outlined,
                        size: 15,
                        color:
                            Colors.grey,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '${value.toStringAsFixed(0)} أوقية',
            style: TextStyle(
              fontWeight: bold
                  ? FontWeight.bold
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
