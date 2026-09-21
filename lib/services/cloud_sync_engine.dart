import 'dart:convert';

import 'cloud_config.dart';
import 'cloud_admin_service.dart';
import 'supabase_service.dart';
import '../core/database/app_database.dart';
import 'cloud_service.dart';
import 'sync_outbox.dart';

class CloudSyncSummary {
  final int pushed;
  final int pulled;
  final int failed;
  final List<String> errors;
  const CloudSyncSummary({
    required this.pushed,
    required this.pulled,
    required this.failed,
    this.errors = const [],
  });
}

class CloudSyncEngine {
  CloudSyncEngine({CloudService? cloud, SyncOutbox? outbox})
      : _cloud = cloud ?? CloudService(), _outbox = outbox ?? const SyncOutbox();
  final CloudService _cloud;
  final SyncOutbox _outbox;

  Future<CloudSyncSummary> sync({int maxRows = 100}) async {
    if (!CloudConfig.enabled) {
      return const CloudSyncSummary(pushed: 0, pulled: 0, failed: 0);
    }
    var failed = 0;
    var pushed = 0;
    var pulled = 0;
    final errors = <String>[];

    if (SupabaseService.session == null) {
      errors.add('لا توجد جلسة Supabase (المستخدم غير مسجّل الدخول سحابياً)');
    }

    // Pull first so الهاتف الجديد لا يدفع بيانات seed محلية فوق السحابة.
    try {
      await _cloud.pullAllToLocal();
      pulled = 1;
    } catch (e) {
      errors.add('فشل السحب: $e');
    }

    final rows = await _outbox.pending(limit: maxRows);
    for (final entry in rows) {
      final id = entry['id'] as int;
      final table = entry['table_name'] as String;
      final operation = entry['operation'] as String? ?? 'upsert';
      try {
        if (operation == 'delete') {
          final raw = entry['payload_json'] as String?;
          final syncUuid = raw == null
              ? null
              : (jsonDecode(raw) as Map)['sync_uuid'] as String?;
          if (syncUuid != null) {
            await _cloud.deleteRowBySyncUuid(table: table, syncUuid: syncUuid);
          }
          // لا sync_uuid محفوظ: لا شيء لحذفه سحابياً، نعتبرها منتهية.
        } else {
          final payload = Map<String, Object?>.from(
            jsonDecode(entry['payload_json'] as String? ?? '{}') as Map,
          );
          await _cloud.upsertRow(
            table: table,
            legacyId: entry['local_row_id'] as int,
            row: payload,
          );
        }
        await _outbox.markSynced(id);
        pushed++;
      } catch (e) {
        await _outbox.markFailed(id, e.toString());
        failed++;
        if (errors.length < 6) errors.add('رفع $table: $e');
      }
    }

    try {
      await _cloud.pullAllToLocal();
      pulled = 1;
    } catch (e) {
      final msg = 'فشل السحب الثاني: $e';
      if (!errors.contains(msg)) errors.add(msg);
    }
    try {
      await _provisionPendingMemberAccounts();
    } catch (e) {
      errors.add('فشل تجهيز حسابات المنتسبين: $e');
    }

    return CloudSyncSummary(
      pushed: pushed,
      pulled: pulled,
      failed: failed,
      errors: errors,
    );
  }

  Future<void> _provisionPendingMemberAccounts() async {
    if (!CloudConfig.enabled || SupabaseService.session == null) return;
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT u.id AS user_id, u.member_id, u.username, m.sync_uuid, m.name, m.phone
      FROM users u JOIN members m ON m.id=u.member_id
      WHERE u.role='member' AND (u.cloud_user_id IS NULL OR u.cloud_user_id='')
        AND TRIM(u.username)<>'' AND TRIM(COALESCE(m.phone,''))<>''
      LIMIT 25
    ''');
    const admin = CloudAdminService();
    for (final row in rows) {
      try {
        final cloudId = await admin.provisionMember(
          memberId: row['member_id'] as int,
          memberSyncUuid: row['sync_uuid'].toString(),
          displayName: row['name'].toString(),
          username: row['username'].toString(),
          temporaryPassword: row['phone'].toString(),
        );
        if (cloudId != null) {
          await db.update(
            'users',
            {'cloud_user_id': cloudId, 'is_active': 1, 'must_change_password': 1},
            where: 'id=?',
            whereArgs: [row['user_id']],
          );
        }
      } catch (_) {}
    }
  }

  Future<CloudSyncSummary> pushPending({int maxRows = 100}) => sync(maxRows: maxRows);
}
