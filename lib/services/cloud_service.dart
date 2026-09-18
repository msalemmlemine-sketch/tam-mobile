import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/database/app_database.dart';
import 'cloud_config.dart';
import 'supabase_service.dart';

/// طبقة البيانات المشتركة: Supabase هو مصدر الحقيقة، وSQLite نسخة محلية.
/// الهوية المشتركة للصفوف هي sync_uuid، وليس id المحلي؛ وهذا يمنع تصادم
/// أرقام SQLite عندما ينشئ هاتفان سجلات جديدة في الوقت نفسه.
class CloudService {
  CloudService({SupabaseClient? client}) : _client = client ?? SupabaseService.client;
  final SupabaseClient _client;

  static bool get enabled => CloudConfig.enabled;
  static Future<void> initialize() => SupabaseService.initialize();

  static const _foreignKeys = {
    'institutions': {'district_id': 'districts'},
    'members': {'district_id': 'districts', 'institution_id': 'institutions'},
    'subscription_payments': {'member_id': 'members'},
  };

  Future<String?> _localSyncUuid(String table, int localId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(table,
        columns: ['sync_uuid'], where: 'id = ?', whereArgs: [localId], limit: 1);
    return rows.isEmpty ? null : rows.first['sync_uuid'] as String?;
  }

  Future<String?> _remoteIdBySyncUuid(String table, String syncUuid) async {
    final row = await _client.from(table).select('id').eq('sync_uuid', syncUuid).maybeSingle();
    return row?['id'] as String?;
  }

  Future<void> upsertRow({
    required String table,
    required int legacyId,
    required Map<String, Object?> row,
  }) async {
    if (!enabled) throw StateError('Supabase غير مهيأ.');
    final payload = Map<String, Object?>.from(row);
    payload.remove('id');
    if (payload['sync_uuid'] == null) {
      final uuid = await _localSyncUuid(table, legacyId);
      if (uuid == null) throw StateError('السجل $table#$legacyId بلا sync_uuid.');
      payload['sync_uuid'] = uuid;
    }

    final fkMap = _foreignKeys[table];
    if (fkMap != null) {
      for (final entry in fkMap.entries) {
        final localValue = payload[entry.key];
        if (localValue == null) continue;
        final localParentId = localValue is int ? localValue : int.tryParse('$localValue');
        if (localParentId == null) throw StateError('معرف مرجعي غير صالح: ${entry.key}');
        final parentSync = await _localSyncUuid(entry.value, localParentId);
        if (parentSync == null) throw StateError('السجل المرجعي ${entry.value}#$localParentId غير معروف.');
        final remoteId = await _remoteIdBySyncUuid(entry.value, parentSync);
        if (remoteId == null) throw StateError('السجل المرجعي ${entry.value} لم يصل إلى Supabase بعد.');
        payload[entry.key] = remoteId;
      }
    }

    await _client.from(table).upsert(payload, onConflict: 'sync_uuid');
  }

  Future<List<Map<String, dynamic>>> fetchAll(String table) async {
    final rows = await _client.from(table).select('*');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> pullAllToLocal() async {
    if (!enabled) return;
    final db = await AppDatabase.instance.database;
    final districts = await fetchAll('districts');
    final institutions = await fetchAll('institutions');
    final members = await fetchAll('members');
    final payments = await fetchAll('subscription_payments');

    final districtMap = <String, int>{};
    for (final r in districts) {
      final sync = r['sync_uuid'] as String?;
      if (sync == null) continue;
      int? localId;
      final bySync = await db.query('districts', where: 'sync_uuid = ?', whereArgs: [sync], limit: 1);
      if (bySync.isNotEmpty) localId = bySync.first['id'] as int;
      if (localId == null) {
        final byName = await db.query('districts', where: 'name = ?', whereArgs: [r['name']], limit: 1);
        if (byName.isNotEmpty) localId = byName.first['id'] as int;
      }
      final values = {'sync_uuid': sync, 'name': r['name'], 'sort_order': r['sort_order'] ?? 0, 'created_at': r['created_at'] ?? DateTime.now().toIso8601String()};
      if (localId == null) localId = await db.insert('districts', values);
      else await db.update('districts', values, where: 'id = ?', whereArgs: [localId]);
      districtMap[r['id'] as String] = localId;
    }

    final institutionMap = <String, int>{};
    for (final r in institutions) {
      final sync = r['sync_uuid'] as String?;
      final districtId = districtMap[r['district_id'] as String?];
      if (sync == null || districtId == null) continue;
      int? localId;
      final bySync = await db.query('institutions', where: 'sync_uuid = ?', whereArgs: [sync], limit: 1);
      if (bySync.isNotEmpty) localId = bySync.first['id'] as int;
      if (localId == null) {
        final byName = await db.query('institutions', where: 'district_id = ? AND name = ?', whereArgs: [districtId, r['name']], limit: 1);
        if (byName.isNotEmpty) localId = byName.first['id'] as int;
      }
      final values = {
        'sync_uuid': sync, 'district_id': districtId, 'name': r['name'],
        'total_staff': r['total_staff'] ?? 0, 'sipes_members': r['sipes_members'] ?? 0,
        'snes_members': r['snes_members'] ?? 0, 'other_union_members': r['other_union_members'] ?? 0,
        'non_union_staff': r['non_union_staff'] ?? 0, 'created_at': r['created_at'] ?? DateTime.now().toIso8601String(),
      };
      if (localId == null) localId = await db.insert('institutions', values);
      else await db.update('institutions', values, where: 'id = ?', whereArgs: [localId]);
      institutionMap[r['id'] as String] = localId;
    }

    final memberMap = <String, int>{};
    for (final r in members) {
      final sync = r['sync_uuid'] as String?;
      final districtId = districtMap[r['district_id'] as String?];
      final institutionId = institutionMap[r['institution_id'] as String?];
      if (sync == null || districtId == null || institutionId == null) continue;
      final bySync = await db.query('members', where: 'sync_uuid = ?', whereArgs: [sync], limit: 1);
      int? localId = bySync.isEmpty ? null : bySync.first['id'] as int;
      final values = {
        'sync_uuid': sync, 'district_id': districtId, 'institution_id': institutionId,
        'name': r['name'], 'guide': r['guide'], 'card_no': r['card_no'], 'phone': r['phone'],
        'notes': r['notes'], 'membership_status': r['membership_status'] ?? 'active',
        'status_date': r['status_date'], 'is_archived': r['is_archived'] == true ? 1 : 0,
        'created_at': r['created_at'] ?? DateTime.now().toIso8601String(),
        'updated_at': r['updated_at'] ?? r['created_at'] ?? DateTime.now().toIso8601String(),
      };
      if (localId == null) localId = await db.insert('members', values);
      else await db.update('members', values, where: 'id = ?', whereArgs: [localId]);
      memberMap[r['id'] as String] = localId;
    }

    for (final r in payments) {
      final sync = r['sync_uuid'] as String?;
      if (sync == null) continue;
      final bySync = await db.query('subscription_payments', where: 'sync_uuid = ?', whereArgs: [sync], limit: 1);
      int? localId = bySync.isEmpty ? null : bySync.first['id'] as int;
      final memberId = memberMap[r['member_id'] as String?];
      final values = {
        'sync_uuid': sync, 'member_id': memberId, 'member_name': r['member_name'],
        'financial_guide': r['financial_guide'], 'card_no': r['card_no'],
        'payment_year': r['payment_year'], 'payment_month': r['payment_month'],
        'payment_date': r['payment_date'], 'subscription_amount': (r['subscription_amount'] as num?)?.toDouble() ?? 0,
        'card_fee': (r['card_fee'] as num?)?.toDouble() ?? 0, 'total_amount': (r['total_amount'] as num?)?.toDouble() ?? 0,
        'source': r['source'], 'source_name': r['source_name'], 'payment_method': r['payment_method'] ?? 'cash',
        'payment_reference': r['payment_reference'], 'matched_by': r['matched_by'],
        'direct_to_executive': r['direct_to_executive'] == true ? 1 : 0,
        'import_batch_id': r['import_batch_id'], 'row_hash': r['row_hash'], 'notes': r['notes'],
        'created_at': r['created_at'] ?? DateTime.now().toIso8601String(),
        'updated_at': r['updated_at'] ?? r['created_at'] ?? DateTime.now().toIso8601String(),
      };
      if (localId == null) await db.insert('subscription_payments', values);
      else await db.update('subscription_payments', values, where: 'id = ?', whereArgs: [localId]);
    }
  }
}
