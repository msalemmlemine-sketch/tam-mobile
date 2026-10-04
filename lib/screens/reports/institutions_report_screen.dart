import 'package:flutter/material.dart';

import '../../models/institution.dart';
import '../../repositories/institution_repository.dart';
import '../../services/export_service.dart';

class InstitutionsReportScreen extends StatefulWidget {
  const InstitutionsReportScreen({super.key});

  @override
  State<InstitutionsReportScreen> createState() => _InstitutionsReportScreenState();
}

class _InstitutionsReportScreenState extends State<InstitutionsReportScreen> {
  final _repo = InstitutionRepository();
  final _exportService = ExportService();
  late Future<List<InstitutionAnalytics>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.getAnalytics();
  }

  List<InstitutionAnalytics> _sorted(List<InstitutionAnalytics> rows) {
    final sorted = [...rows];
    sorted.sort((a, b) {
      final d = a.districtName.compareTo(b.districtName);
      return d != 0 ? d : a.institution.name.compareTo(b.institution.name);
    });
    return sorted;
  }

  List<String> get _headers => [
        'المقاطعة',
        'المؤسسة',
        'إجمالي الطاقم',
        'منتسبو APM',
        'SIPES',
        'SNES',
        'نقابات أخرى',
        'غير نقابيين',
        'نسبة APM',
        'الحالة التنافسية',
      ];

  String _getCompetitiveLabel(InstitutionAnalytics a) {
    final staff = a.institution.totalStaff;
    if (staff == 0) return 'بيانات غير مكتملة';
    final rate = a.tamPercentage ?? 0.0;
    if (rate >= 50.0) return 'أغلبية مطلقة';
    final maxRival = [
      a.institution.sipesMembers,
      a.institution.snesMembers,
      a.institution.otherUnionMembers,
    ].reduce((curr, next) => curr > next ? curr : next);

    if (a.tamMembers > maxRival) return 'ريادة تنافسية';
    if (a.tamMembers > 0) return 'مطاردة ومنافسة';
    return 'غير ممثلة';
  }

  List<String> _rowValues(InstitutionAnalytics a) {
    final p = a.tamPercentage;
    return [
      a.districtName,
      a.institution.name,
      '${a.institution.totalStaff}',
      '${a.tamMembers}',
      '${a.institution.sipesMembers}',
      '${a.institution.snesMembers}',
      '${a.institution.otherUnionMembers}',
      '${a.institution.nonUnionStaff}',
      p == null ? '—' : '${p.toStringAsFixed(1)}%',
      _getCompetitiveLabel(a),
    ];
  }

  Future<void> _exportCsv(List<InstitutionAnalytics> rows) async {
    await _exportService.exportCsv(
      fileName: 'التقرير_التحليلي_للمؤسسات.csv',
      headers: _headers,
      rows: _sorted(rows).map(_rowValues).toList(),
    );
  }

  Future<void> _exportPdf(List<InstitutionAnalytics> rows) async {
    final staff = rows.fold<int>(0, (s, a) => s + a.institution.totalStaff);
    final tam = rows.fold<int>(0, (s, a) => s + a.tamMembers);
    final sipes = rows.fold<int>(0, (s, a) => s + a.institution.sipesMembers);
    final snes = rows.fold<int>(0, (s, a) => s + a.institution.snesMembers);
    final other = rows.fold<int>(0, (s, a) => s + a.institution.otherUnionMembers);
    final non = rows.fold<int>(0, (s, a) => s + a.institution.nonUnionStaff);
    final p = staff > 0 ? tam * 100 / staff : null;
    final otherUnions = sipes + snes + other;
    final totalUnionized = tam + otherUnions;
    final marketShare = totalUnionized > 0 ? (tam * 100 / totalUnionized) : 0.0;

    await _exportService.exportPdfReport(
      fileName: 'التقرير_التحليلي_للمؤسسات.pdf',
      title: 'التقرير الاستراتيجي والتحليلي للمؤسسات التعليمية',
      cards: [
        ReportSummaryCard(title: 'المؤسسات المرصودة', value: '${rows.length}'),
        ReportSummaryCard(title: 'إجمالي الطاقم التعليمي', value: '$staff'),
        ReportSummaryCard(title: 'منتسبو تحالف APM', value: '$tam'),
        ReportSummaryCard(
          title: 'نسبة التمثيل العامة (APM)',
          value: p == null ? '—' : '${p.toStringAsFixed(1)}%',
        ),
        ReportSummaryCard(
          title: 'الحصة من الساحة النقابية',
          value: '${marketShare.toStringAsFixed(1)}%',
        ),
        ReportSummaryCard(title: 'الكتلة غير المنتمية نقابياً', value: '$non'),
      ],
      sections: [
        ReportTableSection(
          title: 'بيانات المؤسسات والتمثيل النقابي الميداني',
          headers: _headers,
          rows: _sorted(rows).map(_rowValues).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          title: const Text('التقرير التحليلي للمؤسسات'),
          actions: [
            FutureBuilder<List<InstitutionAnalytics>>(
              future: _future,
              builder: (context, snapshot) {
                final rows = snapshot.data;
                return Row(
                  children: [
                    IconButton(
                      onPressed: rows == null ? null : () => _exportPdf(rows),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      tooltip: 'تصدير PDF',
                    ),
                    IconButton(
                      onPressed: rows == null ? null : () => _exportCsv(rows),
                      icon: const Icon(Icons.table_chart_outlined),
                      tooltip: 'تصدير CSV',
                    ),
                  ],
                );
              },
            ),
            IconButton(
              onPressed: () => setState(() => _future = _repo.getAnalytics()),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'تحديث البيانات',
            ),
          ],
        ),
        body: FutureBuilder<List<InstitutionAnalytics>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('تعذر إنشاء التقرير: ${snapshot.error}'),
              );
            }
            final rows = snapshot.data!;
            final staff = rows.fold<int>(0, (s, a) => s + a.institution.totalStaff);
            final tam = rows.fold<int>(0, (s, a) => s + a.tamMembers);
            final sipes = rows.fold<int>(0, (s, a) => s + a.institution.sipesMembers);
            final snes = rows.fold<int>(0, (s, a) => s + a.institution.snesMembers);
            final other = rows.fold<int>(0, (s, a) => s + a.institution.otherUnionMembers);
            final non = rows.fold<int>(0, (s, a) => s + a.institution.nonUnionStaff);

            final withTam = rows.where((a) => a.tamMembers > 0).toList();
            final withoutTam = rows.where((a) => a.tamMembers == 0).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 36),
              children: [
                _buildExecutiveDashboard(
                  rows.length,
                  withTam.length,
                  withoutTam.length,
                  staff,
                  tam,
                  sipes,
                  snes,
                  other,
                  non,
                ),
                const SizedBox(height: 16),
                _buildMacroAnalysisCard(
                  totalInstitutions: rows.length,
                  staff: staff,
                  tam: tam,
                  otherUnions: sipes + snes + other,
                  nonUnion: non,
                  representedInst: withTam.length,
                  rows: rows,
                ),
                const SizedBox(height: 20),
                _buildSectionHeader(
                  title: 'المؤسسات ذات الحضور الفعلي لـ APM',
                  subtitle: '${withTam.length} مؤسسة مسجلة بها تمثيل مباشر',
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF0D5344),
                ),
                const SizedBox(height: 8),
                if (withTam.isEmpty)
                  _buildEmptyState('لا توجد مؤسسات مسجل بها منتسبون حالياً')
                else
                  ...withTam.map((a) => _buildInstitutionCard(context, a)),
                const SizedBox(height: 24),
                _buildSectionHeader(
                  title: 'المؤسسات الخالية من التمثيل (فرص التوسع)',
                  subtitle: '${withoutTam.length} مؤسسة تستوجب خطة استقطاب ميدانية',
                  icon: Icons.radar_outlined,
                  color: Colors.amber.shade900,
                ),
                const SizedBox(height: 8),
                if (withoutTam.isEmpty)
                  _buildEmptyState('تحالف APM ممثل في كافة المؤسسات المسجلة')
                else
                  ...withoutTam.map((a) => _buildInstitutionCard(context, a)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildExecutiveDashboard(
    int totalInst,
    int withTam,
    int withoutTam,
    int staff,
    int tam,
    int sipes,
    int snes,
    int other,
    int non,
  ) {
    final overallTamRate = staff > 0 ? (tam * 100 / staff) : 0.0;
    final otherUnions = sipes + snes + other;
    final totalUnionized = tam + otherUnions;
    final marketShare = totalUnionized > 0 ? (tam * 100 / totalUnionized) : 0.0;
    final coverageRate = totalInst > 0 ? (withTam * 100 / totalInst) : 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.dashboard_customize_outlined,
                        size: 20, color: Color(0xFF0D5344)),
                    SizedBox(width: 8),
                    Text(
                      'لوحة المؤشرات القيادية الكبرى',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2EFEA),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$totalInst مؤسسة',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0D5344),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _statTile(
                    title: 'حصة APM الكلية',
                    value: '${overallTamRate.toStringAsFixed(1)}%',
                    caption: '$tam من أصل $staff أستاذ',
                    color: const Color(0xFF0D5344),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statTile(
                    title: 'الوزن بين النقابيين',
                    value: '${marketShare.toStringAsFixed(1)}%',
                    caption: 'من أصل $totalUnionized نقابي',
                    color: Colors.teal.shade800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statTile(
                    title: 'نسبة التغطية الميدانية',
                    value: '${coverageRate.toStringAsFixed(1)}%',
                    caption: '$withTam من $totalInst مؤسسة',
                    color: Colors.indigo.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              children: [
                _miniBadge('منتسبو APM: $tam', const Color(0xFF0D5344)),
                _miniBadge('SIPES: $sipes', Colors.blueGrey),
                _miniBadge('SNES: $snes', Colors.blueGrey),
                _miniBadge('نقابات أخرى: $other', Colors.grey.shade700),
                _miniBadge('غير النقابيين: $non', Colors.amber.shade900),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile({
    required String title,
    required String value,
    required String caption,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _miniBadge(String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildMacroAnalysisCard({
    required int totalInstitutions,
    required int staff,
    required int tam,
    required int otherUnions,
    required int nonUnion,
    required int representedInst,
    required List<InstitutionAnalytics> rows,
  }) {
    if (staff == 0) return const SizedBox.shrink();

    int majorityCount = 0;
    int competitiveCount = 0;

    for (final row in rows) {
      final s = row.institution.totalStaff;
      if (s == 0) continue;
      final rate = row.tamPercentage ?? 0.0;
      if (rate >= 50.0) {
        majorityCount++;
      } else if (row.tamMembers > 0) {
        final maxRival = [
          row.institution.sipesMembers,
          row.institution.snesMembers,
          row.institution.otherUnionMembers,
        ].reduce((c, n) => c > n ? c : n);
        if (row.tamMembers >= maxRival) {
          competitiveCount++;
        }
      }
    }

    final nonUnionRate = (nonUnion * 100 / staff);
    final emptyInstCount = totalInstitutions - representedInst;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0D5344).withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics_outlined, color: Color(0xFF0D5344), size: 20),
              SizedBox(width: 6),
              Text(
                'الرؤية الاستراتيجية وتوجيه الميدان',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: Color(0xFF0D5344),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'تحالف APM يمتلك السيطرة المطلقة في $majorityCount مؤسسة، ويقود المشهد التنافسي في $competitiveCount مؤسسة أخرى. '
            'في المقابل، تمثل الكتلة غير المنتمية نقابياً ($nonUnion أستاذ بنسبة ${nonUnionRate.toStringAsFixed(1)}%) خزان التوسع الاستراتيجي الأول للتحالف.',
            style: const TextStyle(fontSize: 12.5, height: 1.45, color: Colors.black87),
          ),
          const Divider(height: 20),
          const Text(
            'التوصيات التنفيذية للقيادة النقابية:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 6),
          _bulletPoint(
            'التحصين التنظيمي:',
            'تثبيت قواعد العمل النقابي في الـ $majorityCount مؤسسة المحسومة وتكليف مكاتبها بقيادة المبادرات.',
          ),
          _bulletPoint(
            'حسم المؤسسات التنافسية:',
            'توجيه مسؤولي الفروع إلى المؤسسات التي يقترب فيها التحالف من عتبة 50% لاستقطاب المحايدين.',
          ),
          if (emptyInstCount > 0)
            _bulletPoint(
              'كسر العزلة:',
              'وضع جدول زمني لزيارة الـ $emptyInstCount مؤسسة غير الممثلة لتشكيل خلايا تأسيسية أولية.',
            ),
        ],
      ),
    );
  }

  Widget _bulletPoint(String prefix, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(color: Color(0xFF0D5344), fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.35),
                children: [
                  TextSpan(
                    text: '$prefix ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInstitutionCard(BuildContext context, InstitutionAnalytics a) {
    final staff = a.institution.totalStaff;
    final tam = a.tamMembers;
    final rate = a.tamPercentage;
    final nonUnion = a.institution.nonUnionStaff;

    final rivals = [
      {'name': 'SIPES', 'count': a.institution.sipesMembers},
      {'name': 'SNES', 'count': a.institution.snesMembers},
      {'name': 'أخرى', 'count': a.institution.otherUnionMembers},
    ]..sort((x, y) => (y['count'] as int).compareTo(x['count'] as int));

    final topRival = rivals.first;
    final topRivalCount = topRival['count'] as int;

    String statusBadge;
    Color statusColor;
    String tacticalAdvice;

    if (staff == 0) {
      statusBadge = 'بيانات غير محددة';
      statusColor = Colors.grey;
      tacticalAdvice = 'يلزم تدقيق بيانات الطاقم لتحديد الموقف النقابي.';
    } else if (rate != null && rate >= 50.0) {
      statusBadge = 'أغلبية مطلقة';
      statusColor = const Color(0xFF0D5344);
      tacticalAdvice = 'معقل نقابي راسخ. التركيز على حماية المكتسبات والتأطير.';
    } else if (tam > topRivalCount) {
      statusBadge = 'ريادة نسبية';
      statusColor = Colors.teal.shade800;
      final needed = ((staff / 2).ceil() - tam).clamp(1, staff);
      tacticalAdvice = 'التحالف في الصدارة. استقطاب $needed فقط يحقق الأغلبية المطلقة.';
    } else if (tam > 0) {
      statusBadge = 'منافسة متأخرة';
      statusColor = Colors.amber.shade900;
      final gap = topRivalCount - tam;
      tacticalAdvice = 'الفارق $gap مع ${topRival['name']}. الوعاء المتاح: $nonUnion غير منخرط.';
    } else {
      statusBadge = 'غير ممثلة';
      statusColor = Colors.red.shade700;
      tacticalAdvice = 'المؤسسة شاغرة تماماً من التمثيل؛ مستهدفة بزيارة تواصل ميدانية.';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    a.institution.name,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    statusBadge,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'مقاطعة: ${a.districtName}  •  إجمالي الطاقم: $staff أستاذ',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'APM: $tam  |  SIPES: ${a.institution.sipesMembers}  |  SNES: ${a.institution.snesMembers}  |  أخرى: ${a.institution.otherUnionMembers}  |  غير نقابيين: $nonUnion',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'حصة APM: ${rate == null ? '—' : '${rate.toStringAsFixed(1)}%'}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    color: (rate != null && rate >= 50)
                        ? const Color(0xFF0D5344)
                        : Colors.black87,
                  ),
                ),
                Expanded(
                  child: Text(
                    tacticalAdvice,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
      ),
    );
  }
}
