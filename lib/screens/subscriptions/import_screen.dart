import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/import_models.dart';
import '../../models/member.dart';
import '../../repositories/member_repository.dart';
import '../../services/subscription_importer.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _importer = SubscriptionImporter();
  final _memberRepo = MemberRepository();

  ImportAnalysisResult? _analysis;
  final Map<int, int> _manualOverrides = {};
  bool _busy = false;
  ImportConfirmResult? _result;

  Future<void> _pickAndAnalyze() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (picked == null || picked.files.single.path == null) return;

    setState(() {
      _busy = true;
      _result = null;
      _manualOverrides.clear();
    });
    final analysis = await _importer.analyze(picked.files.single.path!);
    setState(() {
      _analysis = analysis;
      _busy = false;
    });
  }

  Future<void> _pickManualMember(int rowIndex) async {
    final searchCtrl = TextEditingController();
    var results = <Member>[];

    final selected = await showModalBottomSheet<Member>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SizedBox(
            height: 400,
            child: Column(
              children: [
                TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(
                      labelText: 'ابحث عن المنتسب', prefixIcon: Icon(Icons.search)),
                  onChanged: (value) async {
                    final r = await _memberRepo.search(query: value, limit: 15);
                    setSheetState(() => results = r);
                  },
                ),
                Expanded(
                  child: ListView(
                    children: results
                        .map((m) => ListTile(
                              title: Text(m.name),
                              subtitle: Text(m.guide ?? ''),
                              onTap: () => Navigator.of(context).pop(m),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (selected != null) {
      setState(() => _manualOverrides[rowIndex] = selected.id!);
    }
  }

  Future<void> _confirm() async {
    if (_analysis == null) return;
    setState(() => _busy = true);
    final result =
        await _importer.confirm(_analysis!.items, manualOverrides: _manualOverrides);
    setState(() {
      _busy = false;
      _result = result;
      if (result.success) _analysis = null;
    });
  }

  Color _statusColor(ImportMatchType type) => switch (type) {
        ImportMatchType.exact || ImportMatchType.guide => Colors.green.shade700,
        ImportMatchType.name => Colors.orange.shade800,
        ImportMatchType.review || ImportMatchType.unmatched => Colors.red.shade700,
        ImportMatchType.historical => Colors.blueGrey,
      };

  String _statusLabel(ImportMatchType type) => switch (type) {
        ImportMatchType.exact => '✓ الاسم + الدليل',
        ImportMatchType.guide => '✓ الدليل',
        ImportMatchType.name => '⚠ الاسم فقط',
        ImportMatchType.review => 'يحتاج مراجعة',
        ImportMatchType.unmatched => 'غير مرتبط',
        ImportMatchType.historical => 'سجل تاريخي',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد بيانات الاشتراكات')),
      floatingActionButton: _analysis == null
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _pickAndAnalyze,
              icon: const Icon(Icons.upload_file),
              label: const Text('اختيار ملف CSV'),
            )
          : null,
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _result != null
              ? _buildResult(_result!)
              : _analysis == null
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'اختر ملف CSV يحتوي على أعمدة: الاسم، المبلغ، السنة، '
                          'الدليل المالي (اختياري)، تفاصيل الاشتراك...',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _buildPreview(_analysis!),
    );
  }

  Widget _buildResult(ImportConfirmResult result) {
    if (!result.success) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('فشل الاستيراد: ${result.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 48),
        const SizedBox(height: 12),
        Text('تم تنفيذ الاستيراد', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _resultLine('السجلات المضافة', '${result.added}'),
        _resultLine('سجلات تاريخية غير مرتبطة', '${result.historical}'),
        _resultLine('تحتاج مراجعة', '${result.review}'),
        _resultLine('غير المطابقة', '${result.unmatched}'),
        _resultLine('الإجمالي', '${result.total.toStringAsFixed(0)} أوقية'),
        _resultLine('مباشر للتنفيذي', '${result.directTotal.toStringAsFixed(0)} أوقية'),
      ],
    );
  }

  Widget _resultLine(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))],
        ),
      );

  Widget _buildPreview(ImportAnalysisResult analysis) {
    if (analysis.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(analysis.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('${analysis.items.length} صف — راجع الحالات المحتاجة لربط يدوي'),
              ),
              FilledButton(onPressed: _confirm, child: const Text('اعتماد الاستيراد')),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: analysis.items.length,
            itemBuilder: (context, index) {
              final item = analysis.items[index];
              final overriddenId = _manualOverrides[index];
              return Card(
                child: ListTile(
                  title: Text(item.row.name),
                  subtitle: Text(
                    '${item.row.amount.toStringAsFixed(0)} أوقية — سنة ${item.row.year}'
                    '${item.row.details.isNotEmpty ? ' — ${item.row.details}' : ''}',
                  ),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_statusLabel(item.matchType),
                          style: TextStyle(color: _statusColor(item.matchType), fontSize: 12)),
                      TextButton(
                        onPressed: () => _pickManualMember(index),
                        child: Text(overriddenId != null ? 'تم الربط يدويًا' : 'ربط يدوي'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
