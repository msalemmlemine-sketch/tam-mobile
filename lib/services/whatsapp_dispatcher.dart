import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import 'whatsapp_service.dart';

/// نتيجة تشغيل واحد لصف انتظار رسائل واتساب.
class WhatsAppDispatchSummary {
  final int sent;
  final int failed;
  final int skippedQuotaExceeded;
  final int remainingPending;

  const WhatsAppDispatchSummary({
    required this.sent,
    required this.failed,
    required this.skippedQuotaExceeded,
    required this.remainingPending,
  });

  @override
  String toString() =>
      'تم الإرسال: $sent، فشل: $failed، مؤجَّل (تجاوز الحد اليومي): $skippedQuotaExceeded، متبقٍ بالطابور: $remainingPending';
}

/// مُرسِل صف انتظار رسائل واتساب (whatsapp_messages) بأمان.
///
/// المشكلة الأصلية: أي حلقة تُرسل رسائل واتساب فورًا وبتتابع مباشر
/// (دون فاصل زمني) تُشبه سلوك روبوتات الرسائل الجماعية في نظر رصد
/// Meta الآلي لواتساب، مما قد يؤدي لحظر رقم واتساب النقابة كليًا.
///
/// الحل المطبَّق هنا:
/// 1) تأخير عشوائي (Jitter) بين 4 و9 ثوانٍ قبل كل رسالة (ما عدا أول
///    رسالة في كل تشغيل، لتفادي انتظار بلا داعٍ إذا كانت القائمة
///    قصيرة)، بدل إرسال متتابع فوري.
/// 2) تسجيل كل نجاح/فشل على حدة في نفس صف whatsapp_messages دون كسر
///    الحلقة — فشل رسالة واحدة (رقم غير صالح، انقطاع اتصال، ...) لا
///    يوقف إرسال بقية المنتسبين.
/// 3) حد يومي أقصى لعدد الرسائل المُرسلة (لكل الجلسات مجتمعة في نفس
///    اليوم، وليس فقط الجلسة الحالية) يُخزَّن في جدول settings العام،
///    فوق الحد الأقصى للتشغيل الواحد (maxPerRun) — أيهما أقرب.
class WhatsAppDispatcher {
  WhatsAppDispatcher({WhatsAppService? service, Random? random})
      : _service = service ?? WhatsAppService(),
        _random = random ?? Random.secure();

  final WhatsAppService _service;
  final Random _random;

  static const int defaultDailyLimit = 200;
  static const _dailyLimitSettingKey = 'whatsapp_daily_limit';
  static const _dailyCountPrefix = 'whatsapp_sent_count_'; // + yyyy-mm-dd
  static const String defaultTemplateName = 'overdue_subscription_reminder';
  static const String defaultLanguageCode = 'ar';

  Future<Database> get _db => AppDatabase.instance.database;

  String _todayKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$_dailyCountPrefix$y-$m-$d';
  }

  Future<int> _dailyLimit(Database db) async {
    final rows = await db.query('settings',
        where: 'setting_key = ?', whereArgs: [_dailyLimitSettingKey], limit: 1);
    if (rows.isEmpty) return defaultDailyLimit;
    return int.tryParse(rows.first['setting_value'] as String? ?? '') ??
        defaultDailyLimit;
  }

  Future<int> _sentToday(Database db) async {
    final rows = await db.query('settings',
        where: 'setting_key = ?', whereArgs: [_todayKey()], limit: 1);
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['setting_value'] as String? ?? '0') ?? 0;
  }

  Future<void> _incrementSentToday(Database db, int by) async {
    final key = _todayKey();
    final current = await _sentToday(db);
    await db.insert(
      'settings',
      {'setting_key': key, 'setting_value': '${current + by}'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Duration> _jitterDelay() async {
    // تأخير عشوائي صحيح بين 4000 و9000 ميلي ثانية (4 إلى 9 ثوانٍ).
    final ms = 4000 + _random.nextInt(5001);
    return Duration(milliseconds: ms);
  }

  /// يُرسل ما أمكن من الرسائل "المعلَّقة" (status='pending') في صف
  /// الانتظار، حتى حد [maxPerRun] لهذا التشغيل، وحتى الحد اليومي
  /// العام المخزَّن في الإعدادات (أيهما أقل)، مع فاصل عشوائي بين كل
  /// رسالة وأخرى. آمن للاستدعاء المتكرر — لا يعيد إرسال رسالة
  /// أُرسلت أو فشلت سابقًا إلا إذا أُعيد ضبط حالتها يدويًا.
  Future<WhatsAppDispatchSummary> dispatchPending({int maxPerRun = 40}) async {
    final db = await _db;

    if (!await _service.enabled) {
      return const WhatsAppDispatchSummary(
          sent: 0, failed: 0, skippedQuotaExceeded: 0, remainingPending: 0);
    }

    final dailyLimit = await _dailyLimit(db);
    var sentToday = await _sentToday(db);

    final pending = await db.query(
      'whatsapp_messages',
      where: "status = 'pending'",
      orderBy: 'scheduled_at ASC',
      limit: maxPerRun,
    );

    var sent = 0;
    var failed = 0;
    var skippedQuota = 0;
    var isFirst = true;

    for (final row in pending) {
      if (sentToday >= dailyLimit) {
        skippedQuota++;
        continue;
      }

      if (!isFirst) {
        await Future.delayed(await _jitterDelay());
      }
      isFirst = false;

      final id = row['id'] as int;
      final memberId = row['member_id'] as int?;
      final phone = row['phone'] as String?;
      final debtAmount = (row['debt_amount'] as num?) ?? 0;
      final monthsDue = (row['months_due'] as String?) ?? '';

      if (memberId == null || phone == null || phone.trim().isEmpty) {
        await _markFailed(db, id, 'رقم هاتف غير صالح أو منتسب غير معروف.');
        failed++;
        continue;
      }

      try {
        final response = await _service.sendTemplate(
          memberId: memberId,
          phone: phone,
          templateName: defaultTemplateName,
          languageCode: defaultLanguageCode,
          parameters: [debtAmount.toString(), monthsDue],
        );
        await _markSent(db, id, response['messageId']?.toString());
        sent++;
        sentToday++;
        await _incrementSentToday(db, 1);
      } catch (e) {
        // لا نكسر الحلقة — نُسجّل الفشل وننتقل للمنتسب التالي.
        await _markFailed(db, id, e.toString());
        failed++;
      }
    }

    final remaining = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) AS c FROM whatsapp_messages WHERE status = 'pending'",
        )) ??
        0;

    return WhatsAppDispatchSummary(
      sent: sent,
      failed: failed,
      skippedQuotaExceeded: skippedQuota,
      remainingPending: remaining,
    );
  }

  Future<void> _markSent(Database db, int id, String? providerMessageId) {
    return db.update(
      'whatsapp_messages',
      {
        'status': 'sent',
        'sent_at': DateTime.now().toIso8601String(),
        'provider_message_id': providerMessageId,
        'error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _markFailed(Database db, int id, String error) {
    return db.update(
      'whatsapp_messages',
      {'status': 'failed', 'error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
