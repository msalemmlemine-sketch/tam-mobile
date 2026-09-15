import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import 'drive_sync_config.dart';
import 'secure_kv_store.dart';

class DriveSyncResult {
  final bool success;
  final bool conflict;
  final int? revision;
  final String message;
  const DriveSyncResult({
    required this.success,
    this.conflict = false,
    this.revision,
    required this.message,
  });
}

/// مزامنة البيانات بين الأجهزة الثلاثة عبر Google Apps Script وملف JSON
/// واحد محفوظ في Google Drive الخاص بمالك السكربت.
///
/// البروتوكول متعمد أن يكون محافظًا: كل Push يحمل revision الذي سبق أن
/// سحبه الجهاز. إذا تغيّر الملف على جهاز آخر، يرفض الخادم الكتابة بدل
/// الكتابة فوق البيانات. عندها يجب Pull ثم إعادة المحاولة.
class DriveSyncService {
  DriveSyncService({SecureKvStore? store}) : _store = store ?? FlutterSecureKvStore();

  static const _deviceIdKey = 'tam_drive_sync_device_id';
  static const _revisionKey = 'tam_drive_sync_revision';
  static const _dirtyKey = 'tam_drive_sync_dirty';
  final SecureKvStore _store;

  Future<String> _deviceId() async {
    final existing = await _store.read(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final rnd = Random.secure();
    final id = 'tam-${DateTime.now().microsecondsSinceEpoch}-${List.generate(10, (_) => rnd.nextInt(16).toRadixString(16)).join()}';
    await _store.write(_deviceIdKey, id);
    return id;
  }

  Future<int> _revision() async => int.tryParse(await _store.read(_revisionKey) ?? '') ?? 0;
  Future<void> _setRevision(int revision) => _store.write(_revisionKey, '$revision');

  Future<void> markDirty() => _store.write(_dirtyKey, '1');
  Future<bool> isDirty() async => (await _store.read(_dirtyKey)) == '1';
  Future<void> _clearDirty() => _store.delete(_dirtyKey);

  Uri _uri({required String action}) {
    final base = Uri.parse(DriveSyncConfig.url);
    return base.replace(queryParameters: {
      ...base.queryParameters,
      'action': action,
      'key': DriveSyncConfig.apiKey,
    });
  }

  Future<DriveSyncResult> pull({bool force = false}) async {
    if (!DriveSyncConfig.enabled) {
      return const DriveSyncResult(success: false, message: 'مزامنة Google Drive غير مفعلة في إعدادات البناء.');
    }
    try {
      if (!force && await isDirty()) {
        return const DriveSyncResult(success: false, conflict: true, message: 'توجد تغييرات محلية غير مرفوعة. ارفعها أولًا، أو ارفض التغييرات المحلية يدويًا قبل السحب.');
      }
      final response = await http.get(_uri(action: 'pull')).timeout(const Duration(seconds: 30));
      final data = _decode(response);
      if (data['ok'] != true) {
        return DriveSyncResult(success: false, message: data['error']?.toString() ?? 'فشل السحب من Google Drive.');
      }
      final revision = (data['revision'] as num?)?.toInt() ?? 0;
      final state = Map<String, dynamic>.from(data['state'] as Map? ?? {});
      await _replaceBusinessData(state);
      await _setRevision(revision);
      await _clearDirty();
      return DriveSyncResult(success: true, revision: revision, message: 'تم سحب البيانات من Google Drive بنجاح.');
    } catch (e) {
      return DriveSyncResult(success: false, message: 'تعذر الاتصال بالمزامنة: $e');
    }
  }

  Future<DriveSyncResult> push() async {
    if (!DriveSyncConfig.enabled) {
      return const DriveSyncResult(success: false, message: 'مزامنة Google Drive غير مفعلة في إعدادات البناء.');
    }
    try {
      final baseRevision = await _revision();
      final snapshot = await _snapshot();
      final deviceId = await _deviceId();
      final response = await http.post(
        _uri(action: 'push'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'apiKey': DriveSyncConfig.apiKey,
          'deviceId': deviceId,
          'baseRevision': baseRevision,
          'state': snapshot,
        }),
      ).timeout(const Duration(seconds: 60));
      final data = _decode(response);
      if (data['ok'] != true) {
        final conflict = data['errorCode'] == 'REVISION_CONFLICT';
        return DriveSyncResult(
          success: false,
          conflict: conflict,
          revision: (data['revision'] as num?)?.toInt(),
          message: data['error']?.toString() ?? 'فشل رفع البيانات.',
        );
      }
      final revision = (data['revision'] as num?)?.toInt() ?? baseRevision + 1;
      await _setRevision(revision);
      await _clearDirty();
      return DriveSyncResult(success: true, revision: revision, message: 'تم رفع البيانات إلى Google Drive بنجاح.');
    } catch (e) {
      return DriveSyncResult(success: false, message: 'تعذر رفع البيانات: $e');
    }
  }

  Future<DriveSyncResult> sync() async {
    // إذا كانت هناك تغييرات محلية، ارفعها أولًا. إذا كانت نسخة Drive
    // أحدث سيرفض الخادم العملية ولن تُمحى التغييرات المحلية.
    if (await isDirty()) return push();
    return pull();
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = utf8.decode(response.bodyBytes);
    final parsed = jsonDecode(body);
    if (parsed is! Map) throw FormatException('استجابة غير صالحة من Apps Script');
    return Map<String, dynamic>.from(parsed);
  }

  static const _tables = <String>[
    'settings',
    'districts',
    'institutions',
    'members',
    'subscription_settings',
    'subscription_payments',
    'subscription_dues',
    'membership_card_payments',
    'subscription_name_aliases',
    'subscription_import_batches',
    'regional_expenses',
    'fund_opening_overrides',
  ];

  Future<Map<String, dynamic>> _snapshot() async {
    final db = await AppDatabase.instance.database;
    final result = <String, dynamic>{
      'schema': 1,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    for (final table in _tables) {
      final rows = table == 'settings'
          ? await db.query('settings', where: 'setting_key IN (?, ?)', whereArgs: ['org_name', 'org_short'])
          : await db.query(table);
      result[table] = rows.map((row) => Map<String, dynamic>.from(row)).toList();
    }
    return result;
  }

  Future<void> _replaceBusinessData(Map<String, dynamic> state) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      // أبناء أولًا بسبب مفاتيح SQLite الخارجية.
      for (final table in [
        'subscription_name_aliases',
        'membership_card_payments',
        'subscription_dues',
        'subscription_payments',
        'subscription_import_batches',
        'regional_expenses',
        'members',
        'institutions',
        'districts',
        'fund_opening_overrides',
        'subscription_settings',
        'settings',
      ]) {
        if (table == 'settings') {
          batch.delete(table, where: 'setting_key IN (?, ?)', whereArgs: ['org_name', 'org_short']);
        } else {
          batch.delete(table);
        }
      }
      // الآباء أولًا عند الإدخال.
      for (final table in [
        'settings',
        'subscription_settings',
        'fund_opening_overrides',
        'districts',
        'institutions',
        'members',
        'subscription_import_batches',
        'subscription_payments',
        'subscription_dues',
        'membership_card_payments',
        'subscription_name_aliases',
        'regional_expenses',
      ]) {
        final rawRows = state[table];
        if (rawRows is! List) continue;
        for (final raw in rawRows) {
          if (raw is Map) batch.insert(table, Map<String, Object?>.from(raw));
        }
      }
      await batch.commit(noResult: true);
    });
  }
}
