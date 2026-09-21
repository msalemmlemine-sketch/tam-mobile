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

  Future<void> _refresh() async {
    final rows = await const SyncOutbox().pending(limit: 100000);
    if (!mounted) return;
    setState(() => _pending = rows.length);
  }

  Future<void> _sync() async {
    setState(() { _busy = true; _status = 'تتم المزامنة...'; });
    try {
      await CloudRealtimeSync.instance.start();
      final result = await CloudSyncEngine().sync(maxRows: 500);
      await _refresh();
      if (mounted) setState(() => _status = result.failed == 0 ? 'تمت المزامنة بنجاح' : 'اكتملت مع وجود ${result.failed} أخطاء');
    } catch (e) {
      if (mounted) setState(() => _status = 'خطأ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() { super.initState(); _refresh(); }

  @override
  Widget build(BuildContext context) {
    final onlineConfig = CloudConfig.enabled;
    return Scaffold(
      appBar: AppBar(title: const Text('حالة المزامنة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(leading: Icon(onlineConfig ? Icons.cloud_done : Icons.cloud_off), title: const Text('Supabase'), subtitle: Text(onlineConfig ? 'مهيأ' : 'غير مهيأ — يجب تمرير مفاتيح البناء'))),
        Card(child: ListTile(leading: const Icon(Icons.sync), title: const Text('المزامنة'), subtitle: Text(_status))),
        Card(child: ListTile(leading: const Icon(Icons.pending_actions), title: const Text('العمليات المعلقة'), trailing: Text('$_pending', style: Theme.of(context).textTheme.titleLarge))),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _busy ? null : _sync, icon: _busy ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.sync), label: const Text('مزامنة الآن')),
      ]),
    );
  }
}
