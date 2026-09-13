import 'package:flutter/material.dart';

import '../../services/export_service.dart';
import '../../services/report_service.dart';

class OverdueReportScreen extends StatefulWidget {
  const OverdueReportScreen({super.key});

  @override
  State<OverdueReportScreen> createState() => _OverdueReportScreenState();
}

class _OverdueReportScreenState extends State<OverdueReportScreen> {
  final _reportService = ReportService();
  final _exportService = ExportService();
  late Future<List<MemberDebtRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _reportService.overdueReport();
  }

  Future<void> _exportCsv(List<MemberDebtRow> rows) async {
    await _exportService.exportCsv(
      fileName: 'تقرير_المتأخرات.csv',
      headers: ['الاسم', 'المؤسسة', 'المستحق', 'المدفوع', 'المتبقي'],
      rows: rows
          .map((r) => [
                r.member.name,
                r.institutionName,
                r.totalDue.toStringAsFixed(0),
                r.totalPaid.toStringAsFixed(0),
                r.remaining.toStringAsFixed(0),
              ])
          .toList(),
    );
  }

  Future<void> _exportPdf(List<MemberDebtRow> rows) async {
    await _exportService.exportPdfTable(
      fileName: 'تقرير_المتأخرات.pdf',
      title: 'تقرير المتأخرات',
      headers: ['الاسم', 'المؤسسة', 'المستحق', 'المدفوع', 'المتبقي'],
      rows: rows
          .map((r) => [
                r.member.name,
                r.institutionName,
                r.totalDue.toStringAsFixed(0),
                r.totalPaid.toStringAsFixed(0),
                r.remaining.toStringAsFixed(0),
              ])
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تقرير المتأخرات')),
      body: FutureBuilder<List<MemberDebtRow>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return const Center(child: Text('لا توجد متأخرات حاليًا 🎉'));
          }
          final totalRemaining = rows.fold<double>(0, (s, r) => s + r.remaining);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${rows.length} منتسب — الإجمالي ${totalRemaining.toStringAsFixed(0)} أوقية'),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          onPressed: () => _exportPdf(rows),
                          tooltip: 'تصدير PDF',
                        ),
                        IconButton(
                          icon: const Icon(Icons.table_chart_outlined),
                          onPressed: () => _exportCsv(rows),
                          tooltip: 'تصدير CSV',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final r = rows[index];
                    return ListTile(
                      title: Text(r.member.name),
                      subtitle: Text(r.institutionName),
                      trailing: Text(
                        '${r.remaining.toStringAsFixed(0)} أوقية',
                        style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                      ),
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
