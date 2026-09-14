import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../core/database/app_database.dart';

import '../core/database/app_database.dart';

/// تصدير التقارير كملفات CSV أو PDF قابلة للمشاركة/الطباعة، بدون
/// أي اتصال بالإنترنت.
///
/// خط PDF العربي (Amiri Regular/Bold) مضمَّن فعليًا في
/// `assets/fonts/arabic_regular.ttf` و`arabic_bold.ttf` — راجع
/// `assets/fonts/README.md` لمصدره ورخصته (SIL OFL 1.1). يُحمَّل
/// من الحزمة نفسها عبر `rootBundle`، لا من الإنترنت، فيبقى التصدير
/// يعمل بدون اتصال كما هو مطلوب.
class ExportService {
  Future<File> _writeTempFile(String fileName, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<pw.Font?> _tryLoadFont(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return pw.Font.ttf(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> exportCsv({
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final csv = const ListToCsvConverter().convert([headers, ...rows]);
    final bytes = [0xEF, 0xBB, 0xBF, ...csv.codeUnits];
    final file = await _writeTempFile(fileName, bytes);
    await Share.shareXFiles([XFile(file.path)], text: fileName);
  }

  Future<void> exportPdfTable({
    required String fileName,
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final doc = pw.Document();
    final regular = await _tryLoadFont('assets/fonts/arabic_regular.ttf');
    final bold = await _tryLoadFont('assets/fonts/arabic_bold.ttf');
    pw.ImageProvider? logo;
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query('settings', where: 'setting_key = ?', whereArgs: ['org_logo_path']);
      final path = rows.isEmpty ? null : rows.first['setting_value'] as String?;
      if (path != null && await File(path).exists()) {
        logo = pw.MemoryImage(await File(path).readAsBytes());
      }
    } catch (_) {}

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: regular != null
            ? pw.ThemeData.withFont(base: regular, bold: bold ?? regular)
            : null,
        build: (context) => [
          if (logo != null)
            pw.Center(child: pw.Image(logo!, width: 70, height: 70)),
          if (logo != null) pw.Center(child: pw.Image(logo!, width: 70, height: 70)),
          pw.Header(
            level: 0,
            child: pw.Text(title, style: const pw.TextStyle(fontSize: 18)),
          ),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: headers,
            data: rows,
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE0F2EF)),
            cellAlignment: pw.Alignment.centerRight,
            headerAlignment: pw.Alignment.centerRight,
            cellStyle: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final file = await _writeTempFile(fileName, bytes);
    await Share.shareXFiles([XFile(file.path)], text: title);
  }
}
