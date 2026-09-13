import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

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
      // احتياط دفاعي فقط — الملفان موجودان فعليًا في assets/fonts؛
      // هذا يمنع تعطل التصدير بالكامل لو حُذف الأصل لاحقًا بالخطأ.
      return null;
    }
  }

  Future<void> exportCsv({
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final csv = const ListToCsvConverter().convert([headers, ...rows]);
    // BOM حتى يفتح إكسل الملف بترميز عربي صحيح مباشرة.
    final bytes = [0xEF, 0xBB, 0xBF, ...csv.codeUnits];
    final file = await _writeTempFile(fileName, bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: fileName),
    );
  }

  /// ينشئ PDF بسيط لجدول بيانات (عنوان + رأس جدول + صفوف)، ثم يفتح
  /// قائمة المشاركة/الطباعة. يحمّل خطًا عربيًا محليًا من الحزمة
  /// (assets/fonts) إن وُجد — راجع ملاحظة الخط أعلى الملف.
  Future<void> exportPdfTable({
    required String fileName,
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final doc = pw.Document();
    final regular = await _tryLoadFont('assets/fonts/arabic_regular.ttf');
    final bold = await _tryLoadFont('assets/fonts/arabic_bold.ttf');

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: regular != null
            ? pw.ThemeData.withFont(base: regular, bold: bold ?? regular)
            : null,
        build: (context) => [
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
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: title),
    );
  }
}
