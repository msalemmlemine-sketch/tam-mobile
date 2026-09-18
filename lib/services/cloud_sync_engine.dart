import 'dart:convert';

import 'cloud_config.dart';
import 'cloud_service.dart';
import 'sync_outbox.dart';

class CloudSyncSummary {
  final int pushed;
  final int pulled;
  final int failed;
  const CloudSyncSummary({required this.pushed, required this.pulled, required this.failed});
}

class CloudSyncEngine {
  CloudSyncEngine({CloudService? cloud, SyncOutbox? outbox})
      : _cloud = cloud ?? CloudService(), _outbox = outbox ?? const SyncOutbox();
  final CloudService _cloud;
  final SyncOutbox _outbox;

  Future<CloudSyncSummary> sync({int maxRows = 100}) async {
    if (!CloudConfig.enabled) return const CloudSyncSummary(pushed: 0, pulled: 0, failed: 0);
    var failed = 0;
    var pushed = 0;
    try {
      // Pull first so الهاتف الجديد لا يدفع بيانات seed محلية فوق السحابة.
      await _cloud.pullAllToLocal();
    } catch (_) {
      // لا نمنع العمل المحلي؛ سنحاول الدفع فقط للصفوف المعلقة.
    }
    final rows = await _outbox.pending(limit: maxRows);
    for (final entry in rows) {
      final id = entry['id'] as int;
      try {
        final payload = Map<String, Object?>.from(
          jsonDecode(entry['payload_json'] as String? ?? '{}') as Map,
        );
        await _cloud.upsertRow(
          table: entry['table_name'] as String,
          legacyId: entry['local_row_id'] as int,
          row: payload,
        );
        await _outbox.markSynced(id);
        pushed++;
      } catch (e) {
        await _outbox.markFailed(id, e.toString());
        failed++;
      }
    }
    try {
      await _cloud.pullAllToLocal();
    } catch (_) {}
    return CloudSyncSummary(pushed: pushed, pulled: 1, failed: failed);
  }

  Future<CloudSyncSummary> pushPending({int maxRows = 100}) => sync(maxRows: maxRows);
}
