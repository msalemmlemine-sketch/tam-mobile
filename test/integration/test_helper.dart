import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tam_mobile/core/database/app_database.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

/// يهيّئ قاعدة بيانات SQLite حقيقية (عبر sqflite_common_ffi، تنفيذ
/// أصلي بلغة C لنفس محرك SQLite المستخدم على أندرويد) في ملف مؤقت
/// جديد لكل اختبار — لا mocks ولا محاكاة لطبقة البيانات نفسها، بل
/// نفس طبقة AppDatabase/Repositories الحقيقية المستخدمة في التطبيق،
/// تمامًا كما طُلب ("إجراء التكامل مع قاعدة البيانات").
///
/// السطر الوحيد المُحاكى هو قناة منصّة path_provider (تحتاج جهازًا
/// حقيقيًا وغير متاحة في `flutter test`) — نُعيد بدلًا عنها مسار
/// المجلد المؤقت الذي أنشأناه لهذا الاختبار نفسه، حتى تعمل
/// BackupService (التي تستدعي getTemporaryDirectory مباشرة) بدون
/// تعديل أي كود إنتاجي فقط من أجل الاختبار.
Future<Directory> openFreshTestDatabase() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final tempDir = await Directory.systemTemp.createTemp('tam_test_');
  final dbPath = '${tempDir.path}/tam_test.db';

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
    switch (call.method) {
      case 'getTemporaryDirectory':
      case 'getApplicationDocumentsDirectory':
      case 'getApplicationSupportDirectory':
        return tempDir.path;
      default:
        return null;
    }
  });

  // إغلاق أي اتصال سابق مفتوح من اختبار قبله (AppDatabase singleton).
  await AppDatabase.instance.close();
  AppDatabase.testDbPathOverride = dbPath;

  // يفتح قاعدة جديدة فارغة وينفّذ onCreate/seed الحقيقيَّين.
  await AppDatabase.instance.database;

  return tempDir;
}

Future<void> closeTestDatabase(Directory tempDir) async {
  await AppDatabase.instance.close();
  AppDatabase.testDbPathOverride = null;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, null);
  if (await tempDir.exists()) {
    await tempDir.delete(recursive: true);
  }
}
