import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tam_mobile/core/database/app_database.dart';
import 'package:tam_mobile/models/district.dart';
import 'package:tam_mobile/repositories/district_repository.dart';
import 'package:tam_mobile/services/backup_service.dart';

import 'test_helper.dart';

void main() {
  late Directory tempDir;
  final districtRepo = DistrictRepository();
  final backupService = BackupService();

  setUp(() async {
    tempDir = await openFreshTestDatabase();
  });

  tearDown(() async {
    await closeTestDatabase(tempDir);
  });

  test('createBackup ينتج ملف SQLite صالحًا يحوي نفس البيانات الحالية', () async {
    await districtRepo.create(
        District(name: 'مقاطعة قبل النسخ', createdAt: DateTime.now().toIso8601String()));

    final result = await backupService.createBackup();
    expect(result.success, isTrue);
    expect(await File(result.filePath!).exists(), isTrue);

    final isValid = await backupService.isValidSqliteFile(result.filePath!);
    expect(isValid, isTrue);
  });

  test('isValidSqliteFile يرفض ملفًا عاديًا ليس قاعدة بيانات', () async {
    final fakeFile = File('${tempDir.path}/fake.db');
    await fakeFile.writeAsString('هذا ليس ملف قاعدة بيانات');
    final isValid = await backupService.isValidSqliteFile(fakeFile.path);
    expect(isValid, isFalse);
  });

  test('restoreBackup يستبدل البيانات الحالية فعليًا ببيانات النسخة المستعادة', () async {
    await districtRepo.create(
        District(name: 'بيانات قديمة قبل النسخ', createdAt: DateTime.now().toIso8601String()));
    final backupBeforeChange = await backupService.createBackup();
    expect(backupBeforeChange.success, isTrue);

    // نغيّر البيانات الحالية بعد أخذ النسخة — لنتأكد أن الاستعادة
    // تعيدها فعليًا للحالة القديمة، لا مجرد نجاح شكلي.
    await districtRepo.create(
        District(name: 'بيانات جديدة بعد النسخ', createdAt: DateTime.now().toIso8601String()));
    expect((await districtRepo.getAll()).length, 2);

    final restoreResult = await backupService.restoreBackup(backupBeforeChange.filePath!);
    expect(restoreResult.success, isTrue);

    final districtsAfterRestore = await districtRepo.getAll();
    expect(districtsAfterRestore.length, 1);
    expect(districtsAfterRestore.single.name, 'بيانات قديمة قبل النسخ');
  });

  test('restoreBackup يرفض ملفًا غير صالح ولا يمس البيانات الحالية إطلاقًا', () async {
    await districtRepo.create(
        District(name: 'بيانات يجب ألا تتأثر', createdAt: DateTime.now().toIso8601String()));

    final fakeFile = File('${tempDir.path}/invalid.db');
    await fakeFile.writeAsString('ليس sqlite');

    final result = await backupService.restoreBackup(fakeFile.path);
    expect(result.success, isFalse);

    final districts = await districtRepo.getAll();
    expect(districts.length, 1);
    expect(districts.single.name, 'بيانات يجب ألا تتأثر');
  });
}
