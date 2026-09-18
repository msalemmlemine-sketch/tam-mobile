import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/member_importer.dart';
import '../../widgets/app_widgets.dart';

class MemberImportScreen extends StatefulWidget {
  const MemberImportScreen({super.key});
  @override
  State<MemberImportScreen> createState() => _MemberImportScreenState();
}

class _MemberImportScreenState extends State<MemberImportScreen> {
  final _importer = MemberImporter();
  bool _busy = false;
  MemberImportResult? _result;

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv'], withData: false);
    if (picked.isEmpty || picked.single.path == null) return;
    setState(() { _busy = true; _result = null; });
    final result = await _importer.importFile(picked.single.path!);
    if (mounted) setState(() { _busy = false; _result = result; });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد المنتسبين')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _busy ? null : _pick, icon: const Icon(Icons.upload_file_rounded), label: const Text('اختيار ملف CSV')),
      body: _busy
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('جارٍ قراءة الملف وإضافة المنتسبين...')]))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
              children: [
                Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.table_view_rounded, color: scheme.onPrimaryContainer)), const SizedBox(width: 12), Expanded(child: Text('استيراد قائمة المنتسبين', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)))]), const SizedBox(height: 14), Text('اختر ملف CSV وسيتم إنشاء المقاطعات والمؤسسات غير الموجودة تلقائيًا، مع تجاوز السجلات المكررة.', style: Theme.of(context).textTheme.bodyMedium)]))),
                AppSection(title: 'صيغة الملف', child: Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const _Field(label: 'مطلوب', value: 'الإسم • المقاطعة • المؤسسة'), const SizedBox(height: 10), const _Field(label: 'اختياري', value: 'الدليل • رقم البطاقة • الهاتف • ملاحظات')])))),
                if (_result != null)
                  AppSection(
                    title: 'نتيجة العملية',
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(children: [
                          Row(children: [
                            Icon(_result!.success ? Icons.check_circle_rounded : Icons.warning_rounded, color: _result!.success ? scheme.primary : scheme.error, size: 32),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_result!.success ? 'تم الاستيراد بنجاح' : 'تمت العملية مع ملاحظات', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                          ]),
                          const SizedBox(height: 16),
                          Row(children: [
                            Expanded(child: _ResultBox('أضيف', '${_result!.added}', scheme.primaryContainer)),
                            Expanded(child: _ResultBox('مكرر', '${_result!.skipped}', scheme.surfaceContainerHighest)),
                            Expanded(child: _ResultBox('أخطاء', '${_result!.errors}', scheme.errorContainer)),
                          ]),
                          if (_result!.error != null) ...[
                            const SizedBox(height: 14),
                            Align(alignment: AlignmentDirectional.centerStart, child: Text(_result!.error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w700))),
                          ],
                          if (_result!.messages.isNotEmpty) ...[
                            const Divider(height: 28),
                            ..._result!.messages.map((m) => Align(alignment: AlignmentDirectional.centerStart, child: Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(m)))),
                          ],
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Field extends StatelessWidget { final String label, value; const _Field({required this.label, required this.value}); @override Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Chip(label: Text(label), visualDensity: VisualDensity.compact), const SizedBox(width: 10), Expanded(child: Padding(padding: const EdgeInsets.only(top: 7), child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))))]); }
class _ResultBox extends StatelessWidget { final String label, value; final Color color; const _ResultBox(this.label, this.value, this.color); @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.symmetric(horizontal: 3), padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)), child: Column(children: [Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 2), Text(label, style: Theme.of(context).textTheme.labelSmall)])); }
