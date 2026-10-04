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
  static const PdfColor primaryColor = PdfColor.fromInt(0xFF0D5344);
  static const PdfColor tableHeaderColor = PdfColor.fromInt(0xFFE2EFEA);
  static const PdfColor alternateRowColor = PdfColor.fromInt(0xFFF9FBFA);
  static const PdfColor borderColor = PdfColor.fromInt(0xFFD1DCD6);

  Future<File> _writeTempFile(String fileName, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[<>:"/\|?*]'), '').trim();
    final file = File(p.join(dir.path, safeName));
    await file.writeAsBytes(bytes, flush: true);
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
      final val = rows.first['setting_value']?.toString().trim();
      return (val == null || val.isEmpty) ? null : val;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _getFirstSetting(List<String> keys) async {
    for (final key in keys) {
      final val = await _getSetting(key);
      if (val != null && val.isNotEmpty) return val;
    }
    return null;
  }

  Future<_OrganizationInfo> _loadOrganizationInfo() async {
    String orgName = await _getSetting('org_name') ?? 'تحالف أساتذة موريتانيا';
    orgName = orgName.replaceAll('(تام)', '').replaceAll('تام', '').trim();

    String shortName = await _getSetting('org_short') ?? 'APM';
    if (shortName == 'تام') shortName = 'APM';

    String? orgSec = await _getFirstSetting([
      'organization_secretary_name',
      'org_secretary_name',
      'secretary_name',
    ]);
    String? regCap = await _getFirstSetting([
      'regional_captain_name',
      'captain_name',
      'regional_captain',
    ]);
    String? finSec = await _getFirstSetting([
      'finance_secretary_name',
      'org_finance_secretary_name',
      'finance_name',
    ]);

    try {
      final db = await AppDatabase.instance.database;
      if (orgSec == null) {
        final r = await db.query('users', columns: ['display_name'], where: 'role = ?', whereArgs: ['organization_secretary'], limit: 1);
        if (r.isNotEmpty) orgSec = r.first['display_name']?.toString().trim();
      }
      if (regCap == null) {
        final r = await db.query('users', columns: ['display_name'], where: 'role = ?', whereArgs: ['regional_captain'], limit: 1);
        if (r.isNotEmpty) regCap = r.first['display_name']?.toString().trim();
      }
      if (finSec == null) {
        final r = await db.query('users', columns: ['display_name'], where: 'role = ?', whereArgs: ['finance_secretary'], limit: 1);
        if (r.isNotEmpty) finSec = r.first['display_name']?.toString().trim();
      }
    } catch (_) {}

    return _OrganizationInfo(
      name: orgName,
      shortName: shortName,
      organizationSecretary: orgSec,
      financeSecretary: finSec,
      regionalCaptain: regCap,
    );
  }

  Future<pw.ImageProvider?> _loadLogo() async {
    try {
      final path = await _getSetting('org_logo_path');
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          final b = await file.readAsBytes();
          if (b.isNotEmpty) return pw.MemoryImage(b);
        }
      }
    } catch (_) {}
    try {
      final data = await rootBundle.load('assets/images/default_logo.png');
      final b = data.buffer.asUint8List();
      if (b.isNotEmpty) return pw.MemoryImage(b);
    } catch (_) {}
    return null;
  }

  String _formatDateTime(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  pw.Widget _buildOfficialHeader({
    required _OrganizationInfo organization,
    required pw.ImageProvider? logo,
    required String title,
    required String generatedAt,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Row(
                children: [
                  if (logo != null)
                    pw.Container(
                      width: 40,
                      height: 40,
                      margin: const pw.EdgeInsets.only(left: 8),
                      child: pw.Image(logo),
                    ),
                  pw.Text(
                    '${organization.name} (${organization.shortName})',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      font: bold ?? regular,
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('تاريخ الإصدار', textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: regular, fontSize: 7, color: PdfColors.grey600)),
                  pw.Text(generatedAt, textDirection: pw.TextDirection.ltr, style: pw.TextStyle(font: regular, fontSize: 8, color: PdfColors.grey800)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            decoration: const pw.BoxDecoration(
              color: primaryColor,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              title,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: bold ?? regular,
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter({
    required pw.Context context,
    required _OrganizationInfo organization,
    required pw.Font? regular,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: borderColor, width: 0.5))),
      child: pw.Column(
        children: [
          pw.Text(
            'منصة تحالف أساتذة موريتانيا (APM) - تقرير رسمي استراتيجي معتمد',
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: regular, fontSize: 7, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(organization.shortName, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: regular, fontSize: 7.5, color: PdfColors.grey600)),
              pw.Text('صفحة ${context.pageNumber} من ${context.pagesCount}', textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: regular, fontSize: 7.5, color: PdfColors.grey700)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSignatures({
    required _OrganizationInfo organization,
    required pw.Font? regular,
    required pw.Font? bold,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 16),
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildSigItem('النقيب الجهوي', organization.regionalCaptain ?? '', regular, bold),
          _buildSigItem('أمين التنظيم', organization.organizationSecretary ?? '', regular, bold),
          _buildSigItem('أمين المالية', organization.financeSecretary ?? '', regular, bold),
        ],
      ),
    );
  }

  pw.Widget _buildSigItem(String role, String name, pw.Font? regular, pw.Font? bold) {
    return pw.Column(
      children: [
        pw.Text(role, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: bold ?? regular, fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: primaryColor)),
        pw.SizedBox(height: 22),
        pw.Text(name, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: bold ?? regular, fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Container(width: 80, height: 0.5, color: PdfColors.grey500),
      ],
    );
  }

  // ============================================================
  // التصدير الرئيسي مع لوحة المؤشرات والتحليل
  // ============================================================
  Future<void> exportPdfReport({
    required String fileName,
    required String title,
    List<ReportSummaryCard> cards = const [],
    ReportStrategicSection? strategicSection,
    required List<ReportTableSection> sections,
  }) async {
    final doc = pw.Document();
    final regular = await _tryLoadFont('assets/fonts/arabic_regular.ttf');
    final bold = await _tryLoadFont('assets/fonts/arabic_bold.ttf');
    final organization = await _loadOrganizationInfo();
    final logo = await _loadLogo();
    final generatedAt = _formatDateTime(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape, // استخدام الوضع العرضي لراحة جدول الـ 10 أعمدة
        margin: const pw.EdgeInsets.all(20),
        textDirection: pw.TextDirection.rtl,
        theme: regular != null ? pw.ThemeData.withFont(base: regular, bold: bold ?? regular) : null,
        header: (context) => context.pageNumber == 1
            ? _buildOfficialHeader(organization: organization, logo: logo, title: title, generatedAt: generatedAt, regular: regular, bold: bold)
            : pw.SizedBox(),
        footer: (context) => _buildFooter(context: context, organization: organization, regular: regular),
        build: (context) {
          final widgets = <pw.Widget>[];

          // 1. بطاقات المؤشرات القيادية
          if (cards.isNotEmpty) {
            widgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: cards.map((c) => pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      decoration: pw.BoxDecoration(
                        color: const PdfColor.fromInt(0xFFF7FAF9),
                        border: pw.Border.all(color: borderColor, width: 0.6),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Text(c.value, style: pw.TextStyle(font: bold ?? regular, fontSize: 11, fontWeight: pw.FontWeight.bold, color: c.accentColor ?? primaryColor)),
                          pw.SizedBox(height: 2),
                          pw.Text(c.title, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: regular, fontSize: 6.8)),
                        ],
                      ),
                    ),
                  )).toList(),
                ),
              ),
            );
          }

          // 2. التحليل والتوصيات
          if (strategicSection != null) {
            widgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFF2F7F4),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                  border: pw.Border.all(color: primaryColor, width: 0.7),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'الرؤية الاستراتيجية وخطة العمل الميدانية: ${strategicSection.title}',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(font: bold ?? regular, fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryColor),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      strategicSection.diagnosis,
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(font: regular, fontSize: 7.8, lineSpacing: 1.2),
                    ),
                    if (strategicSection.recommendations.isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Text('التوجيهات الميدانية:', textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: bold ?? regular, fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                      pw.SizedBox(height: 2),
                      ...strategicSection.recommendations.map(
                        (r) => pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('• ', textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: bold ?? regular, fontSize: 7.5, color: primaryColor)),
                            pw.Expanded(child: pw.Text(r, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: regular, fontSize: 7.5))),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          // 3. جدول البيانات (بدون عكس أو إعادة ترتيب عشوائية)
          for (final sec in sections) {
            widgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 4, top: 4),
                child: pw.Text(
                  sec.title,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: bold ?? regular, fontSize: 9, fontWeight: pw.FontWeight.bold, color: primaryColor),
                ),
              ),
            );

            widgets.add(
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: borderColor, width: 0.5),
                headers: sec.headers,
                data: sec.rows,
                headerStyle: pw.TextStyle(font: bold ?? regular, fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: primaryColor),
                headerDecoration: const pw.BoxDecoration(color: tableHeaderColor),
                headerAlignment: pw.Alignment.center,
                headerHeight: 20,
                cellHeight: 18,
                cellStyle: pw.TextStyle(font: regular, fontSize: 7),
                cellAlignment: pw.Alignment.center,
                oddRowDecoration: const pw.BoxDecoration(color: alternateRowColor),
              ),
            );
          }

          widgets.add(_buildSignatures(organization: organization, regular: regular, bold: bold));
          return widgets;
        },
      ),
    );

    final bytes = await doc.save();
    final file = await _writeTempFile(fileName, bytes);
    await Share.shareXFiles([XFile(file.path)], text: title);
  }

  // دعم التصدير المباشر لـ CSV
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
    final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(csv)];
    final file = await _writeTempFile(fileName, bytes);
    await Share.shareXFiles([XFile(file.path)], text: fileName);
  }
}

// النماذج
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

class ReportSummaryCard {
  final String title;
  final String value;
  final String? subtitle;
  final PdfColor? accentColor;
  const ReportSummaryCard({required this.title, required this.value, this.subtitle, this.accentColor});
}

class ReportStrategicSection {
  final String title;
  final String diagnosis;
  final List<String> recommendations;
  const ReportStrategicSection({required this.title, required this.diagnosis, this.recommendations = const []});
}

class ReportTableSection {
  final String title;
  final String? note;
  final List<String> headers;
  final List<List<String>> rows;
  final List<String>? totalsRow;
  const ReportTableSection({required this.title, this.note, required this.headers, required this.rows, this.totalsRow});
}
