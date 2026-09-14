import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/backup_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _backupService = BackupService();
  bool _busy = false;
  String? _message;

  Future<void> _createBackup() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await _backupService.createBackup();
    setState(() => _busy = false);

    if (!mounted) return;
    if (result.success) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(result.filePath!)],
          text: 'نسخة احتياطية من سجل منتسبي تام',
        ),
      );
    } else {
      setState(() => _message = 'فشل إنشاء النسخة: ${result.error}');
    }
  }

  Future<void> _restoreBackup() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.any,
      withData: false,
    );
    if (picked.isEmpty || picked.single.path == null) return;
    final path = picked.single.path!;

    final isValid = await _backupService.isValidSqliteFile(path);
    if (!isValid) {
      setState(() => _message = 'الملف المختار ليس نسخة قاعدة بيانات صالحة');
      return;
    }
    final sizeBytes = await _backupService.fileSizeBytes(path);
    final sizeKb = (sizeBytes / 1024).toStringAsFixed(0);

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: Text(
          'حجم الملف: $sizeKb كيلوبايت.\n\n'
          'سيتم استبدال جميع البيانات الحالية بهذه النسخة. '
          'سيُنشأ تلقائيًا نسخة أمان من البيانات الحالية قبل الاستبدال.\n\n'
          'هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('استعادة')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final result = await _backupService.restoreBackup(path);
    setState(() {
      _busy = false;
      _message = result.success
          ? 'تمت الاستعادة بنجاح. أعد تشغيل التطبيق لضمان تحميل البيانات الجديدة بالكامل.'
          : 'فشلت الاستعادة: ${result.error}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي والاستعادة')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('إنشاء نسخة احتياطية'),
                subtitle: const Text('يُنشئ ملف .db يمكن إرساله عبر واتساب/تيليجرام/بلوتوث'),
                onTap: _busy ? null : _createBackup,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.restore_outlined),
                title: const Text('استعادة نسخة احتياطية'),
                subtitle: const Text('يستبدل البيانات الحالية بملف نسخة سابقة'),
                onTap: _busy ? null : _restoreBackup,
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
