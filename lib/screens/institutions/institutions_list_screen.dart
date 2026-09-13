import 'package:flutter/material.dart';

import '../../models/district.dart';
import '../../models/institution.dart';
import '../../repositories/district_repository.dart';
import '../../repositories/institution_repository.dart';
import 'institution_form_screen.dart';

class InstitutionsListScreen extends StatefulWidget {
  const InstitutionsListScreen({super.key});

  @override
  State<InstitutionsListScreen> createState() =>
      _InstitutionsListScreenState();
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
    final institutions = await _institutionRepo.getAll();
    final districts = await _districtRepo.getAll();
    final districtsById = {for (final d in districts) d.id: d};
    final counts = <int, int>{};
    for (final inst in institutions) {
      counts[inst.id!] = await _institutionRepo.countMembers(inst.id!);
    }
    return _Data(institutions: institutions, districtsById: districtsById, counts: counts);
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المؤسسات')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const InstitutionFormScreen()),
          );
          if (saved == true) _refresh();
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<_Data>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.institutions.isEmpty) {
            return const Center(child: Text('لا توجد مؤسسات بعد'));
          }
          return ListView.builder(
            itemCount: data.institutions.length,
            itemBuilder: (context, index) {
              final inst = data.institutions[index];
              final district = data.districtsById[inst.districtId];
              return ListTile(
                title: Text(inst.name),
                subtitle: Text(district?.name ?? '—'),
                trailing: Chip(label: Text('${data.counts[inst.id] ?? 0} منتسب')),
                onTap: () async {
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => InstitutionFormScreen(institution: inst),
                    ),
                  );
                  if (saved == true) _refresh();
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _Data {
  final List<Institution> institutions;
  final Map<int?, District> districtsById;
  final Map<int, int> counts;
  _Data({required this.institutions, required this.districtsById, required this.counts});
}
