import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_config.dart';

/// عميل REST خفيف لـ Supabase (PostgREST) — بدون إضافة حزمة
/// supabase_flutter كاملة (تفاديًا لمخاطر تعارض إصدارات لم تُختبر في
/// هذه البيئة بلا Flutter SDK)؛ نستخدم فقط حزمة http الموجودة أصلًا
/// في المشروع، عبر واجهة PostgREST القياسية التي يعرضها كل مشروع
/// Supabase تلقائيًا على `${SUPABASE_URL}/rest/v1/<table>`.
///
/// **Supabase هو مصدر الحقيقة الوحيد** للبيانات المشتركة بين الهواتف
/// الثلاثة (قرار معماري صريح — انظر PROFESSIONAL_UPGRADE/CLOUD_SETUP).
/// دور Google Drive تحوَّل إلى أرشيف تقارير فقط (انظر drive_sync_service.dart)،
/// ولم يعد قناة مزامنة حية للبيانات الحيّة كي لا يتكرر تعارض
/// "من يملك الحقيقة؟" (Split-Brain) الذي كان موجودًا سابقًا.
///
/// الربط بين المعرّف المحلي (INTEGER AUTOINCREMENT في SQLite) والمعرّف
/// السحابي (uuid في Supabase) يتم عبر عمود إضافي `legacy_id` أُضيف لكل
/// جدول مشترك في supabase/001_tam_schema_and_rls.sql، مع قيد UNIQUE
/// عليه — هذا يسمح بعمل upsert مباشر بمفتاح ثابت (`on_conflict=legacy_id`)
/// دون الحاجة لجدول ترجمة معرّفات منفصل على الجهاز.
class CloudService {
  CloudService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static bool get enabled => CloudConfig.enabled;

  Uri _restUri(String table, {Map<String, String>? query}) {
    final base = CloudConfig.url.endsWith('/')
        ? CloudConfig.url.substring(0, CloudConfig.url.length - 1)
        : CloudConfig.url;
    return Uri.parse('$base/rest/v1/$table').replace(queryParameters: query);
  }

  Map<String, String> _headers({String prefer = 'return=minimal'}) => {
        'apikey': CloudConfig.publishableKey,
        'Authorization': 'Bearer ${CloudConfig.publishableKey}',
        'Content-Type': 'application/json',
        'Prefer': prefer,
      };

  /// كل عمود مفتاح أجنبي محلي (INTEGER) يحتاج ترجمة إلى uuid سحابي
  /// عبر جدوله المرجعي قبل الإرسال — Supabase لا يعرف شيئًا عن
  /// أرقام SQLite المحلية إلا عبر عمود legacy_id في الجدول الهدف.
  static const Map<String, Map<String, String>> _foreignKeys = {
    'institutions': {'district_id': 'districts'},
    'members': {'district_id': 'districts', 'institution_id': 'institutions'},
    'subscription_payments': {'member_id': 'members'},
  };

  /// يجلب الـ uuid السحابي المقابل لسطر محلي عبر legacy_id، أو null
  /// إن لم يكن ذلك الجدول الأب قد وصل لـ Supabase بعد (عندها يبقى
  /// سطر outbox الحالي "فاشلًا مؤقتًا" ويُعاد المحاولة لاحقًا تلقائيًا
  /// — بترتيب outbox حسب created_at، الجداول الأب تُدفع عادة أولًا
  /// لأنها تُنشأ قبل استخدامها كمرجع في سجل تابع).
  Future<String?> _resolveLegacyId({
    required String remoteTable,
    required int legacyId,
  }) async {
    final response = await _client.get(
      _restUri(remoteTable, query: {
        'legacy_id': 'eq.$legacyId',
        'select': 'id',
        'limit': '1',
      }),
      headers: _headers(),
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode >= 300) return null;
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List || decoded.isEmpty) return null;
    return (decoded.first as Map)['id'] as String?;
  }

  /// يُدرج/يُحدِّث صفًا واحدًا (upsert) بمفتاح `legacy_id` الثابت —
  /// هذا يجعل إعادة إرسال نفس العملية (بعد فشل شبكي مثلاً) آمنة
  /// تمامًا (Idempotent) ولا تُنشئ صفوفًا مكررة أبدًا.
  Future<void> upsertRow({
    required String table,
    required int legacyId,
    required Map<String, Object?> row,
  }) async {
    if (!enabled) {
      throw StateError('Supabase غير مُهيَّأ (SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY فارغان).');
    }
    final payload = Map<String, Object?>.from(row)..['legacy_id'] = legacyId;
    // id المحلي INTEGER لا معنى له كمفتاح UUID سحابي — لا نرسله أبدًا.
    payload.remove('id');

    // ترجمة كل مفتاح أجنبي محلي (إن وُجد) إلى uuid سحابي قبل الإرسال.
    final fkMap = _foreignKeys[table];
    if (fkMap != null) {
      for (final entry in fkMap.entries) {
        final localFkValue = payload[entry.key];
        if (localFkValue == null) continue;
        final remoteUuid = await _resolveLegacyId(
          remoteTable: entry.value,
          legacyId: localFkValue is int ? localFkValue : int.parse(localFkValue.toString()),
        );
        if (remoteUuid == null) {
          throw StateError(
              'الجدول المرجعي "${entry.value}" لم يصل بعد إلى Supabase (legacy_id=$localFkValue) — سيُعاد المحاولة لاحقًا.');
        }
        payload[entry.key] = remoteUuid;
      }
    }

    final response = await _client
        .post(
          _restUri(table, query: {'on_conflict': 'legacy_id'}),
          headers: _headers(prefer: 'resolution=merge-duplicates,return=minimal'),
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode >= 300) {
      throw StateError('فشل رفع $table#$legacyId إلى Supabase: '
          '${response.statusCode} ${utf8.decode(response.bodyBytes)}');
    }
  }

  /// يجلب كل الصفوف التي تغيّرت بعد [since] (لمزامنة سحب اختيارية
  /// مستقبلًا — البنية جاهزة وإن لم تُستخدم بعد من كل الشاشات).
  Future<List<Map<String, dynamic>>> fetchUpdatedSince({
    required String table,
    required DateTime since,
  }) async {
    if (!enabled) return const [];
    final response = await _client.get(
      _restUri(table, query: {
        'updated_at': 'gt.${since.toUtc().toIso8601String()}',
        'select': '*',
      }),
      headers: _headers(),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode >= 300) {
      throw StateError('فشل سحب $table من Supabase: '
          '${response.statusCode} ${utf8.decode(response.bodyBytes)}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) return const [];
    return decoded.cast<Map<String, dynamic>>();
  }

  void close() => _client.close();
}
