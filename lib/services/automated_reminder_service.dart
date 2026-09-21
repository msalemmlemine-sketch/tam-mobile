import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/app_role.dart';
import '../services/permission_service.dart';
import 'report_service.dart';

/// نظام التذكير الآلي بالمتأخرات.
///
/// - يحدد يومي 24 و26 من كل شهر كموعدين للتذكير.
/// - عند فتح التطبيق في أحد هذين اليومين، يحسب المتأخرات الفعلية ويصدر
///   إشعارًا يتضمن العدد والإجمالي.
/// - كما يبرمج إشعارين شهريين محليين حتى يظهر التذكير حتى إذا كان التطبيق
///   مغلقًا. لأن إشعار Android المجدول لا يستطيع في هذه البنية قراءة SQLite
///   لحظة الإشعار، فإن النص المجدول عام، بينما يتم تخصيص العدد والمبلغ عند
///   فتح التطبيق في يوم التذكير.
///
/// هذا تذكير داخلي على أجهزة الإدارة، وليس إرسال رسائل خارجية للمنتسبين.
/// إرسال رسائل خارجية للمنتسبين يحتاج قناة إرسال منفصلة ومصرحًا بها.
class AutomatedReminderService {
  AutomatedReminderService._();

  static final AutomatedReminderService instance = AutomatedReminderService._();

  static const int _notification24Id = 24024;
  static const int _notification26Id = 26026;
  static const int _immediateNotificationId = 2624;
  static const String _channelId = 'tam_overdue_reminders';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    // التطبيق مخصص لموريتانيا؛ نستخدم المنطقة المحلية الرسمية للمواعيد.
    tz.setLocalLocation(tz.getLocation('Africa/Nouakchott'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _notifications.initialize(settings);

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    const channel = AndroidNotificationChannel(
      _channelId,
      'تذكيرات المتأخرات',
      description: 'تذكيرات يومي 24 و26 للمنتسبين المتأخرين عن الدفع',
      importance: Importance.high,
    );
    await androidPlugin?.createNotificationChannel(channel);

    await _scheduleMonthlyReminder(_notification24Id, 24);
    await _scheduleMonthlyReminder(_notification26Id, 26);

    _initialized = true;
  }

  Future<void> _scheduleMonthlyReminder(int id, int day) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      day,
      9,
      0,
    );

    if (!scheduled.isAfter(now)) {
      final nextMonth = now.month == 12
          ? DateTime(now.year + 1, 1, 1)
          : DateTime(now.year, now.month + 1, 1);
      scheduled = tz.TZDateTime(
        tz.local,
        nextMonth.year,
        nextMonth.month,
        day,
        9,
        0,
      );
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'تذكيرات المتأخرات',
        channelDescription: 'تذكيرات يومي 24 و26 للمتأخرين عن الدفع',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _notifications.zonedSchedule(
      id,
      'تذكير المتأخرين عن الدفع',
      'اليوم موعد التذكير. افتح تطبيق TAM لمراجعة قائمة المتأخرين عن الدفع.',
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime,
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      payload: jsonEncode({'type': 'overdue_reminder', 'day': day}),
    );
  }

  /// في اليوم 24 أو 26 من كل شهر: يُحسب المتأخرون فعليًا، وتُرسل
  /// إشعار محلي مفصّل للإدارة على الجهاز فقط. لا يوجد أي إرسال خارجي
  /// (واتساب أو غيره) للمنتسبين من هذا التطبيق.
  Future<void> checkAndSendAutomatedReminders(
    List<MemberDebtRow> overdueMembers,
  ) async {
    if (!_isReminderDay()) return;
    if (!_canReceiveManagementReminder()) return;

    final total = overdueMembers.fold<double>(
      0,
      (sum, row) => sum + row.remaining,
    );

    await _showManagementReminder(
      count: overdueMembers.length,
      totalRemaining: total,
    );
  }

  bool _isReminderDay() {
    final day = DateTime.now().day;
    return day == 24 || day == 26;
  }

  bool _canReceiveManagementReminder() {
    final role = PermissionService.role;
    return role == AppRole.organizationSecretary ||
        role == AppRole.financeSecretary;
  }

  Future<void> _showManagementReminder({
    required int count,
    required double totalRemaining,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'تذكيرات المتأخرات',
        channelDescription: 'تذكيرات يومي 24 و26 للمتأخرين عن الدفع',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''),
      ),
    );

    final day = DateTime.now().day;
    final body = count == 0
        ? 'لا توجد متأخرات عن الدفع اليوم.'
        : 'يوجد $count منتسبًا متأخرًا عن الدفع، بإجمالي متبقٍ ${totalRemaining.toStringAsFixed(0)} أوقية.';

    await _notifications.show(
      _immediateNotificationId,
      'تذكير المتأخرين — يوم $day',
      body,
      details,
      payload: jsonEncode({'type': 'overdue_report'}),
    );
  }

  /// للاختبار اليدوي من داخل التطبيق.
  Future<void> sendAutomatedBatches(List<MemberDebtRow> overdueMembers) async {
    await checkAndSendAutomatedReminders(overdueMembers);
  }

  Future<void> cancelScheduledReminders() async {
    await _notifications.cancel(_notification24Id);
    await _notifications.cancel(_notification26Id);
  }

  @visibleForTesting
  bool isReminderDay(DateTime date) => date.day == 24 || date.day == 26;
}
