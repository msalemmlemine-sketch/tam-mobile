import 'dart:convert';

import 'cloud_config.dart';
import 'cloud_service.dart';
import 'sync_outbox.dart';

class CloudSyncSummary {
  final int pushed;
  final int failed;
  final int skippedNotConfigured;
  const CloudSyncSummary({
    required this.pushed,
    required this.failed,
    required this.skippedNotConfigured,
  });
}

/// يُفرِّغ صف انتظار [SyncOutbox] برفعها إلى Supabase عبر [CloudService].
///
/// لا يوقف الحلقة عند أول فشل (انقطاع إنترنت، صف غير موجود بعد على
/// الخادم، ...) — يُسجِّل الخطأ في نفس سطر outbox (last_error +
/// attempt_count) وينتقل للسطر التالي، بحيث لا تمنع دفعة واحدة
/// معطوبة رفع بقية المنتسبين/الدفعات السليمة.
class CloudSyncEngine {
  CloudSyncEngine({CloudService? cloud, SyncOutbox? outbox})
      : _cloud = cloud ?? CloudService(),
        _outbox = outbox ?? const SyncOutbox();

  final CloudService _cloud;
  final SyncOutbox _outbox;

  Future<CloudSyncSummary> pushPending({int maxRows = 100}) async {
    if (!CloudConfig.enabled) {
      return const CloudSyncSummary(pushed: 0, failed: 0, skippedNotConfigured: 1);
    }
    if (await _outbox.needsFullResync()) {
      // جهاز استُعيد له نسخة احتياطية محلية مؤخرًا — يجب سحب طازج من
      // Supabase أولًا قبل دفع أي شيء، تفاديًا للكتابة فوق بيانات
      // سحابية أحدث ببيانات محلية قديمة (انظر SyncOutbox.clearPendingAndRequireFullResync).
      return const CloudSyncSummary(pushed: 0, failed: 0, skippedNotConfigured: 0);
    }

    final rows = await _outbox.pending(limit: maxRows);
    var pushed = 0;
    var failed = 0;

    for (final entry in rows) {
      final id = entry['id'] as int;
      final table = entry['table_name'] as String;
      final localRowId = entry['local_row_id'] as int;
      final operation = entry['operation'] as String;

      try {
        if (operation == 'upsert') {
          final payloadJson = entry['payload_json'] as String?;
          final row = payloadJson == null
              ? <String, Object?>{}
              : Map<String, Object?>.from(jsonDecode(payloadJson) as Map);
          await _cloud.upsertRow(table: table, legacyId: localRowId, row: row);
          await _outbox.markSynced(id);
          pushed++;
        } else {
          // 'delete' غير مدعوم حاليًا لأي جدول سُجِّل في outbox (انظر
          // تعليقات SubscriptionRepository.deletePayment) — يُترك
          // السطر كما هو (لا يُعلَّم كمكتمل) حتى يُبنى مسار حذف
          // سحابي صريح ومقصود، بدل تجاهله بصمت وكأنه نجح.
          await _outbox.markFailed(id, 'عملية "$operation" غير مدعومة بعد في محرك المزامنة.');
          failed++;
        }
      } catch (e) {
        await _outbox.markFailed(id, e.toString());
        failed++;
      }
    }

    return CloudSyncSummary(pushed: pushed, failed: failed, skippedNotConfigured: 0);
  }
}
