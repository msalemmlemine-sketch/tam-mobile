import 'package:flutter/material.dart';

import '../../models/app_role.dart';
import '../../models/district.dart';
import '../../models/institution.dart';
import '../../repositories/district_repository.dart';
import '../../repositories/institution_repository.dart';
import '../../services/permission_service.dart';

class InstitutionFormScreen extends StatefulWidget {
  final Institution? institution;

  const InstitutionFormScreen({
    super.key,
    this.institution,
  });

  @override
  State<InstitutionFormScreen> createState() =>
      _InstitutionFormScreenState();
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

  int _apmMembers = 0;
  bool _saving = false;

  bool get _isEditing => widget.institution != null;

  bool get _canEditIdentity =>
      PermissionService.can(Permission.manageInstitutions);

  @override
  void initState() {
    super.initState();

    final inst = widget.institution;

    _nameCtrl = TextEditingController(
      text: inst?.name ?? '',
    );

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
      _loadApmCount(inst!.id!);
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
      setState(() {
        _districts = districts;
      });
    }
  }

  Future<void> _loadApmCount(int id) async {
    final count = await _institutionRepo.countMembers(id);

    if (mounted) {
      setState(() {
        _apmMembers = count;
      });
    }
  }

  int _number(TextEditingController c) {
    return int.tryParse(c.text.trim()) ?? 0;
  }

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
              onPressed: () => Navigator.pop(
                context,
                ctrl.text.trim(),
              ),
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );

    ctrl.dispose();

    if (name == null || name.isEmpty) {
      return;
    }

    try {
      final id = await _districtRepo.create(
        District(
          name: name,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );

      await _loadDistricts();

      if (mounted) {
        setState(() {
          _districtId = id;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر إضافة المقاطعة؛ قد تكون مسجلة مسبقاً.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_canEditIdentity && !_isEditing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا تملك صلاحية إضافة مؤسسة جديدة',
          ),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_districtId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'يرجى اختيار المقاطعة',
          ),
        ),
      );
      return;
    }

    final staff = _number(_staffCtrl);
    final sipes = _number(_sipesCtrl);
    final snes = _number(_snesCtrl);
    final otherUnion = _number(_otherUnionCtrl);
    final nonUnion = _number(_nonUnionCtrl);

    if (staff < _apmMembers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'إجمالي الطاقم ($staff) أقل من عدد منتسبي APM الفعليين ($_apmMembers).',
          ),
        ),
      );
      return;
    }

    if (_apmMembers +
            sipes +
            snes +
            otherUnion +
            nonUnion >
        staff) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'مجموع الفئات يتجاوز إجمالي الطاقم الكلي للمؤسسة.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

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
      final msg =
          e.toString().contains('UNIQUE constraint failed')
              ? 'توجد مؤسسة بنفس الاسم في هذه المقاطعة مسبقاً.'
              : 'تعذر الحفظ: $e';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
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

    final totalClassified =
        _apmMembers +
        sipes +
        snes +
        other +
        nonUnion;

    final remaining = staff - totalClassified;

    final apmPercentage =
        staff > 0 ? (_apmMembers * 100 / staff) : 0.0;

    final unionizedTotal =
        _apmMembers +
        sipes +
        snes +
        other;

    final unionRate =
        staff > 0 ? (unionizedTotal * 100 / staff) : 0.0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isEditing
                ? 'التقرير الميداني: ${_nameCtrl.text}'
                : 'إعداد تقرير مؤسسة تعليمية',
          ),
          elevation: 1,
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            children: [
              // 1. بطاقة الهوية الإدارية
              _buildAdministrativeCard(),

              const SizedBox(height: 16),

              // 2. نموذج تدقيق وتحديث البيانات
              _buildDataEntrySection(remaining),

              const SizedBox(height: 20),

              // 3. جدول التحليل الإحصائي
              _buildStatisticalTable(
                staff,
                sipes,
                snes,
                other,
                nonUnion,
                remaining,
              ),

              const SizedBox(height: 20),

              // 4. مؤشرات الأداء والتمثيل النقابي
              _buildKPICard(
                staff,
                apmPercentage,
                unionRate,
              ),

              const SizedBox(height: 20),

              // 5. التقييم الاستراتيجي
              _buildStrategicAssessment(
                staff: staff,
                apmCount: _apmMembers,
                apmRate: apmPercentage,
                nonUnionCount: nonUnion,
                remainingCount: remaining,
              ),

              const SizedBox(height: 24),

              // زر التثبيت والاعتماد
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                  backgroundColor: const Color(0xFF0D5344),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _saving ? null : _save,
                icon: const Icon(
                  Icons.verified_outlined,
                ),
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
                        'اعتماد وحفظ التقرير الإحصائي',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // بطاقة البيانات الأساسية للمؤسسة
  // -------------------------------------------------------------

  Widget _buildAdministrativeCard() {
    return Card(
      elevation: 0,
      color: Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'البيانات الأساسية للمؤسسة',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 10),

            TextFormField(
              controller: _nameCtrl,
              enabled: _canEditIdentity,
              decoration: const InputDecoration(
                labelText: 'اسم المؤسسة التعليمية *',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'اسم المؤسسة مطلوب';
                }

                return null;
              },
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
                          (d) => DropdownMenuItem<int>(
                            value: d.id,
                            child: Text(d.name),
                          ),
                        )
                        .toList(),
                    onChanged: _canEditIdentity
                        ? (v) {
                            setState(() {
                              _districtId = v;
                            });
                          }
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

  // -------------------------------------------------------------
  // إدخال بيانات الطاقم
  // -------------------------------------------------------------

  Widget _buildDataEntrySection(int remaining) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'أرقام الطاقم والتمثيل النقابي',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
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
                labelText:
                    'إجمالي أساتذة وطاقم المؤسسة *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              validator: _numberValidator,
              onChanged: (_) {
                setState(() {});
              },
            ),

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFE2EFEA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF0D5344)
                      .withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'المسجلون في APM - مثبت آلياً:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0D5344),
                      ),
                    ),
                  ),

                  Text(
                    '$_apmMembers أستاذ',
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
                    onChanged: (_) {
                      setState(() {});
                    },
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
                    onChanged: (_) {
                      setState(() {});
                    },
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
                    onChanged: (_) {
                      setState(() {});
                    },
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
                    onChanged: (_) {
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // الجدول الإحصائي
  // -------------------------------------------------------------

  Widget _buildStatisticalTable(
    int staff,
    int sipes,
    int snes,
    int other,
    int nonUnion,
    int remaining,
  ) {
    double calcPercent(int count) {
      return staff > 0
          ? (count * 100 / staff)
          : 0.0;
    }

    final categories = [
      {
        'name': 'تحالف أساتذة موريتانيا (APM)',
        'count': _apmMembers,
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
        'color': Colors.orange,
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
        side: BorderSide(
          color: Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF0D5344),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: const Text(
              'التوزيع الإحصائي لهيكل الطاقم',
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
              headingRowColor:
                  MaterialStateProperty.all(
                const Color(0xFFE2EFEA),
              ),
              columns: const [
                DataColumn(
                  label: Text(
                    'الفئة / الهيئة',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'العدد',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  numeric: true,
                ),
                DataColumn(
                  label: Text(
                    'النسبة من الطاقم',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  numeric: true,
                ),
              ],
              rows: categories.map((cat) {
                final count = cat['count'] as int;

                final pct = calcPercent(count);

                final isApm = cat['name']
                    .toString()
                    .contains('APM');

                return DataRow(
                  color: isApm
                      ? MaterialStateProperty.all(
                          const Color(0xFFF0F7F4),
                        )
                      : null,
                  cells: [
                    DataCell(
                      Row(
                        mainAxisSize:
                            MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  cat['color'] as Color,
                            ),
                          ),

                          const SizedBox(width: 8),

                          Text(
                            cat['name'] as String,
                            style: TextStyle(
                              fontWeight: isApm
                                  ? FontWeight.w900
                                  : FontWeight.normal,
                              color: isApm
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
                          fontWeight: isApm
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),

                    DataCell(
                      Text(
                        '${pct.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight: isApm
                              ? FontWeight.bold
                              : FontWeight.normal,
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

  // -------------------------------------------------------------
  // مؤشرات الأداء
  // -------------------------------------------------------------

  Widget _buildKPICard(
    int staff,
    double apmRate,
    double unionRate,
  ) {
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            title: 'حصة APM بالمؤسسة',
            value:
                '${apmRate.toStringAsFixed(1)}%',
            subtitle: 'من إجمالي الأساتذة',
            color: const Color(0xFF0D5344),
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: _metricCard(
            title: 'مستوى العمل النقابي',
            value:
                '${unionRate.toStringAsFixed(1)}%',
            subtitle: 'نسبة المنخرطين عموماً',
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),

          const SizedBox(height: 4),

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
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // التقييم الاستراتيجي
  // -------------------------------------------------------------

  Widget _buildStrategicAssessment({
    required int staff,
    required int apmCount,
    required double apmRate,
    required int nonUnionCount,
    required int remainingCount,
  }) {
    String statusTitle;
    String statusAnalysis;
    Color statusColor;

    List<String> recommendations = [];

    if (staff == 0) {
      statusTitle = 'البيانات غير مكتملة';

      statusAnalysis =
          'يرجى تسجيل إجمالي طاقم المؤسسة '
          'لتوليد التحليل النقابي.';

      statusColor = Colors.grey;

      recommendations.add(
        'تحديث بيانات الطاقم لحساب نسب '
        'التمثيل النقابي بدقة.',
      );
    } else if (apmRate >= 50.0) {
      statusTitle = 'موقع ريادي (أغلبية مطلقة)';

      statusColor = const Color(0xFF0D5344);

      statusAnalysis =
          'تمتلك APM قاعدة تتجاوز نصف الطاقم '
          '(${apmRate.toStringAsFixed(1)}%)، '
          'وهو ما يعكس حضوراً نقابياً قوياً داخل المؤسسة.';

      recommendations.addAll([
        'تثبيت المكاسب الحالية وتنشيط خلية المؤسسة باستمرار.',
        'توسيع التواصل مع بقية الطاقم وتعزيز الحضور المؤسسي.',
      ]);
    } else if (apmRate >= 25.0) {
      statusTitle = 'موقع تنافسي متقدم';

      statusColor = Colors.teal.shade800;

      statusAnalysis =
          'تمثل APM شريحة وازنة '
          '(${apmRate.toStringAsFixed(1)}%)، '
          'مع وجود مساحة لتعزيز الحضور داخل المؤسسة.';

      recommendations.addAll([
        'إطلاق حملة تواصل مركزة مع الأساتذة غير المنخرطين '
            '($nonUnionCount أستاذ).',
        'التنسيق في القضايا المشتركة لتعزيز الحضور المؤسسي.',
      ]);
    } else {
      statusTitle = 'تمثيل بحاجة إلى تدعيم';

      statusColor = Colors.orange.shade900;

      statusAnalysis =
          'حصة APM منخفضة نسبياً '
          '(${apmRate.toStringAsFixed(1)}%)، '
          'ما يستوجب مزيداً من التواصل والتنظيم داخل الطاقم.';

      recommendations.addAll([
        'تكليف منسق المؤسسة بزيارات تواصل فردية مباشرة مع الطاقم.',
        'الاستفادة من كتلة غير المنخرطين نقابياً لتوسيع قاعدة المنتسبين.',
      ]);
    }

    if (remainingCount > 0) {
      recommendations.add(
        'استكمال تصنيف $remainingCount من أفراد الطاقم '
        'للوصول إلى دقة إحصائية كاملة.',
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.insights,
                color: statusColor,
                size: 20,
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  'التقييم النقابي: $statusTitle',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            statusAnalysis,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
            ),
          ),

          const Divider(height: 20),

          const Text(
            'التوصيات الميدانية المقترحة:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 6),

          ...recommendations.map(
            (rec) => Padding(
              padding: const EdgeInsets.only(
                bottom: 4,
              ),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  Expanded(
                    child: Text(
                      rec,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.3,
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
}

ملاحظة مهمة: هذا التعديل يغيّر "TAM" إلى "APM" في هذه الشاشة وأسماء المتغيرات داخلها فقط. لكنه لا يغيّر اسم الحقول في قاعدة البيانات أو "InstitutionRepository" أو "Member"؛ لذلك إذا كان المقصود تحويل النظام كله من TAM إلى APM، فهذه الملفات تحتاج أيضًا إلى تعديل متناسق.
