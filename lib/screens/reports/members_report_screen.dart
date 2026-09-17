import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../services/report_service.dart';
import '../../services/export_service.dart';

class MembersReportScreen extends StatefulWidget {
  const MembersReportScreen({super.key});

  @override
  State<MembersReportScreen> createState() => _MembersReportScreenState();
}

class _MembersReportScreenState extends State<MembersReportScreen> {
  final ReportService _reportService = ReportService();
  final ExportService _exportService = ExportService();

  late Future<List<({Member member, String institutionName})>> _future;

  int? _institutionId;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = _reportService.membersReport(
        institutionId: _institutionId,
      );
    });
  }

  List<({Member member, String institutionName})> _filter(
    List<({Member member, String institutionName})> rows,
  ) {
    final q = _search.trim().toLowerCase();

    if (q.isEmpty) return rows;

    return rows.where((row) {
      final member = row.member;

      return member.name.toLowerCase().contains(q) ||
          row.institutionName.toLowerCase().contains(q) ||
          (member.guide ?? '').toLowerCase().contains(q) ||
          (member.cardNo ?? '').toLowerCase().contains(q) ||
          (member.phone ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Map<String, List<({Member member, String institutionName})>> _groupByInstitution(
    List<({Member member, String institutionName})> rows,
  ) {
    final grouped =
        <String, List<({Member member, String institutionName})>>{};

    for (final row in rows) {
      grouped.putIfAbsent(row.institutionName, () => []).add(row);
    }

    final entries = grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Map.fromEntries(entries);
  }

  Future<void> _exportCsv(
    List<({Member member, String institutionName})> rows,
  ) async {
    if (rows.isEmpty) return;

    final grouped = _groupByInstitution(rows);

    final data = <List<String>>[
      ['المؤسسة', 'الاسم', 'الدليل المالي', 'رقم البطاقة', 'الهاتف', 'الحالة'],
    ];

    for (final entry in grouped.entries) {
      for (final row in entry.value) {
        final m = row.member;

        data.add([
          entry.key,
          m.name,
          m.guide ?? '',
          m.cardNo ?? '',
          m.phone ?? '',
          m.membershipStatus,
        ]);
      }
    }

    await _exportService.exportCsv(
      fileName: 'liste_des_adherents_par_institution.csv',
      rows: data,
    );
  }

  Future<void> _exportPdf(
    List<({Member member, String institutionName})> rows,
  ) async {
    if (rows.isEmpty) return;

    final grouped = _groupByInstitution(rows);

    final headers = [
      'الاسم',
      'الدليل المالي',
      'رقم البطاقة',
      'الهاتف',
      'الحالة',
    ];

    final sections = <Map<String, dynamic>>[];

    for (final entry in grouped.entries) {
      sections.add({
        'title': entry.key,
        'rows': entry.value.map((row) {
          final m = row.member;

          return [
            m.name,
            m.guide ?? '—',
            m.cardNo ?? '—',
            m.phone ?? '—',
            _statusLabel(m.membershipStatus),
          ];
        }).toList(),
      });
    }

    await _exportService.exportPdfTable(
      fileName: 'liste_des_adherents_par_institution.pdf',
      title: 'لائحة المنتسبين',
      headers: headers,
      rows: rows.map((row) {
        final m = row.member;

        return [
          m.name,
          row.institutionName,
          m.guide ?? '—',
          m.cardNo ?? '—',
          m.phone ?? '—',
          _statusLabel(m.membershipStatus),
        ];
      }).toList(),
    );
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'نشط';
      case 'inactive':
        return 'غير نشط';
      case 'suspended':
        return 'موقوف';
      default:
        return status;
    }
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
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, size: 24),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _institutionSection(
    String institution,
    List<({Member member, String institutionName})> rows,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.account_balance),
        title: Text(
          institution,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text('${rows.length} منتسب'),
        children: [
          const Divider(height: 1),
          ...List.generate(rows.length, (index) {
            final row = rows[index];
            final member = row.member;

            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 17,
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
                  if ((member.guide ?? '').isNotEmpty)
                    Text('الدليل: ${member.guide}'),
                  if ((member.cardNo ?? '').isNotEmpty)
                    Text('البطاقة: ${member.cardNo}'),
                  if ((member.phone ?? '').isNotEmpty)
                    Text('الهاتف: ${member.phone}'),
                ],
              ),
              trailing: _statusChip(member.membershipStatus),
            );
          }),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    return Chip(
      label: Text(
        _statusLabel(status),
        style: const TextStyle(fontSize: 11),
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لائحة المنتسبين'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<List<({Member member, String institutionName})>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
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
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'تعذر تحميل لائحة المنتسبين',
                        style: Theme.of(context).textTheme.titleMedium,
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
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final allRows = snapshot.data ?? [];
            final rows = _filter(allRows);
            final grouped = _groupByInstitution(rows);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Row(
                    children: [
                      _summaryCard(
                        title: 'إجمالي المنتسبين',
                        value: '${rows.length}',
                        icon: Icons.groups,
                      ),
                      const SizedBox(width: 8),
                      _summaryCard(
                        title: 'المؤسسات',
                        value: '${grouped.length}',
                        icon: Icons.account_balance,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      hintText: 'بحث بالاسم أو المؤسسة أو الهاتف...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                setState(() {
                                  _search = '';
                                });
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
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
                          icon: const Icon(Icons.table_view),
                          label: const Text('CSV'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: rows.isEmpty
                              ? null
                              : () => _exportPdf(rows),
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('PDF'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: rows.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد بيانات منتسبين',
                            style: TextStyle(fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: grouped.length,
                          itemBuilder: (context, index) {
                            final entry =
                                grouped.entries.elementAt(index);

                            return _institutionSection(
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
