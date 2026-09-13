import 'package:flutter/material.dart';

import '../../models/institution.dart';
import '../../models/member.dart';
import '../../repositories/institution_repository.dart';
import '../../services/export_service.dart';
import '../../services/report_service.dart';

class MembersReportScreen extends StatefulWidget {
  const MembersReportScreen({super.key});

  @override
  State<MembersReportScreen> createState() => _MembersReportScreenState();
}

class _MembersReportScreenState extends State<MembersReportScreen> {
  final _reportService = ReportService();
  final _exportService = ExportService();
  final _institutionRepo = InstitutionRepository();

  List<Institution> _institutions = [];
  int? _institutionId;
  late Future<List<({Member member, String institutionName})>> _future;

  @override
  void initState() {
    super.initState();
    _future = _reportService.membersReport();
    _loadInstitutions();
  }

  Future<void> _loadInstitutions() async {
    final institutions = await _institutionRepo.getAll();
    setState(() => _institutions = institutions);
  }

  void _applyFilter(int? institutionId) {
    setState(() {
      _institutionId = institutionId;
      _future = _reportService.membersReport(institutionId: institutionId);
    });
  }

  Future<void> _exportCsv(List<({Member member, String institutionName})> rows) async {
    await _exportService.exportCsv(
      fileName: 'تقرير_المنتسبين.csv',
      headers: ['الاسم', 'المؤسسة', 'الدليل المالي', 'رقم البطاقة', 'الهاتف', 'الحالة'],
      rows: rows
          .map((r) => [
                r.member.name,
                r.institutionName,
                r.member.guide ?? '',
                r.member.cardNo ?? '',
                r.member.phone ?? '',
                r.member.membershipStatus,
              ])
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير المنتسبين'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: DropdownButtonFormField<int?>(
              value: _institutionId,
              decoration: const InputDecoration(labelText: 'تصفية حسب المؤسسة', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('كل المؤسسات')),
                ..._institutions
                    .map((i) => DropdownMenuItem(value: i.id, child: Text(i.name))),
              ],
              onChanged: _applyFilter,
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<({Member member, String institutionName})>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${rows.length} منتسب'),
                    IconButton(
                      icon: const Icon(Icons.table_chart_outlined),
                      onPressed: () => _exportCsv(rows),
                      tooltip: 'تصدير CSV',
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
                      trailing: Text(r.member.phone ?? ''),
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
