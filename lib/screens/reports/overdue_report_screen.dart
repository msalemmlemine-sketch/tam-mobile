  import 'package:flutter/material.dart';

import '../../services/report_service.dart';
import '../../services/export_service.dart';

class OverdueReportScreen extends StatefulWidget {
  const OverdueReportScreen({super.key});

  @override
  State<OverdueReportScreen> createState() =>
      _OverdueReportScreenState();
}

class _OverdueReportScreenState
    extends State<OverdueReportScreen> {
  final ReportService _reportService = ReportService();
  final ExportService _exportService = ExportService();

  late Future<List<MemberDebtRow>> _future;

  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = _reportService.overdueReport();
    });
  }

  List<MemberDebtRow> _filter(
    List<MemberDebtRow> rows,
  ) {
    final query = _search.trim().toLowerCase();

    if (query.isEmpty) {
      return rows;
    }

    return rows.where((row) {
      return row.member.name.toLowerCase().contains(query) ||
          row.institutionName.toLowerCase().contains(query) ||
          row.districtName.toLowerCase().contains(query) ||
          (row.member.phone ?? '').toLowerCase().contains(query) ||
          (row.member.cardNo ?? '').toLowerCase().contains(query);
    }).toList();
  }

  Map<String, List<MemberDebtRow>> _groupByDistrict(
    List<MemberDebtRow> rows,
  ) {
    final result = <String, List<MemberDebtRow>>{};

    for (final row in rows) {
      result
          .putIfAbsent(row.districtName, () => [])
          .add(row);
    }

    return Map.fromEntries(
      result.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  Map<String, List<MemberDebtRow>> _groupByInstitution(
    List<MemberDebtRow> rows,
  ) {
    final result = <String, List<MemberDebtRow>>{};

    for (final row in rows) {
      result
          .putIfAbsent(row.institutionName, () => [])
          .add(row);
    }

    return Map.fromEntries(
      result.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  double _sumRemaining(List<MemberDebtRow> rows) {
    return rows.fold(
      0,
      (sum, row) => sum + row.remaining,
    );
  }

  double _sumDue(List<MemberDebtRow> rows) {
    return rows.fold(
      0,
      (sum, row) => sum + row.totalDue,
    );
  }

  double _sumPaid(List<MemberDebtRow> rows) {
    return rows.fold(
      0,
      (sum, row) => sum + row.totalPaid,
    );
  }

  String _money(double value) {
    return '${value.toStringAsFixed(0)} MRU';
  }

  String _number(double value) {
    return value.toStringAsFixed(0);
  }

  Future<void> _exportCsv(
    List<MemberDebtRow> rows,
  ) async {
    final headers = <String>[
      'المقاطعة',
      'المؤسسة',
      'الاسم',
      'المستحق',
      'المدفوع',
      'المتبقي',
      'الهاتف',
      'رقم البطاقة',
    ];

    final grouped = _groupByDistrict(rows);

    final data = <List<String>>[];

    for (final district in grouped.entries) {
      for (final row in district.value) {
        final member = row.member;

        data.add([
          district.key,
          row.institutionName,
          member.name,
          _number(row.totalDue),
          _number(row.totalPaid),
          _number(row.remaining),
          member.phone ?? '',
          member.cardNo ?? '',
        ]);
      }
    }

    await _exportService.exportCsv(
      fileName: 'rapport_des_impayes_2026.csv',
      headers: headers,
      rows: data,
    );
  }

  Future<void> _exportPdf(
    List<MemberDebtRow> rows,
  ) async {
    final grouped = _groupByDistrict(rows);

    final pdfRows = <List<String>>[];

    for (final district in grouped.entries) {
      for (final row in district.value) {
        pdfRows.add([
          row.member.name,
          row.institutionName,
          district.key,
          _number(row.totalDue),
          _number(row.totalPaid),
          _number(row.remaining),
        ]);
      }
    }

    await _exportService.exportPdfTable(
      fileName: 'rapport_des_impayes_2026.pdf',
      title: 'تقرير المتأخرات والديون - 2026',
      headers: [
        'الاسم',
        'المؤسسة',
        'المقاطعة',
        'المستحق',
        'المدفوع',
        'المتبقي',
      ],
      rows: pdfRows,
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 12,
          ),
          child: Column(
            children: [
              Icon(icon, size: 24),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _districtSection(
    String district,
    List<MemberDebtRow> rows,
  ) {
    final institutions = _groupByInstitution(rows);
    final remaining = _sumRemaining(rows);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.location_city),
        title: Text(
          district,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${rows.length} منتسب • ${_money(remaining)} متبقية',
        ),
        children: [
          const Divider(height: 1),
          ...institutions.entries.map(
            (institution) => _institutionSection(
              institution.key,
              institution.value,
            ),
          ),
        ],
      ),
    );
  }

  Widget _institutionSection(
    String institution,
    List<MemberDebtRow> rows,
  ) {
    final remaining = _sumRemaining(rows);

    return ExpansionTile(
      leading: const Icon(Icons.school_outlined),
      title: Text(
        institution,
        textAlign: TextAlign.right,
      ),
      subtitle: Text(
        '${rows.length} مدين • ${_money(remaining)}',
        textAlign: TextAlign.right,
      ),
      children: [
        ...List.generate(rows.length, (index) {
          final row = rows[index];
          final member = row.member;

          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              child: Text('${index + 1}'),
            ),
            title: Text(
              member.name,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'المستحق: ${_money(row.totalDue)}',
                ),
                Text(
                  'المدفوع: ${_money(row.totalPaid)}',
                ),
                Text(
                  'المتبقي: ${_money(row.remaining)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if ((member.phone ?? '').isNotEmpty)
                  Text('الهاتف: ${member.phone}'),
              ],
            ),
            trailing: const Icon(
              Icons.warning_amber_rounded,
            ),
          );
        }),
      ],
    );
  }

  Widget _analysisCard(
    List<MemberDebtRow> rows,
  ) {
    final due = _sumDue(rows);
    final paid = _sumPaid(rows);
    final remaining = _sumRemaining(rows);

    final collectionRate =
        due > 0 ? (paid * 100 / due) : 0;

    return Card(
      margin: const EdgeInsets.fromLTRB(
        12,
        8,
        12,
        4,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Text(
              'التحليل المالي',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _financialBox(
                  'المستحق',
                  _money(due),
                ),
                _financialBox(
                  'المدفوع',
                  _money(paid),
                ),
                _financialBox(
                  'المتبقي',
                  _money(remaining),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: collectionRate / 100,
            ),
            const SizedBox(height: 6),
            Text(
              'نسبة التحصيل: ${collectionRate.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ),
    );
  }

  Widget _financialBox(
    String label,
    String value,
  ) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: 3,
        ),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'تقرير المتأخرات والديون',
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<List<MemberDebtRow>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState ==
                ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 50,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'تعذر تحميل تقرير المتأخرات',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text(
                          'إعادة المحاولة',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final allRows = snapshot.data ?? [];
            final rows = _filter(allRows);
            final districts = _groupByDistrict(rows);

            if (allRows.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 55,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'لا توجد متأخرات مسجلة',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    4,
                  ),
                  child: Row(
                    children: [
                      _summaryCard(
                        title: 'عدد المدينين',
                        value: '${rows.length}',
                        icon: Icons.people_alt_outlined,
                      ),
                      const SizedBox(width: 8),
                      _summaryCard(
                        title: 'المتبقي',
                        value:
                            _money(_sumRemaining(rows)),
                        icon: Icons.account_balance_wallet,
                      ),
                      const SizedBox(width: 8),
                      _summaryCard(
                        title: 'المؤسسات',
                        value:
                            '${_groupByInstitution(rows).length}',
                        icon: Icons.school,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    12,
                    8,
                    12,
                    4,
                  ),
                  child: TextField(
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      hintText:
                          'بحث بالاسم أو المؤسسة أو المقاطعة...',
                      prefixIcon:
                          const Icon(Icons.search),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                setState(() {
                                  _search = '';
                                });
                              },
                              icon:
                                  const Icon(Icons.clear),
                            ),
                      border:
                          const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _search = value;
                      });
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: rows.isEmpty
                              ? null
                              : () => _exportCsv(rows),
                          icon:
                              const Icon(Icons.table_view),
                          label: const Text('CSV'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: rows.isEmpty
                              ? null
                              : () => _exportPdf(rows),
                          icon: const Icon(
                            Icons.picture_as_pdf,
                          ),
                          label: const Text('PDF'),
                        ),
                      ),
                    ],
                  ),
                ),
                _analysisCard(rows),
                const SizedBox(height: 4),
                Expanded(
                  child: rows.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد نتائج مطابقة للبحث',
                          ),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.all(12),
                          itemCount: districts.length,
                          itemBuilder:
                              (context, index) {
                            final entry = districts
                                .entries
                                .elementAt(index);

                            return _districtSection(
                              entry.key,
                              entry.value,
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
