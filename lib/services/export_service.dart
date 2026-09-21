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
/// - exportPdfReport: تقرير متعدد الأقسام (بطاقات ملخص + عدة
///   جداول بعناوين فرعية) لتقارير غنية مثل تقرير الصندوق.
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
        await _getSetting('org_name') ?? 'نقابة تحالف أساتذة موريتانيا';

    String shortName = await _getSetting('org_short') ?? 'تام';

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
          final value = rows.first['display_name']?.toString().trim();
          if (value != null && value.isNotEmpty) organizationSecretary = value;
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
          if (value != null && value.isNotEmpty) regionalCaptain = value;
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
          if (value != null && value.isNotEmpty) financeSecretary = value;
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
      if (path == null || path.isEmpty) return null;

      final file = File(path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;

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

    final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(csv)];

    final file = await _writeTempFile(fileName, bytes);

    await Share.shareXFiles([XFile(file.path)], text: fileName);
  }

  // ============================================================
  // اكتشاف عمود الاسم
  // ============================================================

  int _findNameColumn(List<String> headers) {
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
      if (candidates.contains(value)) return i;
    }

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
  // ============================================================

  _ReorderedTable _reorderTable({
    required List<String> headers,
    required List<List<String>> rows,
    List<String>? totalsRow,
  }) {
    final nameIndex = _findNameColumn(headers);

    if (nameIndex < 0 || headers.length <= 1) {
      return _ReorderedTable(
        headers: List<String>.from(headers),
        rows: rows.map(List<String>.from).toList(),
        totalsRow: totalsRow == null ? null : List<String>.from(totalsRow),
        nameIndex: -1,
      );
    }

    final indexes = <int>[
      for (var i = 0; i < headers.length; i++)
        if (i != nameIndex) i,
      nameIndex,
    ];

    List<String> reorderRow(List<String> row) {
      return indexes.map((index) => index < row.length ? row[index] : '').toList();
    }

    return _ReorderedTable(
      headers: indexes.map((i) => headers[i]).toList(),
      rows: rows.map(reorderRow).toList(),
      totalsRow: totalsRow == null ? null : reorderRow(totalsRow),
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
    final font = header ? (bold ?? regular) : regular;

    final style = pw.TextStyle(
      font: font,
      fontSize: header ? 9.5 : 9,
      fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: isName ? pw.Alignment.centerRight : pw.Alignment.center,
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        textAlign: isName ? pw.TextAlign.right : pw.TextAlign.center,
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

    tableRows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE0F2EF)),
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

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];

      tableRows.add(
        pw.TableRow(
          decoration: rowIndex.isEven
              ? null
              : const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8FAFA)),
          children: [
            for (var i = 0; i < headers.length; i++)
              _tableCell(
                text: i
