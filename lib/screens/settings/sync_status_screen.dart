import 'package:flutter/material.dart';

import '../../services/cloud_config.dart';
import '../../services/cloud_realtime_sync.dart';
import '../../services/cloud_sync_engine.dart';
import '../../services/sync_outbox.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});
  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  int _pending = 0;
  bool _busy = false;
  String _status = 'جاهز';
  List<String> _errors = [];
  List<Map<String, Object?>> _failed = [];

  Future<void> _refresh() async {
    const outbox = SyncOutbox();
    final rows = await outbox.pending(limit: 100000);
    final failed = await outbox.failedWithErrors();
    if (!mounted) return;
    setState(() {
      _pending = rows.length;
      _failed = failed;
    });
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _status = 'تتم المزامنة...';
    });
    try {
      await CloudRealtimeSync.instance.start();
      final result = await CloudSyncEngine().sync(maxRows: 500);
      await _refresh();
      if (mounted) {
        setState(() {
          _errors = result.errors;
          _status = result.failed == 0
              ? 'تمت المزامنة بنجاح'
              : 'اكتملت مع وجود ${result.failed} أخطاء';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'خطأ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفع كل البيانات المحلية'),
        content: const Text(
            'سيُرفع كل ما في هذا الجهاز إلى السحابة بترتيب الآباء أولاً. '
            'استخدمه على الجهاز الذي فيه البيانات الصحيحة فقط، '
            'وليس على جهاز جديد. لا يحذف أي بيانات محلية.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('متابعة')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _status = 'تجهيز العمليات...';
      _errors = [];
    });
    try {
      await CloudRealtimeSync.instance.start();
      final queued = await const SyncOutbox().enqueueAllLocalRows();
      var totalPushed = 0;
      var lastErrors = <String>[];
      for (var i = 0; i < 40; i++) {
        final result = await CloudSyncEngine().sync(maxRows: 200);
        totalPushed += result.pushed;
        lastErrors = result.errors;
        await _refresh();
        if (mounted) {
          setState(() => _status =
              'رُفع $totalPushed من $queued — المتبقي $_pending');
        }
        if (_pending == 0 || result.pushed == 0) break;
      }
      if (mounted) {
        setState(() {
          _errors = lastErrors;
          _status = _pending == 0
              ? 'اكتمل رفع كل البيانات ($totalPushed)'
              : 'توقف الرفع: بقي $_pending عملية، راجع الأخطاء أدناه';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'خطأ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Widget _errorBox(String title, List<String> lines) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                lines.join('\n\n'),
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onlineConfig = CloudConfig.enabled;
    return Scaffold(
      appBar: AppBar(title: const Text('حالة المزامنة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
            child: ListTile(
                leading:
                    Icon(onlineConfig ? Icons.cloud_done : Icons.cloud_off),
                title: const Text('Supabase'),
                subtitle: Text(onlineConfig
                    ? 'مهيأ'
                    : 'غير مهيأ — يجب تمرير مفاتيح البناء'))),
        Card(
            child: ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('المزامنة'),
                subtitle: Text(_status))),
        Card(
            child: ListTile(
                leading: const Icon(Icons.pending_actions),
                title: const Text('العمليات المعلقة'),
                trailing: Text('$_pending',
                    style: Theme.of(context).textTheme.titleLarge))),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: _busy ? null : _sync,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            label: const Text('مزامنة الآن')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: _busy ? null : _uploadAll,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('رفع كل البيانات المحلية (الجهاز القديم فقط)')),
        if (_errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          _errorBox('أخطاء آخر مزامنة', _errors),
        ],
        if (_failed.isNotEmpty) ...[
          const SizedBox(height: 12),
          _errorBox(
            'أخطاء العمليات المعلقة',
            _failed
                .map((r) =>
                    '#${r['id']} ${r['table_name']} ${r['operation']} '
                    '(محاولات: ${r['attempt_count']})\n${r['last_error']}')
                .toList(),
          ),
        ],
      ]),
    );
  }
}
