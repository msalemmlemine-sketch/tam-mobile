import 'package:flutter/material.dart';

import '../../models/district.dart';
import '../../models/institution.dart';
import '../../models/member.dart';
import '../../repositories/district_repository.dart';
import '../../repositories/institution_repository.dart';
import '../../repositories/member_repository.dart';
import '../../services/import/csv_normalizer.dart';

/// شاشة إضافة/تعديل منتسب. تُمرَّر [member] عند التعديل، وتُترك
/// فارغة عند الإضافة.
class MemberFormScreen extends StatefulWidget {
  final Member? member;
  const MemberFormScreen({super.key, this.member});

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _memberRepo = MemberRepository();
  final _districtRepo = DistrictRepository();
  final _institutionRepo = InstitutionRepository();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _guideCtrl;
  late final TextEditingController _cardNoCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _notesCtrl;

  List<District> _districts = [];
  List<Institution> _institutions = [];
  int? _districtId;
  int? _institutionId;
  String _status = 'active';
  bool _saving = false;

  bool get _isEditing => widget.member != null;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    _nameCtrl = TextEditingController(text: m?.name ?? '');
    _guideCtrl = TextEditingController(text: m?.guide ?? '');
    _cardNoCtrl = TextEditingController(text: m?.cardNo ?? '');
    _phoneCtrl = TextEditingController(text: m?.phone ?? '');
    _notesCtrl = TextEditingController(text: m?.notes ?? '');
    _districtId = m?.districtId;
    _institutionId = m?.institutionId;
    _status = m?.membershipStatus ?? 'active';
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    final districts = await _districtRepo.getAll();
    setState(() => _districts = districts);
    if (_districtId != null) await _loadInstitutions(_districtId!);
  }

  Future<void> _loadInstitutions(int districtId) async {
    final institutions = await _institutionRepo.getAll(districtId: districtId);
    setState(() => _institutions = institutions);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_districtId == null || _institutionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار المقاطعة والمؤسسة')),
      );
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now().toIso8601String();
    try {
      if (_isEditing) {
        final updated = widget.member!.copyWith(
          districtId: _districtId,
          institutionId: _institutionId,
          name: _nameCtrl.text.trim(),
          guide: _guideCtrl.text.trim(),
          cardNo: _cardNoCtrl.text.trim(),
          phone: CsvNormalizer.normalizePhone(_phoneCtrl.text.trim()),
          notes: _notesCtrl.text.trim(),
          membershipStatus: _status,
          updatedAt: now,
        );
        await _memberRepo.update(updated);
      } else {
        final member = Member(
          districtId: _districtId!,
          institutionId: _institutionId!,
          name: _nameCtrl.text.trim(),
          guide: _guideCtrl.text.trim(),
          cardNo: _cardNoCtrl.text.trim(),
          phone: CsvNormalizer.normalizePhone(_phoneCtrl.text.trim()),
          notes: _notesCtrl.text.trim(),
          membershipStatus: _status,
          createdAt: now,
          updatedAt: now,
        );
        await _memberRepo.create(member);
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'تعديل منتسب' : 'إضافة منتسب')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'الاسم الكامل *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _districtId,
              decoration: const InputDecoration(labelText: 'المقاطعة *'),
              items: _districts
                  .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _districtId = value;
                  _institutionId = null;
                  _institutions = [];
                });
                if (value != null) _loadInstitutions(value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _institutionId,
              decoration: const InputDecoration(labelText: 'المؤسسة *'),
              items: _institutions
                  .map((i) => DropdownMenuItem(value: i.id, child: Text(i.name)))
                  .toList(),
              onChanged: _districtId == null
                  ? null
                  : (value) => setState(() => _institutionId = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _guideCtrl,
              decoration: const InputDecoration(labelText: 'الدليل المالي'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cardNoCtrl,
              decoration: const InputDecoration(labelText: 'رقم البطاقة'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'الهاتف'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'حالة الانتساب'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('نشط')),
                DropdownMenuItem(value: 'inactive', child: Text('غير نشط')),
                DropdownMenuItem(value: 'suspended', child: Text('موقوف')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'active'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'ملاحظات'),
              maxLines: 3,
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
