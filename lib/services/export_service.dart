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

class ExportService {
  // ============================================================
  // ثوابت التصميم والألوان الرسمية
  // ============================================================
  static const PdfColor primaryColor = PdfColor.fromInt(0xFF0D5344);
  static const PdfColor tableHeaderColor = PdfColor.fromInt(0xFFE2EFEA);
  static const PdfColor alternateRowColor = PdfColor.fromInt(0xFFF9FBFA);
  static const PdfColor borderColor = PdfColor.fromInt(0xFFD1DCD6);

  // ============================================================
  // الملفات المؤقتة
  // ============================================================

  Future<File> _writeTempFile(String fileName, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final safeName = _safeFileName(fileName);
    final file = File(p.join(dir.path, safeName));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _safeFileName(String fileName) {
    return fileName
        .replaceAll(RegExp(r'[<>:"/\|?*]'), '')
        .trim();
  }

  // ============================================================
  // تحميل الخطوط
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
  // قراءة الإعدادات
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

  Future<String?> _getFirstSetting(List<String> keys) async {
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

    String? organizationSecretary = await _getFirstSetting([
      'organization_secretary_name',
      'org_secretary_name',
      'secretary_name',
    ]);

    String? regionalCaptain = await _getFirstSetting([
      'regional_captain_name',
      'captain_name',
      'regional_captain',
    ]);

    String? financeSecretary = await _getFirstSetting([
      'finance_secretary_name',
      'org_finance_secretary_name',
      'finance_name',
    ]);

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
          final value =
              rows.first['display_name']?.toString().trim();

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
          final value =
              rows.first['display_name']?.toString().trim();

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
          final value =
              rows.first['display_name']?.toString().trim();

          if (value != null && value.isNotEmpty) {
            financeSecretary = value;
          }
        }
      }
    } catch (_) {}

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

      if (path != null && path.isNotEmpty) {
        final file = File(path);

        if (await file.exists()) {
          final bytes = await file.readAsBytes();

          if (bytes.isNotEmpty) {
            return pw.MemoryImage(bytes);
          }
        }
      }
    } catch (_) {}

    try {
      final data =
          await rootBundle.load('assets/images/default_logo.png');

      final bytes = data.buffer.asUint8List();

      if (bytes.isNotEmpty) {
        return pw.MemoryImage(bytes);
      }
    } catch (_) {}

    return null;
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
  // تنظيف نصوص الخلايا
  // ============================================================

  String _cleanCellText(dynamic text) {
    if (text == null) return '-';

    final str = text.toString().trim();

    if (str.isEmpty ||
        str.toLowerCase() == 'مفقود' ||
        str.toLowerCase() == 'null') {
      return '-';
    }

    return str;
  }

  // ============================================================
  // ترويسة التقارير الرسمية
  // ============================================================

  pw.Widget _buildOfficialHeader({
    required _OrganizationInfo organization,
    required pw.ImageProvider? logo,
    required String title,
    required String generatedAt,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    final fullOrgTitle = organization.shortName.isNotEmpty
        ? '${organization.name} (${organization.shortName})'
        : organization.name;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment:
                pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment:
                pw.CrossAxisAlignment.center,
            children: [
              // اليمين: الشعار واسم المنظمة على سطر واحد
              pw.Row(
                crossAxisAlignment:
                    pw.CrossAxisAlignment.center,
                children: [
                  if (logo != null)
                    pw.Container(
                      width: 44,
                      height: 44,
                      margin:
                          const pw.EdgeInsets.only(left: 8),
                      child: pw.Image(logo),
                    ),
                  pw.Text(
                    fullOrgTitle,
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      font: bold ?? regular,
                      fontSize: 10.5,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),

              // اليسار: تاريخ الإصدار
              pw.Column(
                crossAxisAlignment:
                    pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'تاريخ الإصدار',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      font: bold ?? regular,
                      fontSize: 7.5,
                      color: PdfColors.grey600,
                    ),
                  ),
                  pw.Text(
                    generatedAt,
                    textDirection: pw.TextDirection.ltr,
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 8,
                      color: PdfColors.grey800,
                    ),
                  ),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 10),

          // عنوان التقرير في المنتصف
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(
              vertical: 6,
              horizontal: 12,
            ),
            decoration: const pw.BoxDecoration(
              color: primaryColor,
              borderRadius:
                  pw.BorderRadius.all(
                pw.Radius.circular(4),
              ),
            ),
            child: pw.Text(
              title,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: bold ?? regular,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // التذييل
  // ============================================================

  pw.Widget _buildFooter({
    required pw.Context context,
    required _OrganizationInfo organization,
    required pw.Font? regular,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            color: borderColor,
            width: 0.5,
          ),
        ),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'لائحة مسحوبة من منصة تحالف أساتذة موريتانيا - منسقية البراكنة',
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: regular,
              fontSize: 7,
              color: PdfColors.grey600,
            ),
          ),

          pw.SizedBox(height: 3),

          pw.Row(
            mainAxisAlignment:
                pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                organization.shortName,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: regular,
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Text(
                'صفحة ${context.pageNumber} من ${context.pagesCount}',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: regular,
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // التوقيعات
  // ============================================================

  pw.Widget _buildSignatures({
    required _OrganizationInfo organization,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 20),
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment:
            pw.MainAxisAlignment.spaceAround,
        crossAxisAlignment:
            pw.CrossAxisAlignment.start,
        children: [
          _buildSignatureBox(
            role: 'النقيب الجهوي',
            name: organization.regionalCaptain ?? '',
            regular: regular,
            bold: bold,
          ),
          _buildSignatureBox(
            role: 'أمين التنظيم',
            name: organization.organizationSecretary ?? '',
            regular: regular,
            bold: bold,
          ),
          _buildSignatureBox(
            role: 'أمين المالية',
            name: organization.financeSecretary ?? '',
            regular: regular,
            bold: bold,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSignatureBox({
    required String role,
    required String name,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment:
          pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          role,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(
            font: bold ?? regular,
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: primaryColor,
          ),
        ),

        pw.SizedBox(height: 24),

        pw.Text(
          name,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(
            font: bold ?? regular,
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
          ),
        ),

        pw.SizedBox(height: 2),

        pw.Container(
          width: 80,
          height: 0.5,
          color: PdfColors.grey500,
        ),
      ],
    );
  }

  // ============================================================
  // 1. لائحة مجمّعة حسب المؤسسة (exportPdfGroupedList)
  // ============================================================

  Future<void> exportPdfGroupedList({
    required String fileName,
    required String title,
    required List<ReportGroupedListSection> groups,
  }) async {
    final doc = pw.Document();

    final regular =
        await _tryLoadFont('assets/fonts/arabic_regular.ttf');

    final bold =
        await _tryLoadFont('assets/fonts/arabic_bold.ttf');

    final organization =
        await _loadOrganizationInfo();

    final logo =
        await _loadLogo();

    final now = DateTime.now();

    final generatedAt =
        _formatDateTime(now);

    // ترتيب عروض الأعمدة من اليسار إلى اليمين:
    // 0 (يسار): ملاحظات
    // 1: الهاتف
    // 2: رقم البطاقة
    // 3: الدليل المالي
    // 4: الاسم
    // 5 (يمين): #
    final columnWidths =
        <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1.4),
      1: const pw.FixedColumnWidth(74),
      2: const pw.FixedColumnWidth(58),
      3: const pw.FixedColumnWidth(68),
      4: const pw.FlexColumnWidth(5.0),
      5: const pw.FixedColumnWidth(26),
    };

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,

        margin: const pw.EdgeInsets.fromLTRB(
          25,
          25,
          25,
          25,
        ),

        textDirection: pw.TextDirection.rtl,

        theme: regular != null
            ? pw.ThemeData.withFont(
                base: regular,
                bold: bold ?? regular,
              )
            : null,

        // ======================================================
        // التعديل الأول:
        // ترويسة لائحة المنتسبين تظهر في الصفحة الأولى فقط
        // وتستمر البيانات في الصفحات التالية دون حذف.
        // ======================================================
        header: (context) {
          if (context.pageNumber == 1) {
            return _buildOfficialHeader(
              organization: organization,
              logo: logo,
              title: title,
              generatedAt: generatedAt,
              regular: regular,
              bold: bold,
            );
          }

          return pw.SizedBox();
        },

        footer: (context) => _buildFooter(
          context: context,
          organization: organization,
          regular: regular,
        ),

        build: (context) {
          final widgets = <pw.Widget>[];

          // ترتيب ترويسة الأعمدة مقلوبة من اليسار إلى اليمين
          // لتظهر في ورقة الطباعة:
          // # في اليمين ... ملاحظات في اليسار
          final headers = [
            'ملاحظات',
            'الهاتف',
            'رقم البطاقة',
            'الدليل المالي',
            'الاسم',
            '#',
          ];

          for (final group in groups) {
            final tableRows = <List<String>>[];

            for (
              var i = 0;
              i < group.rows.length;
              i++
            ) {
              final r = group.rows[i];

              tableRows.add([
                _cleanCellText(r['notes']),
                _cleanCellText(r['phone']),
                _cleanCellText(r['cardNo']),
                _cleanCellText(r['guide']),
                _cleanCellText(r['name']),
                '${i + 1}',
              ]);
            }

            // ==================================================
            // ترويسة المجموعة
            //
            // التعديل الثاني:
            // تبديل ترتيب المؤسسة وعدد المنتسبين
            // ==================================================
            final groupBar = pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(
                vertical: 5,
                horizontal: 10,
              ),

              decoration:
                  const pw.BoxDecoration(
                color: primaryColor,
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
                    pw.MainAxisAlignment.spaceBetween,

                crossAxisAlignment:
                    pw.CrossAxisAlignment.center,

                children: [
                  // اسم المؤسسة
                  pw.Text(
                    group.groupTitle,
                    textDirection:
                        pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      font: bold ?? regular,
                      fontSize: 9.5,
                      fontWeight:
                          pw.FontWeight.bold,
                      color:
                          PdfColors.white,
                    ),
                  ),

                  // عدد المنتسبين
                  pw.Container(
                    padding:
                        const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),

                    decoration:
                        pw.BoxDecoration(
                      color:
                          PdfColors.white,
                      borderRadius:
                          pw.BorderRadius.circular(
                        10,
                      ),
                    ),

                    child: pw.Text(
                      '${group.rows.length} منتسب',
                      textDirection:
                          pw.TextDirection.rtl,
                      style: pw.TextStyle(
                        font: bold ?? regular,
                        fontSize: 7.5,
                        fontWeight:
                            pw.FontWeight.bold,
                        color:
                            primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            );

            // بناء الجدول
            final table =
                pw.TableHelper.fromTextArray(
              border:
                  pw.TableBorder.all(
                color: borderColor,
                width: 0.5,
              ),

              columnWidths:
                  columnWidths,

              headers:
                  headers,

              data:
                  tableRows,

              headerStyle:
                  pw.TextStyle(
                font: bold ?? regular,
                fontSize: 8.5,
                fontWeight:
                    pw.FontWeight.bold,
                color:
                    primaryColor,
              ),

              headerDecoration:
                  const pw.BoxDecoration(
                color:
                    tableHeaderColor,
              ),

              headerAlignment:
                  pw.Alignment.center,

              headerHeight:
                  22,

              cellHeight:
                  20,

              cellStyle:
                  pw.TextStyle(
                font: regular,
                fontSize: 8,
                color:
                    PdfColors.black,
              ),

              cellAlignment:
                  pw.Alignment.center,

              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.center,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.center,
              },

              rowDecoration:
                  const pw.BoxDecoration(
                color:
                    PdfColors.white,
              ),

              oddRowDecoration:
                  const pw.BoxDecoration(
                color:
                    alternateRowColor,
              ),
            );

            widgets.add(
              pw.Container(
                margin:
                    const pw.EdgeInsets.only(
                  top: 8,
                  bottom: 6,
                ),

                child: pw.Column(
                  crossAxisAlignment:
                      pw.CrossAxisAlignment
                          .stretch,

                  children: [
                    groupBar,
                    table,
                  ],
                ),
              ),
            );
          }

          widgets.add(
            _buildSignatures(
              organization:
                  organization,
              regular:
                  regular,
              bold:
                  bold,
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
  // 2. تقرير جدول واحد (exportPdfTable)
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

    final now =
        DateTime.now();

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
          25,
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
            _buildOfficialHeader(
          organization:
              organization,
          logo:
              logo,
          title:
              title,
          generatedAt:
              generatedAt,
          regular:
              regular,
          bold:
              bold,
        ),

        footer: (context) =>
            _buildFooter(
          context:
              context,
          organization:
              organization,
          regular:
              regular,
        ),

        build: (context) {
          final widgets =
              <pw.Widget>[];

          if (reordered.headers.isNotEmpty) {
            widgets.add(
              _buildStandardTable(
                headers:
                    reordered.headers,
                rows:
                    reordered.rows,
                regular:
                    regular,
                bold:
                    bold,
              ),
            );
          }

          if (reordered.totalsRow != null) {
            widgets.add(
              _buildTotalsRow(
                totalsRow:
                    reordered.totalsRow!,
                regular:
                    regular,
                bold:
                    bold,
              ),
            );
          }

          widgets.add(
            _buildSignatures(
              organization:
                  organization,
              regular:
                  regular,
              bold:
                  bold,
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
  // 3. تقرير متعدد الأقسام (exportPdfReport)
  // ============================================================

  Future<void> exportPdfReport({
    required String fileName,
    required String title,
    List<ReportSummaryCard> cards = const [],
    required List<ReportTableSection> sections,
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

    final now =
        DateTime.now();

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
          25,
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
            _buildOfficialHeader(
          organization:
              organization,
          logo:
              logo,
          title:
              title,
          generatedAt:
              generatedAt,
          regular:
              regular,
          bold:
              bold,
        ),

        footer: (context) =>
            _buildFooter(
          context:
              context,
          organization:
              organization,
          regular:
              regular,
        ),

        build: (context) {
          final widgets =
              <pw.Widget>[];

          if (cards.isNotEmpty) {
            widgets.add(
              _buildSummaryCardsGrid(
                cards:
                    cards,
                regular:
                    regular,
                bold:
                    bold,
              ),
            );
          }

          for (final section
              in sections) {
            widgets.add(
              _buildSectionTitle(
                title:
                    section.title,
                note:
                    section.note,
                regular:
                    regular,
                bold:
                    bold,
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

            if (reordered.headers
                .isNotEmpty) {
              widgets.add(
                _buildStandardTable(
                  headers:
                      reordered.headers,
                  rows:
                      reordered.rows,
                  regular:
                      regular,
                  bold:
                      bold,
                ),
              );
            }

            if (reordered.totalsRow !=
                null) {
              widgets.add(
                _buildTotalsRow(
                  totalsRow:
                      reordered.totalsRow!,
                  regular:
                      regular,
                  bold:
                      bold,
                ),
              );
            }
          }

          widgets.add(
            _buildSignatures(
              organization:
                  organization,
              regular:
                  regular,
              bold:
                  bold,
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
  // دوال مساعدة للتقارير العامة
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
        rows:
            rows
                .map(
                  List<String>.from,
                )
                .toList(),
        totalsRow:
            totalsRow == null
                ? null
                : List<String>.from(
                    totalsRow,
                  ),
        nameIndex:
            -1,
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
      headers:
          indexes
              .map(
                (i) => headers[i],
              )
              .toList(),
      rows:
          rows
              .map(reorderRow)
              .toList(),
      totalsRow:
          totalsRow == null
              ? null
              : reorderRow(
                  totalsRow,
                ),
      nameIndex:
          indexes.length - 1,
    );
  }

  pw.Widget _buildStandardTable({
    required List<String> headers,
    required List<List<String>> rows,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    return pw.TableHelper.fromTextArray(
      border:
          pw.TableBorder.all(
        color:
            borderColor,
        width:
            0.5,
      ),

      headers:
          headers,

      data:
          rows,

      headerStyle:
          pw.TextStyle(
        font:
            bold ?? regular,
        fontSize:
            8.5,
        fontWeight:
            pw.FontWeight.bold,
        color:
            primaryColor,
      ),

      headerDecoration:
          const pw.BoxDecoration(
        color:
            tableHeaderColor,
      ),

      headerAlignment:
          pw.Alignment.center,

      headerHeight:
          22,

      cellHeight:
          20,

      cellStyle:
          pw.TextStyle(
        font:
            regular,
        fontSize:
            8,
        color:
            PdfColors.black,
      ),

      cellAlignment:
          pw.Alignment.center,

      rowDecoration:
          const pw.BoxDecoration(
        color:
            PdfColors.white,
      ),

      oddRowDecoration:
          const pw.BoxDecoration(
        color:
            alternateRowColor,
      ),
    );
  }

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
        vertical: 6,
        horizontal: 5,
      ),

      decoration:
          const pw.BoxDecoration(
        color:
            PdfColor.fromInt(
          0xFFECEFF1,
        ),
      ),

      child: pw.Row(
        children: [
          for (final cell in totalsRow)
            pw.Expanded(
              child: pw.Text(
                cell,
                textDirection:
                    pw.TextDirection.rtl,
                textAlign:
                    pw.TextAlign.center,
                style:
                    pw.TextStyle(
                  font:
                      bold ?? regular,
                  fontSize:
                      8.5,
                  fontWeight:
                      pw.FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _buildSummaryCard({
    required ReportSummaryCard card,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    return pw.Container(
      width:
          110,

      padding:
          const pw.EdgeInsets.symmetric(
        vertical: 8,
        horizontal: 8,
      ),

      decoration:
          pw.BoxDecoration(
        color:
            const PdfColor.fromInt(
          0xFFF7FAF9,
        ),
        border:
            pw.Border.all(
          color:
              borderColor,
          width:
              0.6,
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
            style:
                pw.TextStyle(
              font:
                  bold ?? regular,
              fontSize:
                  12,
              fontWeight:
                  pw.FontWeight.bold,
              color:
                  card.accentColor ??
                      primaryColor,
            ),
          ),

          pw.SizedBox(
            height: 3,
          ),

          pw.Text(
            card.title,
            textDirection:
                pw.TextDirection.rtl,
            textAlign:
                pw.TextAlign.center,
            style:
                pw.TextStyle(
              font:
                  regular,
              fontSize:
                  8,
            ),
          ),

          if (card.subtitle != null) ...[
            pw.SizedBox(
              height: 2,
            ),

            pw.Text(
              card.subtitle!,
              textDirection:
                  pw.TextDirection.rtl,
              textAlign:
                  pw.TextAlign.center,
              style:
                  pw.TextStyle(
                font:
                    regular,
                fontSize:
                    7,
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
        bottom: 12,
      ),

      child: pw.Wrap(
        alignment:
            pw.WrapAlignment.center,

        spacing:
            8,

        runSpacing:
            8,

        children: [
          for (final c in cards)
            _buildSummaryCard(
              card:
                  c,
              regular:
                  regular,
              bold:
                  bold,
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
        top: 12,
        bottom: 6,
      ),

      child: pw.Column(
        crossAxisAlignment:
            pw.CrossAxisAlignment.stretch,

        children: [
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(
              vertical: 4,
              horizontal: 8,
            ),

            decoration:
                const pw.BoxDecoration(
              color:
                  primaryColor,
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
              style:
                  pw.TextStyle(
                font:
                    bold ?? regular,
                fontSize:
                    10,
                fontWeight:
                    pw.FontWeight.bold,
                color:
                    PdfColors.white,
              ),
            ),
          ),

          if (note != null) ...[
            pw.SizedBox(
              height: 2,
            ),

            pw.Text(
              note,
              textDirection:
                  pw.TextDirection.rtl,
              textAlign:
                  pw.TextAlign.right,
              style:
                  pw.TextStyle(
                font:
                    regular,
                fontSize:
                    7.5,
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
  // 4. تصدير CSV
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
      if (totalsRow != null)
        totalsRow,
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
}

// =================================================================
// نماذج البيانات
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

class ReportGroupedListSection {
  final String groupTitle;
  final List<Map<String, String>> rows;

  const ReportGroupedListSection({
    required this.groupTitle,
    required this.rows,
  });
}.
