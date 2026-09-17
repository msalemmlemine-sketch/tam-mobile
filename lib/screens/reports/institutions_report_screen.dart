import 'package:flutter/material.dart';

import '../../models/institution.dart';
import '../../repositories/institution_repository.dart';

class InstitutionsReportScreen extends StatefulWidget {
  const InstitutionsReportScreen({super.key});
  @override
  State<InstitutionsReportScreen> createState() => _InstitutionsReportScreenState();
}

class _InstitutionsReportScreenState extends State<InstitutionsReportScreen> {
  final _repo = InstitutionRepository();
  late Future<List<InstitutionAnalytics>> _future;

  @override
  void initState() { super.initState(); _future = _repo.getAnalytics(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تقرير المؤسسات'), actions: [IconButton(onPressed: () => setState(() => _future = _repo.getAnalytics()), icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<List<InstitutionAnalytics>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('تعذر إنشاء التقرير: ${snapshot.error}'));
          final rows = snapshot.data!;
          final staff = rows.fold<int>(0, (s, a) => s + a.institution.totalStaff);
          final tam = rows.fold<int>(0, (s, a) => s + a.tamMembers);
          final sipes = rows.fold<int>(0, (s, a) => s + a.institution.sipesMembers);
          final snes = rows.fold<int>(0, (s, a) => s + a.institution.snesMembers);
          final other = rows.fold<int>(0, (s, a) => s + a.institution.otherUnionMembers);
          final non = rows.fold<int>(0, (s, a) => s + a.institution.nonUnionStaff);
          final withTam = rows.where((a) => a.tamMembers > 0).length;
          final withoutTam = rows.length - withTam;
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
            _summary(context, rows.length, withTam, withoutTam, staff, tam, sipes, snes, other, non),
            const SizedBox(height: 12),
            const Text('المؤسسات التي بها منتسبون', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ...rows.where((a) => a.tamMembers > 0).map((a) => _row(context, a)),
            const SizedBox(height: 18),
            const Text('المؤسسات التي ليس بها منتسبون', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ...rows.where((a) => a.tamMembers == 0).map((a) => _row(context, a)),
          ]);
        },
      ),
    );
  }

  Widget _summary(BuildContext context, int institutions, int withTam, int withoutTam, int staff, int tam, int sipes, int snes, int other, int non) {
    final p = staff > 0 ? tam * 100 / staff : null;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('الملخص التنفيذي', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      Text('إجمالي المؤسسات: $institutions'),
      Text('مؤسسات بها منتسبون: $withTam'),
      Text('مؤسسات بلا منتسبين: $withoutTam'),
      Text('إجمالي الطاقم: $staff'),
      Text('منتسبو TAM / APM: $tam'),
      Text('منتسبو SIPES: $sipes'),
      Text('منتسبو SNES: $snes'),
      Text('منتسبون لنقابات أخرى: $other'),
      Text('غير النقابيين: $non'),
      const Divider(height: 22),
      Text(p == null ? 'نسبة TAM العامة: غير محددة' : 'نسبة أساتذة TAM العامة: ${p.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
    ])));
  }

  Widget _row(BuildContext context, InstitutionAnalytics a) {
    final p = a.tamPercentage;
    return Card(margin: const EdgeInsets.only(bottom: 8), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Expanded(child: Text(a.institution.name, style: const TextStyle(fontWeight: FontWeight.w900))), Text(a.districtName, style: const TextStyle(fontSize: 12))]),
      const SizedBox(height: 7),
      Text('الطاقم: ${a.institution.totalStaff}  |  TAM: ${a.tamMembers}  |  SIPES: ${a.institution.sipesMembers}  |  SNES: ${a.institution.snesMembers}  |  نقابات أخرى: ${a.institution.otherUnionMembers}  |  غير نقابيين: ${a.institution.nonUnionStaff}'),
      const SizedBox(height: 5),
      Text('نسبة TAM: ${p == null ? 'غير محددة' : '${p.toStringAsFixed(1)}%'}', style: TextStyle(fontWeight: FontWeight.w800, color: p != null && p >= 60 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error)),
    ])));
  }
}
