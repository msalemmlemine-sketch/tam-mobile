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
  late final TextEditingController _staffCtrl;
  late final TextEditingController _otherUnionCtrl;
  late final TextEditingController _nonUnionCtrl;

  List<District> _districts = [];
  int? _districtId;
  int _tamMembers = 0;
  bool _saving = false;
  bool get _isEditing => widget.institution != null;

  @override
  void initState() {
    super.initState();
    final inst = widget.institution;
    _nameCtrl = TextEditingController(text: inst?.name ?? '');
    _staffCtrl = TextEditingController(text: inst == null ? '' : '${inst.totalStaff}');
    _otherUnionCtrl = TextEditingController(text: inst == null ? '' : '${inst.otherUnionMembers}');
    _nonUnionCtrl = TextEditingController(text: inst == null ? '' : '${inst.nonUnionStaff}');
    _districtId = inst?.districtId;
    _loadDistricts();
    if (inst?.id != null) _loadTamCount(inst!.id!);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _staffCtrl.dispose();
    _otherUnionCtrl.dispose();
    _nonUnionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDistricts() async {
    final districts = await _districtRepo.getAll();
    if (mounted) setState(() => _districts = districts);
  }

  Future<void> _loadTamCount(int id) async {
    final count = await _institutionRepo.countMembers(id);
    if (mounted) setState(() => _tamMembers = count);
  }

  int _number(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  String? _numberValidator(String? value) {
    final n = int.tryParse((value ?? '').trim());
    if (n == null || n < 0) return 'أدخل عددًا صحيحًا غير سالب';
    return null;
  }

  Future<void> _addDistrictInline() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مقاطعة جديدة'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'اسم المقاطعة')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('إضافة')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final id = await _districtRepo.create(District(name: name, createdAt: DateTime.now().toIso8601String()));
      await _loadDistricts();
      if (mounted) setState(() => _districtId = id);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر إضافة المقاطعة؛ قد تكون مسجلة مسبقًا.')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_districtId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر المقاطعة')));
      return;
    }
    final staff = _number(_staffCtrl);
    final otherUnion = _number(_otherUnionCtrl);
    final nonUnion = _number(_nonUnionCtrl);
    if (staff < _tamMembers) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('إجمالي الطاقم ($staff) أقل من عدد منتسبي TAM الحاليين ($_tamMembers).')));
      return;
    }
    if (_tamMembers + otherUnion + nonUnion > staff) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مجموع TAM + النقابات الأخرى + غير النقابيين يتجاوز إجمالي الطاقم.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final value = Institution(
        id: widget.institution?.id,
        districtId: _districtId!,
        name: _nameCtrl.text.trim(),
        totalStaff: staff,
        otherUnionMembers: otherUnion,
        nonUnionStaff: nonUnion,
        createdAt: widget.institution?.createdAt ?? now,
      );
      if (_isEditing) {
        await _institutionRepo.update(value);
      } else {
        await _institutionRepo.create(value);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ المؤسسة: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = _number(_staffCtrl);
    final remaining = staff - _tamMembers - _number(_otherUnionCtrl) - _number(_nonUnionCtrl);
    final percentage = staff > 0 ? _tamMembers * 100 / staff : null;
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'بيانات المؤسسة' : 'إضافة مؤسسة')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'اسم المؤسسة *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: DropdownButtonFormField<int>(value: _districtId, decoration: const InputDecoration(labelText: 'المقاطعة *'), items: _districts.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))).toList(), onChanged: (v) => setState(() => _districtId = v))),
              IconButton(onPressed: _addDistrictInline, icon: const Icon(Icons.add_circle_outline), tooltip: 'مقاطعة جديدة'),
            ]),
            const SizedBox(height: 20),
            _sectionTitle('تركيب طاقم المؤسسة'),
            TextFormField(controller: _staffCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'إجمالي طاقم المؤسسة *', helperText: 'عدد الأساتذة/أعضاء الطاقم في المؤسسة'), validator: _numberValidator, onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            _readonlyMetric('منتسبو TAM / APM', _tamMembers, percentage),
            const SizedBox(height: 10),
            TextFormField(controller: _otherUnionCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'منتسبون لنقابات أخرى'), validator: _numberValidator, onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            TextFormField(controller: _nonUnionCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'غير النقابيين'), validator: _numberValidator, onChanged: (_) => setState(() {})),
            const SizedBox(height: 14),
            Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(remaining >= 0 ? 'المتبقي غير المصنف: $remaining' : '⚠️ يوجد تجاوز في التصنيف: ${remaining.abs()}', style: TextStyle(fontWeight: FontWeight.w800, color: remaining < 0 ? Theme.of(context).colorScheme.error : null)),
              const SizedBox(height: 8),
              Text(percentage == null ? 'نسبة TAM: غير محددة (لم يُدخل إجمالي الطاقم)' : 'نسبة أساتذة TAM: ${percentage.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]))),
            const SizedBox(height: 24),
            ElevatedButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('حفظ بيانات المؤسسة')),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)));

  Widget _readonlyMetric(String label, int value, double? percentage) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [const Icon(Icons.verified_user_outlined), const SizedBox(width: 12), Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))), Text('$value${percentage == null ? '' : ' (${percentage.toStringAsFixed(1)}%)'}', style: const TextStyle(fontWeight: FontWeight.w900))])));
}
