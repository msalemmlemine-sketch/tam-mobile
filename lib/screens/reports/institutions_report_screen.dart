import 'package:flutter/material.dart';

import '../../models/institution.dart';
import '../../services/report_service.dart';
import '../../services/export_service.dart';

class InstitutionsReportScreen extends StatefulWidget {
  const InstitutionsReportScreen({super.key});

  @override
  State<InstitutionsReportScreen> createState() =>
      _InstitutionsReportScreenState();
}

class _InstitutionsReportScreenState
    extends State<InstitutionsReportScreen> {
  final ReportService _reportService = ReportService();
  final ExportService _exportService = ExportService();

  late Future<InstitutionsReport> _future;

  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = _reportService.institutionsReport();
    });
  }

  List<InstitutionReportRow> _filter(
    List<InstitutionReportRow> rows,
  ) {
    final query = _search.trim().toLowerCase();

    if (query.isEmpty) {
      return rows;
    }

    return rows.where((row) {
      return row.institution.name.toLowerCase().contains(query) ||
          row.districtName.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _exportCsv(
    List<InstitutionReportRow> rows,
  ) async {
    final headers = <String>[
      'المقاطعة',
      'المؤسسة',
      'عدد الموظفين',
      'منتسبو TAM',
      'النسبة',
      'SIPES',
      'SNES',
      'نقابات أخرى',
      'غير منخرطين',
    ];

    final data = <List<String>>[];

    for (final row in rows) {
      data.add([
        row.districtName,
        row.institution.name,
        '${row.institution.totalStaff}',
        '${row.tamMembers}',
        _percentage(row.tamPercentage),
        '${row.institution.sipesMembers}',
        '${row.institution.snesMembers}',
        '${row.institution.otherUnionMembers}',
        '${row.institution.nonUnionStaff}',
      ]);
    }

    await _exportService.exportCsv(
      fileName: 'rapport_des_institutions.csv',
      headers: headers,
      rows: data,
    );
  }

  Future<void> _exportPdf(
    List<InstitutionReportRow> rows,
  ) async {
    final data = rows.map((row) {
      return [
        row.institution.name,
        row.districtName,
        '${row.institution.totalStaff}',
        '${row.tamMembers}',
        _percentage(row.tamPercentage),
        '${row.institution.sipesMembers}',
        '${row.institution.snesMembers}',
        '${row.institution.otherUnionMembers}',
        '${row.institution.nonUnionStaff}',
      ];
    }).toList();

    await _exportService.exportPdfTable(
      fileName: 'rapport_des_institutions.pdf',
      title: 'تقرير المؤسسات والمنتسبين',
      headers: [
        'المؤسسة',
        'المقاطعة',
        'إجمالي الموظفين',
        'منتسبو TAM',
        'النسبة',
        'SIPES',
        'SNES',
        'نقابات أخرى',
        'غير منخرطين',
      ],
      rows: data,
    );
  }

  String _percentage(double? value) {
    if (value == null) {
      return '—';
    }

    return '${value.toStringAsFixed(1)}%';
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
              Icon(icon, size: 25),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _institutionCard(InstitutionReportRow row) {
    final institution = row.institution;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.school),
        title: Text(
          institution.name,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${row.districtName} • ${row.tamMembers} منتسب',
          textAlign: TextAlign.right,
        ),
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    _dataBox(
                      'إجمالي الموظفين',
                      '${institution.totalStaff}',
                    ),
                    _dataBox(
                      'منتسبو TAM',
                      '${row.tamMembers}',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _dataBox(
                      'نسبة TAM',
                      _percentage(row.tamPercentage),
                    ),
                    _dataBox(
                      'SIPES',
                      '${institution.sipesMembers}',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _dataBox(
                      'SNES',
                      '${institution.snesMembers}',
                    ),
                    _dataBox(
                      'نقابات أخرى',
                      '${institution.otherUnionMembers}',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _dataBox(
                      'غير منخرطين',
                      '${institution.nonUnionStaff}',
                    ),
                    _dataBox(
                      'غير مصنفين',
                      '${row.unclassifiedStaff}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataBox(
    String label,
    String value,
  ) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(10),
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
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_outlined,
              size: 55,
            ),
            SizedBox(height: 12),
            Text(
              'لا توجد مؤسسات مطابقة',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
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
          title: const Text('تقرير المؤسسات'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<InstitutionsReport>(
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
                        'تعذر تحميل تقرير المؤسسات',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
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
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final report = snapshot.data;

            if (report == null) {
              return _emptyState();
            }

            final rows = _filter(report.rows);

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
                        title: 'المؤسسات',
                        value: '${rows.length}',
                        icon: Icons.account_balance,
                      ),
                      const SizedBox(width: 8),
                      _summaryCard(
                        title: 'الموظفون',
                        value: '${report.totalStaff}',
                        icon: Icons.groups,
                      ),
                      const SizedBox(width: 8),
                      _summaryCard(
                        title: 'منتسبو TAM',
                        value: '${report.totalTamMembers}',
                        icon: Icons.how_to_reg,
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
                          'بحث بالمؤسسة أو المقاطعة...',
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
                const SizedBox(height: 4),
                Expanded(
                  child: rows.isEmpty
                      ? _emptyState()
                      : ListView.builder(
                          padding:
                              const EdgeInsets.all(12),
                          itemCount: rows.length,
                          itemBuilder:
                              (context, index) {
                            return _institutionCard(
                              rows[index],
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
