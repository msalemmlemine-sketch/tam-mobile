import 'package:flutter/material.dart';

import '../../models/district.dart';
import '../../models/institution.dart';
import '../../models/member.dart';
import '../../repositories/district_repository.dart';
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
  final _districtRepo = DistrictRepository();

  List<Institution> _institutions = [];
  List<District> _districts = [];
  int? _institutionId;
  int? _districtId;
  late Future<List<MembersReportRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _reportService.membersReport();
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    final institutions = await _institutionRepo.getAll();
    final districts = await _districtRepo.getAll();
    setState(() {
      _institutions = institutions;
      _districts = districts;
    });
  }

  /// يطبّق التصفية الجديدة. اختيار مؤسسة معيّنة يمسح تصفية
  /// المقاطعة تلقائيًا (تصفية أدقّ تفوز)، واختيار مقاطعة يمسح
  /// المؤسسة المختارة سابقًا لتجنّب تعارض غير منطقي.
  void _applyFilter({int? institutionId, int? districtId}) {
    setState(() {
      _institutionId = institutionId;
      _districtId = institutionId != null ? null : districtId;
      _future = _reportService.membersReport(
        institutionId: _institutionId,
        districtId: _districtId,
      );
    });
  }

  Future<void> _exportCsv(List<MembersReportRow> rows) async {
    await _exportService.exportCsv(
      fileName: 'تقرير_المنتسبين.csv',
      headers: ['الاسم', 'المقاطعة', 'المؤسسة', 'الدليل المالي', 'رقم البطاقة', 'الهاتف', 'الحالة'],
      rows: rows
          .map((r) => [
                r.member.name,
                r.districtName,
                r.institutionName,
                r.member.guide ?? '',
                r.member.cardNo ?? '',
                r.member.phone ?? '',
                r.member.membershipStatus,
              ])
          .toList(),
    );
  }

  /// يجمّع المنتسبين حسب المؤسسة ويصدّر لائحة بنفس شكل نموذج
  /// LISTE.pdf: شارة خضراء بعدد المنتسبين لكل مؤسسة، وترقيم
  /// تسلسلي يبدأ من 1 داخل كل مؤسسة. المؤسسات تُرتَّب حسب
  /// مقاطعتها أولًا (sortOrder ثم اسم المقاطعة أبجديًا) ثم حسب
  /// اسم المؤسسة داخل نفس المقاطعة.
  Future<void> _exportPdf(List<MembersReportRow> rows) async {
    final grouped = <String, List<Member>>{};
    final groupDistrictOrder = <String, int>{};
    final groupDistrictName = <String, String>{};

    for (final r in rows) {
      grouped.putIfAbsent(r.institutionName, () => []).add(r.member);
      groupDistrictOrder[r.institutionName] = r.districtSortOrder;
      groupDistrictName[r.institutionName] = r.districtName;
    }

    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        final orderCmp = groupDistrictOrder[a]!.compareTo(groupDistrictOrder[b]!);
        if (orderCmp != 0) return orderCmp;
        final nameCmp = groupDistrictName[a]!.compareTo(groupDistrictName[b]!);
        if (nameCmp != 0) return nameCmp;
        return a.compareTo(b);
      });

    final sections = [
      for (final key in sortedKeys)
        ReportGroupedListSection(
          groupTitle: key,
          rows: [
            for (final m in grouped[key]!)
              {
                'name': m.name,
                'guide': m.guide ?? '',
                'cardNo': m.cardNo ?? '',
                'phone': m.phone ?? '',
                'notes': '',
              },
          ],
        ),
    ];

    await _exportService.exportPdfGroupedList(
      fileName: 'لائحة_المنتسبين.pdf',
      title: 'لائحة المنتسبين',
      groups: sections,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير المنتسبين'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int?>(
                  value: _districtId,
                  decoration: const InputDecoration(labelText: 'تصفية حسب المقاطعة', isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('كل المقاطعات')),
                    ..._districts.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))),
                  ],
                  onChanged: (v) => _applyFilter(districtId: v),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<int?>(
                  value: _institutionId,
                  decoration: const InputDecoration(labelText: 'تصفية حسب المؤسسة', isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('كل المؤسسات')),
                    ..._institutions
                        .where((i) => _districtId == null || i.districtId == _districtId)
                        .map((i) => DropdownMenuItem(value: i.id, child: Text(i.name))),
                  ],
                  onChanged: (v) => _applyFilter(institutionId: v),
                ),
              ],
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<MembersReportRow>>(
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
                      subtitle: Text('${r.districtName} — ${r.institutionName}'),
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
