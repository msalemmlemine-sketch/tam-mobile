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
/// - اسم أمين التنظيم والنقيب الجهوي وأمين المالية من الإعدادات
///   إن وُجدا، وإلا من جدول users حسب الدور، وإلا قيم افتراضية.
/// - التوقيعات تظهر في نهاية التقرير فقط.
/// - CSV يبقى متوافقًا مع الاستدعاءات الحالية.
/// - لا يحتاج إلى اتصال بالإنترنت.
/// - exportPdfReport: تقرير متعدد الأقسام.
/// - exportPdfGroupedList: لائحة مجمعة حسب المؤسسة.
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

  Future<String?> _getSetting(String key) async {
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
        await _getSetting('org_short') ?? 'تام';

    String? organizationSecretary =
        await _getFirstSetting([
      'organization_secretary_name',
      'org_secretary_name',
      'secretary_name',
    ]);

    String? regionalCaptain =
        await _getFirstSetting([
      'regional_captain_name',
      'captain_name',
      'regional_captain',
    ]);

    String? financeSecretary =
        await _getFirstSetting([
      'finance_secretary_name',
      'org_finance_secretary_name',
      'finance_name',
    ]);

    try {
      final db =
          await AppDatabase.instance.database;

      if (organizationSecretary == null) {
        final rows = await db.query(
          'users',
          columns: ['display_name'],
          where: 'role = ?',
          whereArgs: [
            'organization_secretary',
          ],
          limit: 1,
        );

        if (rows.isNotEmpty) {
          final value = rows.first['display_name']
              ?.toString()
              .trim();

          if (value != null &&
              value.isNotEmpty) {
            organizationSecretary = value;
          }
        }
      }

      if (regionalCaptain == null) {
        final rows = await db.query(
          'users',
          columns: ['display_name'],
          where: 'role = ?',
          whereArgs: [
            'regional_captain',
          ],
          limit: 1,
        );

        if (rows.isNotEmpty) {
          final value = rows.first['display_name']
              ?.toString()
              .trim();

          if (value != null &&
              value.isNotEmpty) {
            regionalCaptain = value;
          }
        }
      }

      if (financeSecretary == null) {
        final rows = await db.query(
          'users',
          columns: ['display_name'],
          where: 'role = ?',
          whereArgs: [
            'finance_secretary',
          ],
          limit: 1,
        );

        if (rows.isNotEmpty) {
          final value = rows.first['display_name']
              ?.toString()
              .trim();

          if (value != null &&
              value.isNotEmpty) {
            financeSecretary = value;
          }
        }
      }
    } catch (_) {}

    organizationSecretary ??=
        'محمد سالم ابن عمر';

    regionalCaptain ??=
        'الشيخ سيد اعل';

    financeSecretary ??=
        'عيسى بابا محمد أعمش';

    return _OrganizationInfo(
      name: organizationName,
      shortName: shortName,
      organizationSecretary:
          organizationSecretary,
      financeSecretary:
          financeSecretary,
      regionalCaptain:
          regionalCaptain,
    );
  }

  // ============================================================
  // تحميل الشعار
  // ============================================================

  Future<pw.ImageProvider?> _loadLogo() async {
    try {
      final path =
          await _getSetting('org_logo_path');

      if (path == null || path.isEmpty) {
        return null;
      }

      final file = File(path);

      if (!await file.exists()) {
        return null;
      }

      final bytes =
          await file.readAsBytes();

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
    final csv =
        const ListToCsvConverter().convert([
      headers,
      ...rows,
      if (totalsRow != null) totalsRow,
    ]);

    final bytes = [
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(csv),
    ];

    final file =
        await _writeTempFile(
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

    for (
      var i = 0;
      i < headers.length;
      i++
    ) {
      final value =
          headers[i].trim();

      if (candidates.contains(value)) {
        return i;
      }
    }

    for (
      var i = 0;
      i < headers.length;
      i++
    ) {
      final value =
          headers[i].trim();

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
  // ============================================================

  _ReorderedTable _reorderTable({
    required List<String> headers,
    required List<List<String>> rows,
    List<String>? totalsRow,
  }) {
    final nameIndex =
        _findNameColumn(headers);

    if (nameIndex < 0 ||
        headers.length <= 1) {
      return _ReorderedTable(
        headers:
            List<String>.from(headers),
        rows: rows
            .map(List<String>.from)
            .toList(),
        totalsRow:
            totalsRow == null
                ? null
                : List<String>.from(
                    totalsRow,
                  ),
        nameIndex: -1,
      );
    }

    final indexes = <int>[
      for (
        var i = 0;
        i < headers.length;
        i++
      )
        if (i != nameIndex) i,
      nameIndex,
    ];

    List<String> reorderRow(
      List<String> row,
    ) {
      return indexes
          .map(
            (index) =>
                index < row.length
                    ? row[index]
                    : '',
          )
          .toList();
    }

    return _ReorderedTable(
      headers: indexes
          .map((i) => headers[i])
          .toList(),
      rows: rows
          .map(reorderRow)
          .toList(),
      totalsRow:
          totalsRow == null
              ? null
              : reorderRow(totalsRow),
      nameIndex:
          indexes.length - 1,
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
    final font =
        header ? (bold ?? regular) : regular;

    final style = pw.TextStyle(
      font: font,
      fontSize:
          header ? 9.5 : 9,
      fontWeight: header
          ? pw.FontWeight.bold
          : pw.FontWeight.normal,
    );

    return pw.Container(
      width: double.infinity,
      padding:
          const pw.EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 5,
      ),
      alignment: isName
          ? pw.Alignment.centerRight
          : pw.Alignment.center,
      child: pw.Text(
        text,
        textDirection:
            pw.TextDirection.rtl,
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
    Map<int, pw.TableColumnWidth>?
        columnWidths,
  }) {
    final tableRows =
        <pw.TableRow>[];

    tableRows.add(
      pw.TableRow(
        decoration:
            const pw.BoxDecoration(
          color: PdfColor.fromInt(
            0xFFE0F2EF,
          ),
        ),
        children: [
          for (
            var i = 0;
            i < headers.length;
            i++
          )
            _tableCell(
              text: headers[i],
              header: true,
              isName:
                  i == nameColumnIndex,
              regular: regular,
              bold: bold,
            ),
        ],
      ),
    );

    for (
      var rowIndex = 0;
      rowIndex < rows.length;
      rowIndex++
    ) {
      final row =
          rows[rowIndex];

      tableRows.add(
        pw.TableRow(
          decoration:
              rowIndex.isEven
                  ? null
                  : const pw.BoxDecoration(
                      color:
                          PdfColor.fromInt(
                        0xFFF8FAFA,
                      ),
                    ),
          children: [
            for (
              var i = 0;
              i < headers.length;
              i++
            )
              _tableCell(
                text: i < row.length
                    ? row[i]
                    : '',
                header: false,
                isName:
                    i == nameColumnIndex,
                regular: regular,
                bold: bold,
              ),
          ],
        ),
      );
    }

    return pw.Table(
      border:
          pw.TableBorder.all(
        color: PdfColors.grey400,
        width: 0.5,
      ),
      defaultVerticalAlignment:
          pw.TableCellVerticalAlignment
              .middle,
      columnWidths: columnWidths,
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
      margin:
          const pw.EdgeInsets.only(
        top: 4,
      ),
      padding:
          const pw.EdgeInsets.symmetric(
        vertical: 7,
        horizontal: 5,
      ),
      decoration:
          const pw.BoxDecoration(
        color: PdfColor.fromInt(
          0xFFF0F0F0,
        ),
      ),
      child: pw.Directionality(
        textDirection:
            pw.TextDirection.ltr,
        child: pw.Row(
          children: [
            for (final cell
                in totalsRow)
              pw.Expanded(
                child: pw.Text(
                  cell,
                  textDirection:
                      pw.TextDirection.rtl,
                  textAlign:
                      pw.TextAlign.center,
                  style: pw.TextStyle(
                    font:
                        bold ?? regular,
                    fontSize: 9,
                    fontWeight:
                        pw.FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
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
    final titleStyle =
        pw.TextStyle(
      font: bold ?? regular,
      fontSize: 17,
      fontWeight:
          pw.FontWeight.bold,
    );

    final organizationStyle =
        pw.TextStyle(
      font: bold ?? regular,
      fontSize: 12,
      fontWeight:
          pw.FontWeight.bold,
    );

    final smallStyle =
        pw.TextStyle(
      font: regular,
      fontSize: 8.5,
      color: PdfColors.grey700,
    );

    return pw.Container(
      margin:
          const pw.EdgeInsets.only(
        bottom: 10,
      ),
      child: pw.Column(
        crossAxisAlignment:
            pw.CrossAxisAlignment.center,
        children: [
          if (logo != null) ...[
            pw.Container(
              width: 58,
              height: 58,
              padding:
                  const pw.EdgeInsets.all(
                2,
              ),
              child: pw.Image(
                logo,
                fit:
                    pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(height: 5),
          ],
          pw.Text(
            organization.name,
            textDirection:
                pw.TextDirection.rtl,
            textAlign:
                pw.TextAlign.center,
            style:
                organizationStyle,
          ),
          if (organization
              .shortName
              .isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              organization.shortName,
              textDirection:
                  pw.TextDirection.rtl,
              textAlign:
                  pw.TextAlign.center,
              style: smallStyle,
            ),
          ],
          pw.SizedBox(height: 7),
          pw.Container(
            width: double.infinity,
            padding:
                const pw.EdgeInsets
                    .symmetric(
              vertical: 7,
              horizontal: 10,
            ),
            decoration:
                const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(
                  color:
                      PdfColors.grey600,
                  width: 0.7,
                ),
                bottom:
                    pw.BorderSide(
                  color:
                      PdfColors.grey600,
                  width: 0.7,
                ),
              ),
            ),
            child: pw.Text(
              title,
              textDirection:
                  pw.TextDirection.rtl,
              textAlign:
                  pw.TextAlign.center,
              style: titleStyle,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            'تاريخ الإصدار: $generatedAt',
            textDirection:
                pw.TextDirection.rtl,
            textAlign:
                pw.TextAlign.center,
            style: smallStyle,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // التوقيعات العامة
  // ============================================================

  pw.Widget _buildSignatures({
    required _OrganizationInfo organization,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    final signatures = <pw.Widget>[
      _buildSignature(
        role: 'النقيب الجهوي',
        name:
            organization.regionalCaptain ??
                '',
        regular: regular,
        bold: bold,
      ),
      _buildSignature(
        role: 'أمين التنظيم',
        name:
            organization
                    .organizationSecretary ??
                '',
        regular: regular,
        bold: bold,
      ),
      _buildSignature(
        role: 'أمين المالية',
        name:
            organization
                    .financeSecretary ??
                '',
        regular: regular,
        bold: bold,
      ),
    ];

    return pw.Container(
      margin:
          const pw.EdgeInsets.only(
        top: 24,
      ),
      padding:
          const pw.EdgeInsets.only(
        top: 10,
      ),
      decoration:
          const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            color: PdfColors.grey400,
            width: 0.6,
          ),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment:
            pw.MainAxisAlignment
                .spaceAround,
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
            textDirection:
                pw.TextDirection.rtl,
            textAlign:
                pw.TextAlign.center,
            style: pw.TextStyle(
              font: bold ?? regular,
              fontSize: 9,
              fontWeight:
                  pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            width: 100,
            decoration:
                const pw.BoxDecoration(
              border: pw.Border(
                bottom:
                    pw.BorderSide(
                  color:
                      PdfColors.grey600,
                  width: 0.7,
                ),
              ),
            ),
            height: 1,
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            name,
            textDirection:
                pw.TextDirection.rtl,
            textAlign:
                pw.TextAlign.center,
            style: pw.TextStyle(
              font: bold ?? regular,
              fontSize: 9,
              fontWeight:
                  pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // بطاقة ملخص واحدة
  // ============================================================

  pw.Widget _buildSummaryCard({
    required ReportSummaryCard card,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    return pw.Container(
      width: 118,
      padding:
          const pw.EdgeInsets.symmetric(
        vertical: 10,
        horizontal: 8,
      ),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(
          0xFFF7FAF9,
        ),
        border: pw.Border.all(
          color: PdfColors.grey300,
          width: 0.6,
        ),
        borderRadius:
            const pw.BorderRadius.all(
          pw.Radius.circular(6),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
            pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            card.value,
            textDirection:
                pw.TextDirection.rtl,
            textAlign:
                pw.TextAlign.center,
            style: pw.TextStyle(
              font: bold ?? regular,
              fontSize: 13,
              fontWeight:
                  pw.FontWeight.bold,
              color:
                  card.accentColor ??
                      PdfColors.teal800,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            card.title,
            textDirection:
                pw.TextDirection.rtl,
            textAlign:
                pw.TextAlign.center,
            style: pw.TextStyle(
              font: regular,
              fontSize: 8.5,
            ),
          ),
          if (card.subtitle != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              card.subtitle!,
              textDirection:
                  pw.TextDirection.rtl,
              textAlign:
                  pw.TextAlign.center,
              style: pw.TextStyle(
                font: regular,
                fontSize: 7.5,
                color:
                    PdfColors.grey600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildSummaryCardsGrid({
    required List<ReportSummaryCard> cards,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    if (cards.isEmpty) {
      return pw.SizedBox();
    }

    return pw.Container(
      margin:
          const pw.EdgeInsets.only(
        bottom: 14,
      ),
      child: pw.Wrap(
        alignment:
            pw.WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in cards)
            _buildSummaryCard(
              card: c,
              regular: regular,
              bold: bold,
            ),
        ],
      ),
    );
  }

  pw.Widget _buildSectionTitle({
    required String title,
    String? note,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    return pw.Container(
      margin:
          const pw.EdgeInsets.only(
        top: 14,
        bottom: 6,
      ),
      child: pw.Column(
        crossAxisAlignment:
            pw.CrossAxisAlignment
                .stretch,
        children: [
          pw.Container(
            padding:
                const pw.EdgeInsets
                    .symmetric(
              vertical: 5,
              horizontal: 8,
            ),
            decoration:
                const pw.BoxDecoration(
              color: PdfColor.fromInt(
                0xFF0F5C52,
              ),
              borderRadius:
                  pw.BorderRadius.all(
                pw.Radius.circular(4),
              ),
            ),
            child: pw.Text(
              title,
              textDirection:
                  pw.TextDirection.rtl,
              textAlign:
                  pw.TextAlign.right,
              style: pw.TextStyle(
                font: bold ?? regular,
                fontSize: 11,
                fontWeight:
                    pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
          if (note != null) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              note,
              textDirection:
                  pw.TextDirection.rtl,
              textAlign:
                  pw.TextAlign.right,
              style: pw.TextStyle(
                font: regular,
                fontSize: 8,
                color:
                    PdfColors.grey700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // شارة عنوان مجموعة (مؤسسة)
  // ============================================================

  pw.Widget _buildGroupHeader({
    required String title,
    required int count,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    return pw.Container(
      margin:
          const pw.EdgeInsets.only(
        top: 14,
      ),
      padding:
          const pw.EdgeInsets.symmetric(
        vertical: 6,
        horizontal: 10,
      ),
      decoration:
          const pw.BoxDecoration(
        color: PdfColor.fromInt(
          0xFF14532D,
        ),
        borderRadius:
            pw.BorderRadius.only(
          topLeft:
              pw.Radius.circular(4),
          topRight:
              pw.Radius.circular(4),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment:
            pw.MainAxisAlignment
                .spaceBetween,
        crossAxisAlignment:
            pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            padding:
                const pw.EdgeInsets
                    .symmetric(
              horizontal: 10,
              vertical: 3,
            ),
            decoration:
                pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius:
                  pw.BorderRadius.circular(
                12,
              ),
            ),
            child: pw.Text(
              '$count منتسب',
              textDirection:
                  pw.TextDirection.rtl,
              style: pw.TextStyle(
                font: bold ?? regular,
                fontSize: 8,
                fontWeight:
                    pw.FontWeight.bold,
                color:
                    const PdfColor.fromInt(
                  0xFF14532D,
                ),
              ),
            ),
          ),
          pw.Text(
            title,
            textDirection:
                pw.TextDirection.rtl,
            textAlign:
                pw.TextAlign.right,
            style: pw.TextStyle(
              font: bold ?? regular,
              fontSize: 11,
              fontWeight:
                  pw.FontWeight.bold,
              color: PdfColors.white,
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

    final regular =
        await _tryLoadFont(
      'assets/fonts/arabic_regular.ttf',
    );

    final bold =
        await _tryLoadFont(
      'assets/fonts/arabic_bold.ttf',
    );

    final organization =
        await _loadOrganizationInfo();

    final logo =
        await _loadLogo();

    final now = DateTime.now();

    final generatedAt =
        _formatDateTime(now);

    final reordered =
        _reorderTable(
      headers: headers,
      rows: rows,
      totalsRow: totalsRow,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat:
            PdfPageFormat.a4,
        margin:
            const pw.EdgeInsets.fromLTRB(
          25,
          25,
          25,
          30,
        ),
        textDirection:
            pw.TextDirection.rtl,
        theme: regular != null
            ? pw.ThemeData.withFont(
                base: regular,
                bold: bold ?? regular,
              )
            : null,
        header: (context) =>
            _buildHeader(
          organization:
              organization,
          logo: logo,
          title: title,
          generatedAt:
              generatedAt,
          regular: regular,
          bold: bold,
        ),
        footer: (context) =>
            pw.Container(
          margin:
              const pw.EdgeInsets.only(
            top: 8,
          ),
          padding:
              const pw.EdgeInsets.only(
            top: 5,
          ),
          decoration:
              const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(
                color:
                    PdfColors.grey300,
                width: 0.5,
              ),
            ),
          ),
          child: pw.Directionality(
            textDirection:
                pw.TextDirection.ltr,
            child: pw.Row(
              mainAxisAlignment:
                  pw.MainAxisAlignment
                      .spaceBetween,
              children: [
                pw.Text(
                  'صفحة ${context.pageNumber} من ${context.pagesCount}',
                  textDirection:
                      pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: regular,
                    fontSize: 8,
                    color:
                        PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  organization.shortName,
                  textDirection:
                      pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: regular,
                    fontSize: 8,
                    color:
                        PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  generatedAt,
                  textDirection:
                      pw.TextDirection.ltr,
                  style: pw.TextStyle(
                    font: regular,
                    fontSize: 8,
                    color:
                        PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
        ),
        build: (context) {
          final widgets =
              <pw.Widget>[];

          if (reordered
              .headers
              .isNotEmpty) {
            widgets.add(
              _buildTable(
                headers:
                    reordered.headers,
                rows:
                    reordered.rows,
                nameColumnIndex:
                    reordered.nameIndex,
                regular: regular,
                bold: bold,
              ),
            );
          }

          if (reordered
                  .totalsRow !=
              null) {
            widgets.add(
              _buildTotalsRow(
                totalsRow:
                    reordered.totalsRow!,
                regular: regular,
                bold: bold,
              ),
            );
          }

          widgets.add(
            _buildSignatures(
              organization:
                  organization,
              regular: regular,
              bold: bold,
            ),
          );

          return widgets;
        },
      ),
    );

    final bytes =
        await doc.save();

    final file =
        await _writeTempFile(
      fileName,
      bytes,
    );

    await Share.shareXFiles(
      [XFile(file.path)],
      text: title,
    );
  }

  // ============================================================
  // PDF REPORT
  // ============================================================

  Future<void> exportPdfReport({
    required String fileName,
    required String title,
    List<ReportSummaryCard> cards =
        const [],
    required List<ReportTableSection>
        sections,
  }) async {
    final doc = pw.Document();

    final regular =
        await _tryLoadFont(
      'assets/fonts/arabic_regular.ttf',
    );

    final bold =
        await _tryLoadFont(
      'assets/fonts/arabic_bold.ttf',
    );

    final organization =
        await _loadOrganizationInfo();

    final logo =
        await _loadLogo();

    final now = DateTime.now();

    final generatedAt =
        _formatDateTime(now);

    doc.addPage(
      pw.MultiPage(
        pageFormat:
            PdfPageFormat.a4,
        margin:
            const pw.EdgeInsets.fromLTRB(
          25,
          25,
          25,
          30,
        ),
        textDirection:
            pw.TextDirection.rtl,
        theme: regular != null
            ? pw.ThemeData.withFont(
                base: regular,
                bold: bold ?? regular,
              )
            : null,
        header: (context) =>
            _buildHeader(
          organization:
              organization,
          logo: logo,
          title: title,
          generatedAt:
              generatedAt,
          regular: regular,
          bold: bold,
        ),
        footer: (context) =>
            pw.Container(
          margin:
              const pw.EdgeInsets.only(
            top: 8,
          ),
          padding:
              const pw.EdgeInsets.only(
            top: 5,
          ),
          decoration:
              const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(
                color:
                    PdfColors.grey300,
                width: 0.5,
              ),
            ),
          ),
          child: pw.Directionality(
            textDirection:
                pw.TextDirection.ltr,
            child: pw.Row(
              mainAxisAlignment:
                  pw.MainAxisAlignment
                      .spaceBetween,
              children: [
                pw.Text(
                  'صفحة ${context.pageNumber} من ${context.pagesCount}',
                  textDirection:
                      pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: regular,
                    fontSize: 8,
                    color:
                        PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  organization.shortName,
                  textDirection:
                      pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: regular,
                    fontSize: 8,
                    color:
                        PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  generatedAt,
                  textDirection:
                      pw.TextDirection.ltr,
                  style: pw.TextStyle(
                    font: regular,
                    fontSize: 8,
                    color:
                        PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
        ),
        build: (context) {
          final widgets =
              <pw.Widget>[];

          widgets.add(
            _buildSummaryCardsGrid(
              cards: cards,
              regular: regular,
              bold: bold,
            ),
          );

          for (final section
              in sections) {
            widgets.add(
              _buildSectionTitle(
                title: section.title,
                note: section.note,
                regular: regular,
                bold: bold,
              ),
            );

            final reordered =
                _reorderTable(
              headers:
                  section.headers,
              rows:
                  section.rows,
              totalsRow:
                  section.totalsRow,
            );

            if (reordered
                .headers
                .isNotEmpty) {
              widgets.add(
                _buildTable(
                  headers:
                      reordered.headers,
                  rows:
                      reordered.rows,
                  nameColumnIndex:
                      reordered.nameIndex,
                  regular: regular,
                  bold: bold,
                ),
              );
            }

            if (reordered
                    .totalsRow !=
                null) {
              widgets.add(
                _buildTotalsRow(
                  totalsRow:
                      reordered.totalsRow!,
                  regular: regular,
                  bold: bold,
                ),
              );
            }
          }

          widgets.add(
            _buildSignatures(
              organization:
                  organization,
              regular: regular,
              bold: bold,
            ),
          );

          return widgets;
        },
      ),
    );

    final bytes =
        await doc.save();

    final file =
        await _writeTempFile(
      fileName,
      bytes,
    );

    await Share.shareXFiles(
      [XFile(file.path)],
      text: title,
    );
  }

  // ============================================================
  // رأس خاص بلائحة المنتسبين المجمّعة.
  //
  // الصفحة الأولى:
  // شعار + عنوان + تاريخ + إجمالي.
  //
  // الصفحات التالية:
  // رأس مختصر فقط حتى تبقى مساحة أكبر للجداول.
  // ============================================================

  pw.Widget _buildGroupedListHeader({
    required _OrganizationInfo
        organization,
    required pw.ImageProvider? logo,
    required String title,
    required String generatedAt,
    required pw.Font? regular,
    required pw.Font? bold,
    required bool firstPage,
    required int totalMembers,
  }) {
    final titleStyle =
        pw.TextStyle(
      font: bold ?? regular,
      fontSize:
          firstPage ? 15 : 10,
      fontWeight:
          pw.FontWeight.bold,
    );

    final smallStyle =
        pw.TextStyle(
      font: regular,
      fontSize:
          firstPage ? 8 : 7,
      color:
          PdfColors.grey700,
    );

    if (!firstPage) {
      return pw.Container(
        margin:
            const pw.EdgeInsets.only(
          bottom: 6,
        ),
        child: pw.Row(
          textDirection:
              pw.TextDirection.ltr,
          mainAxisAlignment:
              pw.MainAxisAlignment
                  .spaceBetween,
          crossAxisAlignment:
              pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              generatedAt,
              textDirection:
                  pw.TextDirection.ltr,
              style: smallStyle,
            ),
            pw.Text(
              title,
              textDirection:
                  pw.TextDirection.rtl,
              textAlign:
                  pw.TextAlign.center,
              style: titleStyle,
            ),
            pw.SizedBox(
              width: 55,
            ),
          ],
        ),
      );
    }

    return pw.Container(
      margin:
          const pw.EdgeInsets.only(
        bottom: 8,
      ),
      child: pw.Column(
        children: [
          pw.Row(
            textDirection:
                pw.TextDirection.ltr,
            crossAxisAlignment:
                pw.CrossAxisAlignment
                    .center,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment:
                      pw.CrossAxisAlignment
                          .start,
                  children: [
                    pw.Text(
                      'تاريخ الإصدار: $generatedAt',
                      textDirection:
                          pw.TextDirection.rtl,
                      style: smallStyle,
                    ),
                    pw.SizedBox(
                      height: 2,
                    ),
                    pw.Text(
                      'إجمالي المنتسبين: $totalMembers',
                      textDirection:
                          pw.TextDirection.rtl,
                      style: smallStyle,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(
                width: 12,
              ),
              pw.Column(
                mainAxisSize:
                    pw.MainAxisSize.min,
                crossAxisAlignment:
                    pw.CrossAxisAlignment
                        .end,
                children: [
                  if (logo != null)
                    pw.Container(
                      width: 48,
                      height: 48,
                      child: pw.Image(
                        logo,
                        fit:
                            pw.BoxFit.contain,
                      ),
                    ),
                  pw.SizedBox(
                    height: 2,
                  ),
                  pw.Text(
                    title,
                    textDirection:
                        pw.TextDirection.rtl,
                    textAlign:
                        pw.TextAlign.right,
                    style: titleStyle,
                  ),
                  if (organization
                      .shortName
                      .isNotEmpty)
                    pw.Text(
                      organization
                          .shortName,
                      textDirection:
                          pw.TextDirection.rtl,
                      textAlign:
                          pw.TextAlign.right,
                      style: smallStyle,
                    ),
                ],
              ),
            ],
          ),
          pw.SizedBox(
            height: 5,
          ),
          pw.Container(
            height: 2.2,
            width: double.infinity,
            color:
                const PdfColor.fromInt(
              0xFF2E8B57,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // توقيعات خاصة بلائحة LISTE.pdf
  //
  // النموذج المرجعي يظهر:
  // - النقيب الجهوي
  // - أمين التنظيم
  //
  // ولا يظهر أمين المالية في نهاية هذه اللائحة.
  // ============================================================

  pw.Widget _buildGroupedListSignatures({
    required _OrganizationInfo
        organization,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    return pw.Container(
      margin:
          const pw.EdgeInsets.only(
        top: 14,
      ),
      padding:
          const pw.EdgeInsets.only(
        top: 8,
      ),
      child: pw.Row(
        textDirection:
            pw.TextDirection.ltr,
        crossAxisAlignment:
            pw.CrossAxisAlignment
                .start,
        children: [
          _buildSignature(
            role: 'النقيب الجهوي',
            name:
                organization
                        .regionalCaptain ??
                    '',
            regular: regular,
            bold: bold,
          ),
          pw.SizedBox(
            width: 35,
          ),
          _buildSignature(
            role: 'أمين التنظيم',
            name:
                organization
                        .organizationSecretary ??
                    '',
            regular: regular,
            bold: bold,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // لائحة مجمّعة حسب المؤسسة
  //
  // مهم:
  // لا يوجد kMaxRowsPerPage.
  // لا يوجد pw.NewPage().
  //
  // MultiPage هو المسؤول عن تقسيم الصفحات تلقائيًا.
  // ============================================================

  Future<void> exportPdfGroupedList({
    required String fileName,
    required String title,
    required List<
            ReportGroupedListSection>
        groups,
  }) async {
    final doc = pw.Document();

    final regular =
        await _tryLoadFont(
      'assets/fonts/arabic_regular.ttf',
    );

    final bold =
        await _tryLoadFont(
      'assets/fonts/arabic_bold.ttf',
    );

    final organization =
        await _loadOrganizationInfo();

    final logo =
        await _loadLogo();

    final now = DateTime.now();

    final generatedAt =
        _formatDateTime(now);

    final totalMembers =
        groups.fold<int>(
      0,
      (sum, group) =>
          sum + group.rows.length,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat:
            PdfPageFormat.a4,

        margin:
            const pw.EdgeInsets.fromLTRB(
          25,
          18,
          25,
          28,
        ),

        textDirection:
            pw.TextDirection.rtl,

        theme: regular != null
            ? pw.ThemeData.withFont(
                base: regular,
                bold: bold ?? regular,
              )
            : null,

        // ======================================================
        // لا يوجد NewPage() يدوي.
        //
        // MultiPage يقوم بإنشاء الصفحات عند الحاجة.
        // ======================================================

        header: (context) =>
            _buildGroupedListHeader(
          organization:
              organization,
          logo: logo,
          title: title,
          generatedAt:
              generatedAt,
          regular: regular,
          bold: bold,
          firstPage:
              context.pageNumber == 1,
          totalMembers:
              totalMembers,
        ),

        // ======================================================
        // تذييل خفيف حتى لا يأخذ مساحة كبيرة.
        // ======================================================

        footer: (context) =>
            pw.Container(
          margin:
              const pw.EdgeInsets.only(
            top: 5,
          ),
          padding:
              const pw.EdgeInsets.only(
            top: 4,
          ),
          decoration:
              const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(
                color:
                    PdfColors.grey300,
                width: 0.5,
              ),
            ),
          ),
          child: pw.Row(
            textDirection:
                pw.TextDirection.ltr,
            mainAxisAlignment:
                pw.MainAxisAlignment
                    .spaceBetween,
            children: [
              pw.Text(
                'تم إنشاء هذه اللائحة آليًا من نظام ${organization.shortName}',
                textDirection:
                    pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: regular,
                  fontSize: 7,
                  color:
                      PdfColors.grey600,
                ),
              ),
              pw.Text(
                '${context.pageNumber}/${context.pagesCount}',
                textDirection:
                    pw.TextDirection.ltr,
                style: pw.TextStyle(
                  font: regular,
                  fontSize: 7,
                  color:
                      PdfColors.grey600,
                ),
              ),
            ],
          ),
        ),

        build: (context) {
          final widgets =
              <pw.Widget>[];

          // ====================================================
          // المؤسسات
          // ====================================================

          for (final group
              in groups) {
            final headers = [
              'ملاحظات',
              'الهاتف',
              'رقم البطاقة',
              'الدليل',
              'الاسم',
              '#',
            ];

            final tableRows =
                <List<String>>[];

            for (
              var i = 0;
              i < group.rows.length;
              i++
            ) {
              final r =
                  group.rows[i];

              tableRows.add([
                r['notes'] ?? '',
                r['phone'] ?? '',
                r['cardNo'] ?? '',
                r['guide'] ?? '',
                r['name'] ?? '',
                '${i + 1}',
              ]);
            }

            final groupWidget =
                pw.Column(
              crossAxisAlignment:
                  pw.CrossAxisAlignment
                      .stretch,
              children: [
                // ----------------------------------------------
                // عنوان المؤسسة
                // ----------------------------------------------

                _buildGroupHeader(
                  title:
                      group.groupTitle,
                  count:
                      group.rows.length,
                  regular:
                      regular,
                  bold:
                      bold,
                ),

                // ----------------------------------------------
                // جدول المؤسسة
                // ----------------------------------------------

                _buildTable(
                  headers:
                      headers,
                  rows:
                      tableRows,
                  nameColumnIndex:
                      4,
                  regular:
                      regular,
                  bold:
                      bold,

                  // توزيع الأعمدة مطابق تقريبًا
                  // للنموذج المرجعي LISTE.pdf.
                  columnWidths:
                      const {
                    0: pw.FlexColumnWidth(
                      1.15,
                    ),
                    1: pw.FlexColumnWidth(
                      1.45,
                    ),
                    2: pw.FlexColumnWidth(
                      1.25,
                    ),
                    3: pw.FlexColumnWidth(
                      1.35,
                    ),
                    4: pw.FlexColumnWidth(
                      3.35,
                    ),
                    5: pw.FlexColumnWidth(
                      0.55,
                    ),
                  },
                ),

                const pw.SizedBox(
                  height: 7,
                ),
              ],
            );

            // ==================================================
            // إذا كانت المؤسسة صغيرة، نحافظ على عنوانها وجدولها
            // كوحدة واحدة إذا كانت هناك مساحة كافية.
            //
            // لا يتم إجبار الصفحة الجديدة يدويًا.
            // ==================================================

            if (group.rows.length <= 18) {
              widgets.add(
                pw.Inseparable(
                  child:
                      groupWidget,
                ),
              );
            } else {
              // إذا كانت المجموعة كبيرة جدًا، نسمح لـ MultiPage
              // بتقسيم الجدول طبيعيًا بين الصفحات.
              widgets.add(
                groupWidget,
              );
            }
          }

          // ====================================================
          // التوقيعات في نهاية اللائحة فقط.
          // ====================================================

          widgets.add(
            pw.Inseparable(
              child:
                  _buildGroupedListSignatures(
                organization:
                    organization,
                regular:
                    regular,
                bold:
                    bold,
              ),
            ),
          );

          return widgets;
        },
      ),
    );

    final bytes =
        await doc.save();

    final file =
        await _writeTempFile(
      fileName,
      bytes,
    );

    await Share.shareXFiles(
      [
        XFile(file.path),
      ],
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

  final String?
      organizationSecretary;

  final String?
      financeSecretary;

  final String?
      regionalCaptain;

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

  final int nameIndex;

  const _ReorderedTable({
    required this.headers,
    required this.rows,
    required this.totalsRow,
    required this.nameIndex,
  });
}

// =================================================================
// بطاقة ملخص واحدة
// =================================================================

class ReportSummaryCard {
  final String title;

  final String value;

  final String? subtitle;

  final PdfColor? accentColor;

  const ReportSummaryCard({
    required this.title,
    required this.value,
    this.subtitle,
    this.accentColor,
  });
}

// =================================================================
// قسم جدولي واحد ضمن تقرير متعدد الأقسام
// =================================================================

class ReportTableSection {
  final String title;

  final String? note;

  final List<String> headers;

  final List<List<String>> rows;

  final List<String>? totalsRow;

  const ReportTableSection({
    required this.title,
    this.note,
    required this.headers,
    required this.rows,
    this.totalsRow,
  });
}

// =================================================================
// قسم واحد ضمن لائحة مجمعة حسب المؤسسة
// =================================================================

class ReportGroupedListSection {
  final String groupTitle;

  final List<Map<String, String>>
      rows;

  const ReportGroupedListSection({
    required this.groupTitle,
    required this.rows,
  });
}
