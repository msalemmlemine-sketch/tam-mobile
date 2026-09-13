import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/database/app_database.dart';

class BackupResult {
  final bool success;
  final String? filePath;
  final String? error;
  const BackupResult({required this.success, this.filePath, this.error});
}

/// نسخ احتياطي/استعادة حقيقيان لملف قاعدة بيانات SQLite — بدون أي
/// اعتماد على الإنترنت أو خدمة سحابية. الملف الناتج قابل لإرساله عبر
/// أي تطبيق آخر (واتساب/تيليجرام/بلوتوث) يدويًا من قبل المستخدم.
class BackupService {
  static const _sqliteMagic = 'SQLite format 3\u0000';

  /// ينشئ نسخة من ملف قاعدة البيانات الحالي في مجلد مؤقت قابل
  /// للمشاركة، باسم يحمل تاريخ ووقت اليوم (للسماح بأكثر من نسخة
  /// في نفس اليوم دون أن تُطابق إحداهما الأخرى بالاسم).
  Future<BackupResult> createBackup() async {
    try {
      final dbFile = await AppDatabase.instance.fileHandle();
      if (!await dbFile.exists()) {
        return const BackupResult(success: false, error: 'قاعدة البيانات غير موجودة بعد');
      }

      final tempDir = await getTemporaryDirectory();
      final backupName = 'TAM_backup_${_timestamp()}.db';
      final backupPath = p.join(tempDir.path, backupName);

      // نسخ آمن: كتابة نسخة مطابقة بالبايت من ملف قاعدة البيانات الحالي.
      await dbFile.copy(backupPath);

      return BackupResult(success: true, filePath: backupPath);
    } catch (e) {
      return BackupResult(success: false, error: e.toString());
    }
  }

  /// طابع زمني دقيق للثانية (وليس لليوم فقط) — يمنع تصادم أسماء
  /// الملفات عند إنشاء أكثر من نسخة في نفس اليوم، وهو ضروري خصوصًا
  /// لأن [restoreBackup] ينشئ نسخة أمان داخلية قد تحدث في نفس
  /// اللحظة تقريبًا من نسخة يدوية سابقة.
  String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  /// يتحقق من أن الملف المختار فعلًا قاعدة بيانات SQLite صالحة عبر
  /// فحص التوقيع (Magic Bytes) في أول 16 بايت من الملف — قبل أي
  /// محاولة استعادة، لمنع استبدال البيانات الحالية بملف تالف.
  Future<bool> isValidSqliteFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final raf = await file.open();
      final header = await raf.read(16);
      await raf.close();
      final headerStr = String.fromCharCodes(Uint8List.fromList(header));
      return headerStr == _sqliteMagic;
    } catch (_) {
      return false;
    }
  }

  Future<int> fileSizeBytes(String path) async {
    final file = File(path);
    if (!await file.exists()) return 0;
    return file.length();
  }

  /// نسخة أمان داخلية قبل الاستعادة — بادئة اسم مختلفة تمامًا عن
  /// [createBackup] (التي يستخدمها المستخدم يدويًا) حتى يستحيل أن
  /// يتطابق مسارها مع الملف المصدر الذي يجري استعادته، مهما كان
  /// توقيت الاستدعاءين متقاربًا.
  Future<BackupResult> _createInternalSafetyCopy() async {
    try {
      final dbFile = await AppDatabase.instance.fileHandle();
      if (!await dbFile.exists()) {
        return const BackupResult(success: false, error: 'قاعدة البيانات غير موجودة بعد');
      }
      final tempDir = await getTemporaryDirectory();
      final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
      final backupPath =
          p.join(tempDir.path, 'TAM_prerestore_${_timestamp()}_$uniqueSuffix.db');
      await dbFile.copy(backupPath);
      return BackupResult(success: true, filePath: backupPath);
    } catch (e) {
      return BackupResult(success: false, error: e.toString());
    }
  }

  /// يستعيد نسخة احتياطية: يأخذ أولًا نسخة أمان من القاعدة الحالية
  /// (pre-restore backup)، يغلق الاتصال الحالي، يستبدل الملف، ثم
  /// يعيد فتح الاتصال. لا يحذف أي شيء قبل التأكد من نجاح كل خطوة.
  Future<BackupResult> restoreBackup(String sourcePath) async {
    try {
      final isValid = await isValidSqliteFile(sourcePath);
      if (!isValid) {
        return const BackupResult(
            success: false, error: 'الملف المختار ليس نسخة قاعدة بيانات صالحة');
      }

      // نسخة أمان تلقائية قبل الاستبدال — لا تُفقد البيانات الحالية
      // حتى لو فشلت عملية الاستعادة لاحقًا. باسم مختلف تمامًا عن
      // نسخ المستخدم اليدوية حتى لا يتصادم مساره مع sourcePath أبدًا
      // (كانا يتشاركان نفس اسم الملف عند إنشاء نسخة يدوية ثم
      // استعادتها في نفس اللحظة تقريبًا، مما كان يؤدي لاستبدال
      // الملف المصدر بنسخة الأمان قبل قراءته — تم إصلاح ذلك هنا).
      final preRestore = await _createInternalSafetyCopy();
      if (!preRestore.success) {
        return BackupResult(
            success: false,
            error: 'تعذّر إنشاء نسخة أمان قبل الاستعادة: ${preRestore.error}');
      }

      await AppDatabase.instance.close();

      final dbPath = await AppDatabase.instance.databaseFilePath();
      await File(sourcePath).copy(dbPath);

      await AppDatabase.instance.reopen();

      return BackupResult(success: true, filePath: dbPath);
    } catch (e) {
      // في حال أي خطأ، حاول إعادة فتح القاعدة الأصلية حتى لا يبقى
      // التطبيق بلا اتصال بقاعدة بيانات.
      await AppDatabase.instance.reopen();
      return BackupResult(success: false, error: e.toString());
    }
  }
}
