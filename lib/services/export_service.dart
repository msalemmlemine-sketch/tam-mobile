import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/database/app_database.dart';

/// خدمة تصدير التقارير والقوائم.
///
/// المزايا:
/// - PDF عربي RTL.
/// - عمود الاسم يكون في أقصى اليمين فعليًا.
/// - استعمال خط Amiri المضمّن داخل التطبيق.
/// - شعار المنظمة من الإعدادات.
/// - اسم المنظمة من الإعدادات.
/// - اسم أمين التنظيم والنقيب الجهوي من الإعدادات إن وُجدا.
/// - في حال عدم وجود اسمي المسؤولين في settings يتم جلبهما
///   من جدول users حسب الدور الموجود في قاعدة البيانات.
/// - التوقيعات تظهر في نهاية التقرير فقط.
/// - CSV يبقى متوافقًا مع الاستدعاءات الحالية.
/// - لا يحتاج إلى اتصال بالإنترنت.
class ExportService {
  // ============================================================
  // الملفات المؤقتة
  // ============================================================

  Future<File> _writeTempFile(
    String fileName,
    List<int> bytes,
  ) async {
    final dir = await getTemporaryDirectory();

    final safeName = _safeFileName(fileName);
    final file = File(p.join(dir.path, safeName));

    await file.writeAsBytes(bytes, flush: true);

    return file;
  }

  String _safeFileName(String fileName) {
    // نحتفظ بالأسماء العربية، ونزيل فقط المحارف التي قد تسبب
    // مشكلة في اسم الملف.
    return fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();
  }

  // ============================================================
  // الخطوط
  // ============================================================

  Future<pw.Font?> _tryLoadFont(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return pw.Font.ttf(data);
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // قراءة إعداد واحد
  // ============================================================

  Future<String?> _getSetting(
    String key,
  ) async {
    try {
      final db = await AppDatabase.instance.database;

      final rows = await db.query(
        'settings',
        columns: ['setting_value'],
        where: 'setting_key = ?',
        whereArgs: [key],
        limit: 1,
      );

      if (rows.isEmpty) return null;

      final value = rows.first['setting_value'];

      if (value == null) return null;

      final text = value.toString().trim();

      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // قراءة أول إعداد موجود من عدة مفاتيح
  // ============================================================

  Future<String?> _getFirstSetting(
    List<String> keys,
  ) async {
    for (final key in keys) {
      final value = await _getSetting(key);

      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return null;
  }

  // ============================================================
  // تحميل بيانات المنظمة والمسؤولين
  // ============================================================

  Future<_OrganizationInfo> _loadOrganizationInfo() async {
    String organizationName =
        await _getSetting('org_name') ??
        'نقابة تحالف أساتذة موريتانيا';

    String shortName =
        await _getSetting('org_short') ??
        'تام';

    // ------------------------------------------------------------
    // اسم أمين التنظيم
    //
    // ندعم عدة مفاتيح مستقبلية دون كسر النسخة الحالية.
    // ------------------------------------------------------------

    String? organizationSecretary =
        await _getFirstSetting([
      'organization_secretary_name',
      'org_secretary_name',
      'secretary_name',
    ]);

    // ------------------------------------------------------------
    // اسم النقيب الجهوي
    // ------------------------------------------------------------

    String? regionalCaptain =
        await _getFirstSetting([
      'regional_captain_name',
      'captain_name',
      'regional_captain',
    ]);

    // ------------------------------------------------------------
    // اسم أمين المالية
    // ------------------------------------------------------------

    String? financeSecretary =
        await _getFirstSetting([
      'finance_secretary_name',
      'org_finance_secretary_name',
      'finance_name',
    ]);

    // ------------------------------------------------------------
    // إذا لم توجد الأسماء في settings،
    // نقرأ users حسب role من قاعدة البيانات الحالية.
    // ------------------------------------------------------------

    try {
      final db = await AppDatabase.instance.database;

      if (organizationSecretary == null) {
        final rows = await db.query(
          'users',
          columns: ['display_name'],
          where: 'role = ?',
          whereArgs: ['organization_secretary'],
          limit: 1,
        );

        if (rows.isNotEmpty) {
          final value = rows.first['display_name']?.toString().trim();

          if (value != null && value.isNotEmpty) {
            organizationSecretary = value;
          }
        }
      }

      if (regionalCaptain == null) {
        final rows = await db.query(
          'users',
          columns: ['display_name'],
          where: 'role = ?',
          whereArgs: ['regional_captain'],
          limit: 1,
        );

        if (rows.isNotEmpty) {
          final value = rows.first['display_name']?.toString().trim();

          if (value != null && value.isNotEmpty) {
            regionalCaptain = value;
          }
        }
      }

      if (financeSecretary == null) {
        final rows = await db.query(
          'users',
          columns: ['display_name'],
          where: 'role = ?',
          whereArgs: ['finance_secretary'],
          limit: 1,
        );

        if (rows.isNotEmpty) {
          final value = rows.first['display_name']?.toString().trim();

          if (value != null && value.isNotEmpty) {
            financeSecretary = value;
          }
        }
      }
    } catch (_) {
      // لا نوقف التصدير إذا تعذر تحميل المسؤولين.
    }

    return _OrganizationInfo(
      name: organizationName,
      shortName: shortName,
      organizationSecretary: organizationSecretary,
      financeSecretary: financeSecretary,
      regionalCaptain: regionalCaptain,
    );
  }

  // ============================================================
  // تحميل الشعار
  // ============================================================

  Future<pw.ImageProvider?> _loadLogo() async {
    try {
      final path = await _getSetting('org_logo_path');

      if (path == null || path.isEmpty) {
        return null;
      }

      final file = File(path);

      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        return null;
      }

      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // التاريخ والوقت
  // ============================================================

  String _formatDateTime(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // CSV
  // ============================================================

  Future<void> exportCsv({
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
    List<String>? totalsRow,
  }) async {
    final csv = const ListToCsvConverter().convert([
      headers,
      ...rows,
      if (totalsRow != null) totalsRow,
    ]);

    // BOM لضمان ظهور العربية بشكل صحيح في Excel.
    final bytes = [
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(csv),
    ];

    final file = await _writeTempFile(
      fileName,
      bytes,
    );

    await Share.shareXFiles(
      [XFile(file.path)],
      text: fileName,
    );
  }

  // ============================================================
  // اكتشاف عمود الاسم
  // ============================================================

  int _findNameColumn(
    List<String> headers,
  ) {
    final candidates = <String>{
      'الاسم',
      'الاسم واللقب',
      'اسم المنتسب',
      'اسم الأستاذ',
      'اسم العضو',
      'المنتسب',
      'العضو',
      'الأستاذ',
      'اسم',
    };

    for (var i = 0; i < headers.length; i++) {
      final value = headers[i].trim();

      if (candidates.contains(value)) {
        return i;
      }
    }

    // فحص أكثر مرونة.
    for (var i = 0; i < headers.length; i++) {
      final value = headers[i].trim();

      if (value.contains('الاسم') ||
          value.contains('اسم المنتسب') ||
          value.contains('اسم العضو')) {
        return i;
      }
    }

    return -1;
  }

  // ============================================================
  // جعل عمود الاسم في أقصى اليمين
  //
  // Table في pdf يعتمد ترتيب العناصر بصريًا من اليسار إلى اليمين.
  // لذلك نقل الاسم إلى آخر عنصر يجعله في أقصى اليمين.
  // ============================================================

  _ReorderedTable _reorderTable({
    required List<String> headers,
    required List<List<String>> rows,
    List<String>? totalsRow,
  }) {
    final nameIndex = _findNameColumn(headers);

    // لا يوجد عمود اسم واضح.
    if (nameIndex < 0 || headers.length <= 1) {
      return _ReorderedTable(
        headers: List<String>.from(headers),
        rows: rows.map(List<String>.from).toList(),
        totalsRow:
            totalsRow == null ? null : List<String>.from(totalsRow),
        nameIndex: -1,
      );
    }

    final indexes = <int>[
      for (var i = 0; i < headers.length; i++)
        if (i != nameIndex) i,
      nameIndex,
    ];

    List<String> reorderRow(List<String> row) {
      return indexes
          .map(
            (index) =>
                index < row.length ? row[index] : '',
          )
          .toList();
    }

    return _ReorderedTable(
      headers: indexes.map((i) => headers[i]).toList(),
      rows: rows.map(reorderRow).toList(),
      totalsRow:
          totalsRow == null ? null : reorderRow(totalsRow),
      nameIndex: indexes.length - 1,
    );
  }

  // ============================================================
  // خلية جدول
  // ============================================================

  pw.Widget _tableCell({
    required String text,
    required bool header,
    required bool isName,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    final font = header
        ? (bold ?? regular)
        : regular;

    final style = pw.TextStyle(
      font: font,
      fontSize: header ? 9.5 : 9,
      fontWeight:
          header ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 5,
      ),
      alignment: isName
          ? pw.Alignment.centerRight
          : pw.Alignment.center,
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        textAlign: isName
            ? pw.TextAlign.right
            : pw.TextAlign.center,
        style: style,
      ),
    );
  }

  // ============================================================
  // إنشاء الجدول
  // ============================================================

  pw.Widget _buildTable({
    required List<String> headers,
    required List<List<String>> rows,
    required int nameColumnIndex,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    final tableRows = <pw.TableRow>[];

    // ------------------------------------------------------------
    // Header
    // ------------------------------------------------------------

    tableRows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFE0F2EF),
        ),
        children: [
          for (var i = 0; i < headers.length; i++)
            _tableCell(
              text: headers[i],
              header: true,
              isName: i == nameColumnIndex,
              regular: regular,
              bold: bold,
            ),
        ],
      ),
    );

    // ------------------------------------------------------------
    // Data
    // ------------------------------------------------------------

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];

      tableRows.add(
        pw.TableRow(
          decoration: rowIndex.isEven
              ? null
              : const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF8FAFA),
                ),
          children: [
            for (var i = 0; i < headers.length; i++)
              _tableCell(
                text: i < row.length ? row[i] : '',
                header: false,
                isName: i == nameColumnIndex,
                regular: regular,
                bold: bold,
              ),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(
        color: PdfColors.grey400,
        width: 0.5,
      ),
      defaultVerticalAlignment:
          pw.TableCellVerticalAlignment.middle,
      children: tableRows,
    );
  }

  // ============================================================
  // صف الإجماليات
  // ============================================================

  pw.Widget _buildTotalsRow({
    required List<String> totalsRow,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 4),
      padding: const pw.EdgeInsets.symmetric(
        vertical: 7,
        horizontal: 5,
      ),
      decoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF0F0F0),
      ),
      child: pw.Row(
        textDirection: pw.TextDirection.ltr,
        children: [
          for (final cell in totalsRow)
            pw.Expanded(
              child: pw.Text(
                cell,
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: bold ?? regular,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // رأس التقرير
  // ============================================================

  pw.Widget _buildHeader({
    required _OrganizationInfo organization,
    required pw.ImageProvider? logo,
    required String title,
    required String generatedAt,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    final titleStyle = pw.TextStyle(
      font: bold ?? regular,
      fontSize: 17,
      fontWeight: pw.FontWeight.bold,
    );

    final organizationStyle = pw.TextStyle(
      font: bold ?? regular,
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
    );

    final smallStyle = pw.TextStyle(
      font: regular,
      fontSize: 8.5,
      color: PdfColors.grey700,
    );

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null) ...[
            pw.Container(
              width: 58,
              height: 58,
              padding: const pw.EdgeInsets.all(2),
              child: pw.Image(
                logo,
                fit: pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(height: 5),
          ],

          pw.Text(
            organization.name,
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            style: organizationStyle,
          ),

          if (organization.shortName.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              organization.shortName,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: smallStyle,
            ),
          ],

          pw.SizedBox(height: 7),

          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(
              vertical: 7,
              horizontal: 10,
            ),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(
                  color: PdfColors.grey600,
                  width: 0.7,
                ),
                bottom: pw.BorderSide(
                  color: PdfColors.grey600,
                  width: 0.7,
                ),
              ),
            ),
            child: pw.Text(
              title,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: titleStyle,
            ),
          ),

          pw.SizedBox(height: 5),

          pw.Text(
            'تاريخ الإصدار: $generatedAt',
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            style: smallStyle,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // التوقيعات
  //
  // توضع بعد محتوى التقرير، وبالتالي تظهر في الصفحة الأخيرة
  // وليس في Footer لكل الصفحات.
  // ============================================================

  pw.Widget _buildSignatures({
    required _OrganizationInfo organization,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    final signatures = <pw.Widget>[];

    if (organization.organizationSecretary != null &&
        organization.organizationSecretary!.isNotEmpty) {
      signatures.add(
        _buildSignature(
          role: 'أمين التنظيم',
          name: organization.organizationSecretary!,
          regular: regular,
          bold: bold,
        ),
      );
    }

    if (organization.regionalCaptain != null &&
        organization.regionalCaptain!.isNotEmpty) {
      signatures.add(
        _buildSignature(
          role: 'النقيب الجهوي',
          name: organization.regionalCaptain!,
          regular: regular,
          bold: bold,
        ),
      );
    }

    if (signatures.isEmpty) {
      return pw.SizedBox();
    }

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 24),
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            color: PdfColors.grey400,
            width: 0.6,
          ),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment:
            pw.MainAxisAlignment.spaceAround,
        crossAxisAlignment:
            pw.CrossAxisAlignment.start,
        children: signatures,
      ),
    );
  }

  pw.Widget _buildSignature({
    required String role,
    required String name,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment:
            pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            role,
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: bold ?? regular,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),

          pw.SizedBox(height: 18),

          pw.Container(
            width: 100,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(
                  color: PdfColors.grey600,
                  width: 0.7,
                ),
              ),
            ),
            height: 1,
          ),

          pw.SizedBox(height: 6),

          pw.Text(
            name,
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: bold ?? regular,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PDF TABLE
  // ============================================================

  Future<void> exportPdfTable({
    required String fileName,
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    List<String>? totalsRow,
  }) async {
    final doc = pw.Document();

    // ------------------------------------------------------------
    // الخطوط العربية المضمّنة في المشروع
    // ------------------------------------------------------------

    final regular = await _tryLoadFont(
      'assets/fonts/arabic_regular.ttf',
    );

    final bold = await _tryLoadFont(
      'assets/fonts/arabic_bold.ttf',
    );

    // ------------------------------------------------------------
    // المنظمة + المسؤولون + الشعار
    // ------------------------------------------------------------

    final organization =
        await _loadOrganizationInfo();

    final logo = await _loadLogo();

    // ------------------------------------------------------------
    // التاريخ
    // ------------------------------------------------------------

    final now = DateTime.now();

    final generatedAt =
        _formatDateTime(now);

    // ------------------------------------------------------------
    // إعادة ترتيب الجدول:
    // الاسم ← أقصى اليمين
    // ------------------------------------------------------------

    final reordered = _reorderTable(
      headers: headers,
      rows: rows,
      totalsRow: totalsRow,
    );

    // ------------------------------------------------------------
    // الصفحة
    // ------------------------------------------------------------

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          25,
          25,
          25,
          30,
        ),

        textDirection: pw.TextDirection.rtl,

        theme: regular != null
            ? pw.ThemeData.withFont(
                base: regular,
                bold: bold ?? regular,
              )
            : null,

        // --------------------------------------------------------
        // Header يتكرر أعلى الصفحات
        // --------------------------------------------------------

        header: (context) {
          return _buildHeader(
            organization: organization,
            logo: logo,
            title: title,
            generatedAt: generatedAt,
            regular: regular,
            bold: bold,
          );
        },

        // --------------------------------------------------------
        // Footer
        //
        // لا توجد فيه التوقيعات.
        // التوقيعات تظهر فقط في نهاية التقرير.
        // --------------------------------------------------------

        footer: (context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 8),
            padding: const pw.EdgeInsets.only(top: 5),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
              ),
            ),
            child: pw.Row(
              textDirection: pw.TextDirection.ltr,
              mainAxisAlignment:
                  pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'صفحة ${context.pageNumber} من ${context.pagesCount}',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: regular,
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),

                pw.Text(
                  organization.shortName,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: regular,
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),

                pw.Text(
                  generatedAt,
                  textDirection: pw.TextDirection.ltr,
                  style: pw.TextStyle(
                    font: regular,
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          );
        },

        // --------------------------------------------------------
        // محتوى التقرير
        // --------------------------------------------------------

        build: (context) {
          final widgets = <pw.Widget>[];

          // الجدول
          if (reordered.headers.isNotEmpty) {
            widgets.add(
              _buildTable(
                headers: reordered.headers,
                rows: reordered.rows,
                nameColumnIndex:
                    reordered.nameIndex,
                regular: regular,
                bold: bold,
              ),
            );
          }

          // الإجمالي
          if (reordered.totalsRow != null) {
            widgets.add(
              _buildTotalsRow(
                totalsRow: reordered.totalsRow!,
                regular: regular,
                bold: bold,
              ),
            );
          }

          // التوقيعات في نهاية التقرير فقط
          widgets.add(
            _buildSignatures(
              organization: organization,
              regular: regular,
              bold: bold,
            ),
          );

          return widgets;
        },
      ),
    );

    // ------------------------------------------------------------
    // حفظ PDF
    // ------------------------------------------------------------

    final bytes = await doc.save();

    final file = await _writeTempFile(
      fileName,
      bytes,
    );

    // ------------------------------------------------------------
    // مشاركة / طباعة
    // ------------------------------------------------------------

    await Share.shareXFiles(
      [XFile(file.path)],
      text: title,
    );
  }
}

// =================================================================
// بيانات المنظمة
// =================================================================

class _OrganizationInfo {
  final String name;
  final String shortName;

  final String? organizationSecretary;
  final String? financeSecretary;
  final String? regionalCaptain;

  const _OrganizationInfo({
    required this.name,
    required this.shortName,
    this.organizationSecretary,
    this.financeSecretary,
    this.regionalCaptain,
  });
}

// =================================================================
// نتيجة إعادة ترتيب الجدول
// =================================================================

class _ReorderedTable {
  final List<String> headers;
  final List<List<String>> rows;
  final List<String>? totalsRow;

  /// موضع الاسم بعد إعادة الترتيب.
  ///
  /// بما أن الاسم يُنقل إلى آخر عمود،
  /// يكون هذا غالبًا headers.length - 1.
  final int nameIndex;

  const _ReorderedTable({
    required this.headers,
    required this.rows,
    required this.totalsRow,
    required this.nameIndex,
  });
}
