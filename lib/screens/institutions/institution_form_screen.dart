import 'package:flutter/material.dart';
import '../../models/app_role.dart';
import '../../models/district.dart';
import '../../models/institution.dart';
import '../../repositories/district_repository.dart';
import '../../repositories/institution_repository.dart';
import '../../services/permission_service.dart';

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
  late final TextEditingController _sipesCtrl;
  late final TextEditingController _snesCtrl;
  late final TextEditingController _otherUnionCtrl;
  late final TextEditingController _nonUnionCtrl;

  List<District> _districts = [];
  int? _districtId;
  int _tamMembers = 0;
  bool _saving = false;

  bool get _isEditing => widget.institution != null;
  bool get _canEditIdentity =>
      PermissionService.can(Permission.manageInstitutions);

  @override
  void initState() {
    super.initState();
    final inst = widget.institution;
    _nameCtrl = TextEditingController(text: inst?.name ?? '');
    _staffCtrl = TextEditingController(
      text: inst == null ? '0' : '${inst.totalStaff}',
    );
    _sipesCtrl = TextEditingController(
      text: inst == null ? '0' : '${inst.sipesMembers}',
    );
    _snesCtrl = TextEditingController(
      text: inst == null ? '0' : '${inst.snesMembers}',
    );
    _otherUnionCtrl = TextEditingController(
      text: inst == null ? '0' : '${inst.otherUnionMembers}',
    );
    _nonUnionCtrl = TextEditingController(
      text: inst == null ? '0' : '${inst.nonUnionStaff}',
    );
    _districtId = inst?.districtId;
    _loadDistricts();
    if (inst?.id != null) {
      _loadTamCount(inst!.id!);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _staffCtrl.dispose();
    _sipesCtrl.dispose();
    _snesCtrl.dispose();
    _otherUnionCtrl.dispose();
    _nonUnionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDistricts() async {
    final districts = await _districtRepo.getAll();
    if (mounted) {
      setState(() => _districts = districts);
    }
  }

  Future<void> _loadTamCount(int id) async {
    final count = await _institutionRepo.countMembers(id);
    if (mounted) {
      setState(() => _tamMembers = count);
    }
  }

  int _number(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  String? _numberValidator(String? value) {
    final n = int.tryParse((value ?? '').trim());
    if (n == null || n < 0) {
      return 'أدخل عدداً صحيحاً';
    }
    return null;
  }

  Future<void> _addDistrictInline() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('مقاطعة جديدة'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'اسم المقاطعة',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();

    if (name == null || name.isEmpty) return;

    try {
      final id = await _districtRepo.create(
        District(
          name: name,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      await _loadDistricts();
      if (mounted) {
        setState(() => _districtId = id);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر إضافة المقاطعة؛ قد تكون مسجلة مسبقاً.'),
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_canEditIdentity && !_isEditing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا تملك صلاحية إضافة مؤسسة جديدة'),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_districtId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار المقاطعة')),
      );
      return;
    }

    final staff = _number(_staffCtrl);
    final sipes = _number(_sipesCtrl);
    final snes = _number(_snesCtrl);
    final otherUnion = _number(_otherUnionCtrl);
    final nonUnion = _number(_nonUnionCtrl);

    if (staff < _tamMembers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'إجمالي الطاقم ($staff) أقل من عدد منتسبي APM الفعليين ($_tamMembers).',
          ),
        ),
      );
      return;
    }

    if (_tamMembers + sipes + snes + otherUnion + nonUnion > staff) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('مجموع الفئات يتجاوز إجمالي الطاقم الكلي للمؤسسة.'),
        ),
      );
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
        sipesMembers: sipes,
        snesMembers: snes,
        otherUnionMembers: otherUnion,
        nonUnionStaff: nonUnion,
        createdAt: widget.institution?.createdAt ?? now,
      );

      if (_isEditing) {
        await _institutionRepo.update(value);
      } else {
        await _institutionRepo.create(value);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      final msg = e.toString().contains('UNIQUE constraint failed')
          ? 'توجد مؤسسة بنفس الاسم في هذه المقاطعة مسبقاً.'
          : 'تعذر الحفظ: $e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = _number(_staffCtrl);
    final sipes = _number(_sipesCtrl);
    final snes = _number(_snesCtrl);
    final other = _number(_otherUnionCtrl);
    final nonUnion = _number(_nonUnionCtrl);

    final totalClassified = _tamMembers + sipes + snes + other + nonUnion;
    final remaining = staff - totalClassified;
    final tamPercentage = staff > 0 ? (_tamMembers * 100 / staff) : 0.0;
    final otherUnionsTotal = sipes + snes + other;
    final unionizedTotal = _tamMembers + otherUnionsTotal;
    final unionRate = staff > 0 ? (unionizedTotal * 100 / staff) : 0.0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isEditing
                ? 'التقرير والتحليل الميداني: ${_nameCtrl.text}'
                : 'إعداد تقرير وتحليل مؤسسة تعليمية',
          ),
          elevation: 1,
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              _buildAdministrativeCard(),
              const SizedBox(height: 16),
              _buildDataEntrySection(remaining),
              const SizedBox(height: 20),
              _buildDistributionBar(
                staff: staff,
                tam: _tamMembers,
                otherUnions: otherUnionsTotal,
                nonUnion: nonUnion,
                remaining: remaining,
              ),
              const SizedBox(height: 20),
              _buildKPICard(
                staff: staff,
                tamRate: tamPercentage,
                unionRate: unionRate,
                tamCount: _tamMembers,
                otherUnionsCount: otherUnionsTotal,
              ),
              const SizedBox(height: 20),
              _buildStrategicAssessment(
                staff: staff,
                tamCount: _tamMembers,
                tamRate: tamPercentage,
                sipesCount: sipes,
                snesCount: snes,
                otherUnionCount: other,
                nonUnionCount: nonUnion,
                remainingCount: remaining,
              ),
              const SizedBox(height: 20),
              _buildStatisticalTable(
                staff,
                sipes,
                snes,
                other,
                nonUnion,
                remaining,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF0D5344),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.verified_outlined),
                label: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'اعتماد وحفظ التقرير والتحليل',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdministrativeCard() {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.location_city, size: 18, color: Color(0xFF0D5344)),
                SizedBox(width: 6),
                Text(
                  'البيانات الأساسية للمؤسسة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              enabled: _canEditIdentity,
              decoration: const InputDecoration(
                labelText: 'اسم المؤسسة التعليمية *',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'اسم المؤسسة مطلوب' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _districtId,
                    decoration: const InputDecoration(
                      labelText: 'المقاطعة التابعة لها *',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: _districts
                        .map(
                          (d) => DropdownMenuItem(
                            value: d.id,
                            child: Text(d.name),
                          ),
                        )
                        .toList(),
                    onChanged: _canEditIdentity
                        ? (v) => setState(() => _districtId = v)
                        : null,
                  ),
                ),
                if (_canEditIdentity) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _addDistrictInline,
                    icon: const Icon(
                      Icons.add_circle,
                      color: Color(0xFF0D5344),
                    ),
                    tooltip: 'إضافة مقاطعة جديدة',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataEntrySection(int remaining) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.edit_note, size: 20, color: Color(0xFF0D5344)),
                    SizedBox(width: 6),
                    Text(
                      'بيانات الطاقم والتمثيل النقابي',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                if (remaining < 0)
                  Text(
                    '⚠️ تجاوز: ${remaining.abs()}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _staffCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'إجمالي أساتذة وطاقم المؤسسة *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              validator: _numberValidator,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE2EFEA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF0D5344).withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'المسجلون في تحالف APM (مثبت آلياً):',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0D5344),
                    ),
                  ),
                  Text(
                    '$_tamMembers أستاذ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: Color(0xFF0D5344),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _sipesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'منتسبو SIPES',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: _numberValidator,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _snesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'منتسبو SNES',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: _numberValidator,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _otherUnionCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'نقابات أخرى',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: _numberValidator,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _nonUnionCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'غير المنتسبين',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: _numberValidator,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistributionBar({
    required int staff,
    required int tam,
    required int otherUnions,
    required int nonUnion,
    required int remaining,
  }) {
    if (staff <= 0) return const SizedBox.shrink();

    final safeRemaining = remaining > 0 ? remaining : 0;
    final total = staff.toDouble();
    final tamFlex = ((tam / total) * 1000).toInt().clamp(0, 1000);
    final otherFlex = ((otherUnions / total) * 1000).toInt().clamp(0, 1000);
    final nonUnionFlex = ((nonUnion / total) * 1000).toInt().clamp(0, 1000);
    final remFlex = ((safeRemaining / total) * 1000).toInt().clamp(0, 1000);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'خارطة توزع القوى بالمؤسسة',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                if (tamFlex > 0)
                  Expanded(
                    flex: tamFlex,
                    child: Container(color: const Color(0xFF0D5344)),
                  ),
                if (otherFlex > 0)
                  Expanded(
                    flex: otherFlex,
                    child: Container(color: Colors.blueGrey),
                  ),
                if (nonUnionFlex > 0)
                  Expanded(
                    flex: nonUnionFlex,
                    child: Container(color: Colors.amber.shade700),
                  ),
                if (remFlex > 0)
                  Expanded(
                    flex: remFlex,
                    child: Container(color: Colors.grey.shade400),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _legendItem('تحالف APM', const Color(0xFF0D5344)),
            _legendItem('بقية النقابات', Colors.blueGrey),
            _legendItem('غير منتسبين', Colors.amber.shade700),
            if (safeRemaining > 0)
              _legendItem('غير محدد', Colors.grey.shade400),
          ],
        ),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildKPICard({
    required int staff,
    required double tamRate,
    required double unionRate,
    required int tamCount,
    required int otherUnionsCount,
  }) {
    final double relativePower = (tamCount + otherUnionsCount) > 0
        ? (tamCount * 100 / (tamCount + otherUnionsCount))
        : 0.0;

    return Row(
      children: [
        Expanded(
          child: _metricCard(
            title: 'حصة APM بالمؤسسة',
            value: '${tamRate.toStringAsFixed(1)}%',
            subtitle: 'من إجمالي طاقم المؤسسة',
            color: const Color(0xFF0D5344),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            title: 'الوزن النقابي النسبي',
            value: '${relativePower.toStringAsFixed(1)}%',
            subtitle: 'من عموم الأساتذة النقابيين',
            color: Colors.teal.shade800,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            title: 'مستوى التفاعل النقابي',
            value: '${unionRate.toStringAsFixed(1)}%',
            subtitle: 'نسبة المنخرطين نقابياً',
            color: Colors.blueGrey.shade800,
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildStrategicAssessment({
    required int staff,
    required int tamCount,
    required double tamRate,
    required int sipesCount,
    required int snesCount,
    required int otherUnionCount,
    required int nonUnionCount,
    required int remainingCount,
  }) {
    String statusTitle;
    String diagnosisText;
    Color statusColor;
    IconData statusIcon;

    final recommendations = <String>[];
    final keyInsights = <String>[];

    if (staff == 0) {
      statusTitle = 'البيانات غير مكتملة';
      diagnosisText =
          'يرجى إدخال إجمالي أفراد الطاقم لتوليد التحليل النقابي الشامل للمؤسسة.';
      statusColor = Colors.grey.shade700;
      statusIcon = Icons.info_outline;
      recommendations.add(
        'إدخال العدد الإجمالي للأساتذة لتمكين خوارزمية التحليل التنافسي.',
      );
    } else {
      final unalignedPool = nonUnionCount + (remainingCount > 0 ? remainingCount : 0);
      final unalignedRate = (unalignedPool * 100 / staff);

      final rivals = [
        {'name': 'SIPES', 'count': sipesCount},
        {'name': 'SNES', 'count': snesCount},
        {'name': 'نقابات أخرى', 'count': otherUnionCount},
      ]..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      final topRival = rivals.first;
      final topRivalCount = topRival['count'] as int;
      final isLeader = tamCount >= topRivalCount;

      if (tamRate >= 50.0) {
        statusTitle = 'هيمنة وأغلبية مطلقة';
        statusColor = const Color(0xFF0D5344);
        statusIcon = Icons.verified;
        diagnosisText =
            'يمتلك تحالف APM الأغلبية المطلقة بالمؤسسة بنسبة (${tamRate.toStringAsFixed(1)}%)، '
            'مما يجعله الممثل الرئيسي المعبر عن إرادة الطاقم والطرف الأكثر حسماً في الاستحقاقات.';
        recommendations.addAll([
          'تثبيت الكوادر الحالية وتفعيل لجان المؤسسة الميدانية بشكل دوري لمنع التآكل.',
          'استثمار موقع القوة لتأطير الأساتذة غير المنخرطين (${unalignedPool} أستاذ) للحفاظ على فارق الهيمنة.',
        ]);
      } else if (isLeader && tamCount > 0) {
        statusTitle = 'ريادة تنافسية (أغلبية نسبية)';
        statusColor = Colors.teal.shade800;
        statusIcon = Icons.trending_up;
        diagnosisText =
            'يحتل تحالف APM المرتبة الأولى داخل المؤسسة بنسبة (${tamRate.toStringAsFixed(1)}%)، '
            'متفوقاً على أقرب المنافسين (${topRival['name']} بـ $topRivalCount أستاذ)، ولكن دون بلوغ عتبة الحسم (50%).';

        final neededForMajority = (staff / 2).ceil() - tamCount;
        if (neededForMajority > 0 && neededForMajority <= unalignedPool) {
          recommendations.add(
            'هدف استراتيجي عاجل: استقطاب $neededForMajority أستاذ إضافي من غير المنتمين للوصول إلى حاجز النصف (50%).',
          );
        }
        recommendations.add(
          'التركيز على القضايا المهنية الملحة لتحويل الدعم المعنوي إلى انتساب مباشر من الكتلة المتبقية.',
        );
      } else if (tamCount > 0) {
        statusTitle = 'موقع مطاردة ومنافسة';
        statusColor = Colors.amber.shade900;
        statusIcon = Icons.compare_arrows;
        final gap = topRivalCount - tamCount;
        diagnosisText =
            'تأتي APM في المرتبة التنافسية خلف (${topRival['name']}) بفارق ($gap أستاذ). '
            'الساحة تشهد استقطاباً نشطاً يستلزم خطة ميدانية واضحة لتقليص الفارق.';
        recommendations.addAll([
          'إطلاق حملة تواصل مركزة تستهدف غير المنتمين ($unalignedPool أستاذ) الذين يمثلون كتلة الحسم الفعلية.',
          'تقديم مبادرات خدمية ونقابية سريعة تسحب المبادرة الميدانية داخل المؤسسة.',
        ]);
      } else {
        statusTitle = 'غياب التمثيل أو ضعف استثنائي';
        statusColor = Colors.red.shade800;
        statusIcon = Icons.warning_amber_rounded;
        diagnosisText =
            'لا تسجل APM أي حضور أو أن نسبتها دون الحد التنافسي (${tamRate.toStringAsFixed(1)}%)، '
            'رغم وجود طاقة استيعابية داخل المؤسسة.';
        recommendations.addAll([
          'انتداب وفد من الفرع الإقليمي لزيارة المؤسسة وعقد لقاءات تمهيدية مع الطاقم.',
          'تحديد شخصيات مؤثرة من الأساتذة غير المنخرطين لبناء النواة الأولى للتحالف بالمؤسسة.',
        ]);
      }

      keyInsights.add(
        'الكتلة المحايدة الحرة (غير منتمين/غير محدد): تشكل ${unalignedRate.toStringAsFixed(1)}% '
        '($unalignedPool أستاذ)، وتعتبر الوعاء الاستراتيجي الرئيسي للتوسع والتأثير.',
      );

      if (remainingCount > 0) {
        keyInsights.add(
          'توجد فجوة معلوماتية تخص $remainingCount أستاذ لم يتم تحديد انتمائهم بدقة بعد.',
        );
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'التقييم الاستراتيجي: $statusTitle',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            diagnosisText,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Colors.black87,
            ),
          ),
          if (keyInsights.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: keyInsights
                    .map(
                      (insight) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '💡 ',
                              style: TextStyle(fontSize: 12),
                            ),
                            Expanded(
                              child: Text(
                                insight,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade800,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          const Divider(height: 24),
          const Row(
            children: [
              Icon(Icons.checklist_rtl, size: 18, color: Color(0xFF0D5344)),
              SizedBox(width: 6),
              Text(
                'التوصيات الميدانية المقترحة:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  color: Color(0xFF0D5344),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...recommendations.map(
            (rec) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '◀ ',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF0D5344),
                      height: 1.4,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rec,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticalTable(
    int staff,
    int sipes,
    int snes,
    int other,
    int nonUnion,
    int remaining,
  ) {
    double calcPercent(int count) => staff > 0 ? (count * 100 / staff) : 0.0;
    final categories = [
      {
        'name': 'تحالف أساتذة موريتانيا (APM)',
        'count': _tamMembers,
        'color': const Color(0xFF0D5344),
      },
      {
        'name': 'النقابة المستقلة (SIPES)',
        'count': sipes,
        'color': Colors.blueGrey,
      },
      {
        'name': 'النقابة الوطنية (SNES)',
        'count': snes,
        'color': Colors.blueGrey,
      },
      {
        'name': 'نقابات تعليمية أخرى',
        'count': other,
        'color': Colors.grey,
      },
      {
        'name': 'الأساتذة غير المنخرطين نقابياً',
        'count': nonUnion,
        'color': Colors.orange.shade800,
      },
      if (remaining > 0)
        {
          'name': 'طاقم غير محدد الانتماء',
          'count': remaining,
          'color': Colors.grey.shade400,
        },
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0D5344),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: const Text(
              'الجدول التفصيلي لهيكل الطاقم بالمؤسسة',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                const Color(0xFFE2EFEA),
              ),
              columns: const [
                DataColumn(
                  label: Text(
                    'الفئة / الهيئة',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'العدد',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  numeric: true,
                ),
                DataColumn(
                  label: Text(
                    'النسبة من الطاقم',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  numeric: true,
                ),
              ],
              rows: categories.map((cat) {
                final count = cat['count'] as int;
                final pct = calcPercent(count);
                final isTam = cat['name'].toString().contains('APM');
                return DataRow(
                  color: isTam
                      ? WidgetStateProperty.all(const Color(0xFFF0F7F4))
                      : null,
                  cells: [
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cat['color'] as Color,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            cat['name'] as String,
                            style: TextStyle(
                              fontWeight:
                                  isTam ? FontWeight.w900 : FontWeight.normal,
                              color: isTam
                                  ? const Color(0xFF0D5344)
                                  : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      Text(
                        '$count',
                        style: TextStyle(
                          fontWeight:
                              isTam ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${pct.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight:
                              isTam ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
