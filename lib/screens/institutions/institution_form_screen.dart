import 'package:flutter/material.dart';

import '../../models/district.dart';
import '../../models/institution.dart';
import '../../repositories/district_repository.dart';
import '../../repositories/institution_repository.dart';

class InstitutionFormScreen extends StatefulWidget {
  final Institution? institution;
  const InstitutionFormScreen({super.key, this.institution});

  @override
  State<InstitutionFormScreen> createState() => _InstitutionFormScreenState();
}

class _InstitutionFormScreenState extends State<InstitutionFormScreen> {
  final _districtRepo = DistrictRepository();
  final _institutionRepo = InstitutionRepository();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;

  List<District> _districts = [];
  int? _districtId;
  bool _saving = false;

  bool get _isEditing => widget.institution != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.institution?.name ?? '');
    _districtId = widget.institution?.districtId;
    _loadDistricts();
  }

  Future<void> _loadDistricts() async {
    final districts = await _districtRepo.getAll();
    setState(() => _districts = districts);
  }

  Future<void> _addDistrictInline() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مقاطعة جديدة'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'اسم المقاطعة'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('إضافة')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final id = await _districtRepo.create(
      District(name: name, createdAt: DateTime.now().toIso8601String()),
    );
    await _loadDistricts();
    setState(() => _districtId = id);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_districtId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اختر المقاطعة')));
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now().toIso8601String();
    if (_isEditing) {
      await _institutionRepo.update(widget.institution!.copyWith(
        districtId: _districtId,
        name: _nameCtrl.text.trim(),
      ));
    } else {
      await _institutionRepo.create(Institution(
        districtId: _districtId!,
        name: _nameCtrl.text.trim(),
        createdAt: now,
      ));
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'تعديل مؤسسة' : 'إضافة مؤسسة')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم المؤسسة *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _districtId,
                    decoration: const InputDecoration(labelText: 'المقاطعة *'),
                    items: _districts
                        .map((d) =>
                            DropdownMenuItem(value: d.id, child: Text(d.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _districtId = v),
                  ),
                ),
                IconButton(
                  onPressed: _addDistrictInline,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'مقاطعة جديدة',
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
