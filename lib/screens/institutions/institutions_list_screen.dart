import 'package:flutter/material.dart';

import '../../models/district.dart';
import '../../models/institution.dart';
import '../../repositories/district_repository.dart';
import '../../repositories/institution_repository.dart';
import 'institution_form_screen.dart';

class InstitutionsListScreen extends StatefulWidget {
  const InstitutionsListScreen({super.key});

  @override
  State<InstitutionsListScreen> createState() => _InstitutionsListScreenState();
}

class _InstitutionsListScreenState extends State<InstitutionsListScreen> {
  final _institutionRepo = InstitutionRepository();
  final _districtRepo = DistrictRepository();
  late Future<_Data> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Data> _load() async {
    final analytics = await _institutionRepo.getAnalytics();
    final districts = await _districtRepo.getAll();
    return _Data(analytics: analytics, districts: districts);
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المؤسسات'), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded), tooltip: 'تحديث')]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () async { final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const InstitutionFormScreen())); if (saved == true) _refresh(); }, icon: const Icon(Icons.add), label: const Text('مؤسسة')),
      body: FutureBuilder<_Data>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('تعذر تحميل المؤسسات: ${snapshot.error}'));
          final data = snapshot.data!;
          final totalStaff = data.analytics.fold<int>(0, (s, a) => s + a.institution.totalStaff);
          final tam = data.analytics.fold<int>(0, (s, a) => s + a.tamMembers);
          final other = data.analytics.fold<int>(0, (s, a) => s + a.institution.otherUnionMembers);
          final non = data.analytics.fold<int>(0, (s, a) => s + a.institution.nonUnionStaff);
          final withMembers = data.analytics.where((a) => a.tamMembers > 0).length;
          final withoutMembers = data.analytics.length - withMembers;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
            children: [
              _summary(context, data.analytics.length, withMembers, withoutMembers, totalStaff, tam),
              const SizedBox(height: 12),
              if (data.analytics.isNotEmpty) ...[
                _classificationCard(context, totalStaff, tam, other, non),
                const SizedBox(height: 12),
              ],
              ..._districtSections(context, data.analytics),
            ],
          );
        },
      ),
    );
  }

  Widget _summary(BuildContext context, int institutions, int withMembers, int withoutMembers, int staff, int tam) {
    final p = staff > 0 ? tam * 100 / staff : null;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('ملخص المؤسسات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _chip('المؤسسات', institutions), _chip('بها منتسبون', withMembers), _chip('بدون منتسبين', withoutMembers), _chip('إجمالي الطاقم', staff), _chip('TAM / APM', tam),
      ]),
      const SizedBox(height: 12),
      Text(p == null ? 'نسبة TAM العامة: غير محددة' : 'نسبة أساتذة TAM العامة: ${p.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w800)),
    ])));
  }

  Widget _classificationCard(BuildContext context, int staff, int tam, int other, int non) {
    final scheme = Theme.of(context).colorScheme;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('تركيب طواقم المؤسسات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      _barLine(context, 'TAM / APM', tam, staff, scheme.primary),
      _barLine(context, 'نقابات أخرى', other, staff, scheme.tertiary),
      _barLine(context, 'غير نقابيين', non, staff, scheme.secondary),
    ])));
  }

  Widget _barLine(BuildContext context, String label, int value, int total, Color color) {
    final p = total > 0 ? value / total : 0.0;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(total > 0 ? '$value (${(p * 100).toStringAsFixed(1)}%)' : '$value')]), const SizedBox(height: 4), ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: p.clamp(0, 1), minHeight: 8, color: color))]));
  }

  List<Widget> _districtSections(BuildContext context, List<InstitutionAnalytics> rows) {
    final byDistrict = <String, List<InstitutionAnalytics>>{};
    for (final row in rows) { (byDistrict[row.districtName] ??= []).add(row); }
    final result = <Widget>[];
    for (final entry in byDistrict.entries) {
      final list = entry.value;
      final tam = list.fold<int>(0, (s, a) => s + a.tamMembers);
      final staff = list.fold<int>(0, (s, a) => s + a.institution.totalStaff);
      result.add(Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(entry.key, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), Text('${list.length} مؤسسة · $tam TAM', style: const TextStyle(fontWeight: FontWeight.w700))])));
      for (final a in list) result.add(_institutionTile(context, a));
      final p = staff > 0 ? tam * 100 / staff : null;
      result.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(p == null ? 'نسبة TAM في المقاطعة: غير محددة' : 'نسبة TAM في المقاطعة: ${p.toStringAsFixed(1)}%', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700))));
    }
    return result;
  }

  Widget _institutionTile(BuildContext context, InstitutionAnalytics a) {
    final p = a.tamPercentage;
    final status = a.tamMembers == 0 ? 'لا يوجد منتسبون' : p == null ? 'الطاقم غير محدد' : p >= 80 ? 'انتساب مرتفع' : p >= 60 ? 'جيد' : p >= 40 ? 'متوسط' : 'يحتاج متابعة';
    final color = a.tamMembers == 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary;
    return Card(margin: const EdgeInsets.only(bottom: 8), child: InkWell(borderRadius: BorderRadius.circular(20), onTap: () async { final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => InstitutionFormScreen(institution: a.institution))); if (saved == true) _refresh(); }, child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Expanded(child: Text(a.institution.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))), Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w800))]),
      const SizedBox(height: 9),
      Wrap(spacing: 14, runSpacing: 6, children: [Text('الطاقم: ${a.institution.totalStaff}'), Text('TAM: ${a.tamMembers}'), Text('نقابات أخرى: ${a.institution.otherUnionMembers}'), Text('غير نقابيين: ${a.institution.nonUnionStaff}'), Text('النسبة: ${p == null ? '—' : '${p.toStringAsFixed(1)}%'}')]),
    ]))));
  }

  Widget _chip(String label, int value) => Chip(label: Text('$label: $value'), visualDensity: VisualDensity.compact);
}

class _Data {
  final List<InstitutionAnalytics> analytics;
  final List<District> districts;
  _Data({required this.analytics, required this.districts});
}
