import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../models/import_models.dart';
import '../models/member.dart';
import '../models/subscription_payment.dart';
import '../repositories/member_repository.dart';
import '../repositories/subscription_repository.dart';
import 'import/csv_normalizer.dart';

/// استيراد سجلات اشتراكات قديمة من CSV — منقول من subscription_import.php
/// مع الحفاظ على نفس خطوتَي "تحليل ومعاينة" ثم "اعتماد الاستيراد"،
/// ونفس منطق المطابقة والتوزيع الشهري ومنع التكرار عبر row_hash.
class SubscriptionImporter {
  SubscriptionImporter({
    MemberRepository? memberRepository,
    SubscriptionRepository? subscriptionRepository,
  })  : _memberRepo = memberRepository ?? MemberRepository(),
        _subRepo = subscriptionRepository ?? SubscriptionRepository();

  final MemberRepository _memberRepo;
  final SubscriptionRepository _subRepo;

  /// ==================== المرحلة 1: تحليل ومعاينة ====================
  Future<ImportAnalysisResult> analyze(String filePath) async {
    try {
      final raw = await File(filePath).readAsBytes();
      String content;
      // إزالة BOM إن وُجد (UTF-8) — أبسط من محاولة اكتشاف كل
      // الترميزات كما في PHP، وكافٍ لملفات Excel/Sheets الشائعة.
      if (raw.length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) {
        content = utf8.decode(raw.sublist(3));
      } else {
        content = utf8.decode(raw, allowMalformed: true);
      }

      final firstLine = content.split(RegExp(r'[\r\n]')).firstWhere(
            (l) => l.isNotEmpty,
            orElse: () => '',
          );
      final commaCount = ','.allMatches(firstLine).length;
      final semiCount = ';'.allMatches(firstLine).length;
      final tabCount = '\t'.allMatches(firstLine).length;
      String delimiter = ',';
      if (semiCount > commaCount && semiCount > tabCount) delimiter = ';';
      if (tabCount > commaCount && tabCount > semiCount) delimiter = '\t';

      final table = const CsvToListConverter(eol: '\n')
          .convert(content.replaceAll('\r\n', '\n'), fieldDelimiter: delimiter);
      if (table.isEmpty) {
        return const ImportAnalysisResult(
            fileName: '', items: [], error: 'ملف CSV فارغ.');
      }

      final headers = table.first.map((h) => h.toString().trim()).toList();
      final mapped = <String, int>{};
      for (var i = 0; i < headers.length; i++) {
        final key = CsvNormalizer.headerKey(headers[i]);
        if (key.isNotEmpty) mapped[key] = i;
      }
      if (!mapped.containsKey('name')) {
        return ImportAnalysisResult(
          fileName: '',
          items: const [],
          error: 'لم يتم التعرف على عمود الاسم. الأعمدة المقروءة: ${headers.join(' | ')}',
        );
      }

      String get(List<dynamic> line, String key) {
        final idx = mapped[key];
        if (idx == null || idx >= line.length) return '';
        return line[idx].toString().trim();
      }

      final members = await _memberRepo.getAllForImportMatching();
      final settings = await _subRepo.getSettings();
      var cardSetting = settings['card_fee'] ?? 200.0;
      if (cardSetting <= 0) cardSetting = 200;

      final items = <ImportPreviewItem>[];
      for (var i = 1; i < table.length; i++) {
        final line = table[i];
        final isBlank = line.every((v) => v.toString().trim().isEmpty);
        if (isBlank) continue;

        final row = ImportRawRow(
          name: get(line, 'name'),
          guide: get(line, 'guide'),
          cardNo: get(line, 'card_no'),
          year: get(line, 'year'),
          batch: get(line, 'batch'),
          sourceNo: get(line, 'source_no'),
          amount: CsvNormalizer.parseAmount(get(line, 'amount')),
          paymentMethod: get(line, 'payment_method'),
          details: get(line, 'details'),
          directExecFlag: get(line, 'direct_exec'),
          sourcePage: get(line, 'source_page'),
          month: get(line, 'month'),
          paymentDate: get(line, 'payment_date'),
          notes: get(line, 'notes'),
          rowNo: i + 1,
        );

        final match = _matchMember(members, row.name, row.guide);
        final cardFee = CsvNormalizer.cardFeeFromDetails(
            row.details, row.amount, cardSetting);
        final subAmount = (row.amount - cardFee).clamp(0, double.infinity);
        final explicitMonths = CsvNormalizer.extractMonths(row.details);
        final direct = CsvNormalizer.isDirectExecutive(
            row.directExecFlag, row.paymentMethod, row.details);

        items.add(ImportPreviewItem(
          row: row,
          matchType: match.type,
          matchReason: match.reason,
          autoMatchedMember: match.member,
          cardFeeCalc: cardFee,
          subscriptionAmountCalc: subAmount.toDouble(),
          explicitMonths: explicitMonths,
          directExecCalc: direct,
        ));
      }

      return ImportAnalysisResult(fileName: filePath.split('/').last, items: items);
    } catch (e) {
      return ImportAnalysisResult(fileName: '', items: const [], error: e.toString());
    }
  }

  ({ImportMatchType type, String reason, Member? member}) _matchMember(
      List<Member> members, String name, String guide) {
    final nameN = CsvNormalizer.norm(name);
    final guideN = CsvNormalizer.norm(guide);

    if (nameN.isEmpty) {
      return (type: ImportMatchType.unmatched, reason: 'اسم فارغ', member: null);
    }

    final byName = <String, List<Member>>{};
    final byGuide = <String, List<Member>>{};
    for (final m in members) {
      final mn = CsvNormalizer.norm(m.name);
      byName.putIfAbsent(mn, () => []).add(m);
      if ((m.guide ?? '').trim().isNotEmpty) {
        final gn = CsvNormalizer.norm(m.guide!);
        byGuide.putIfAbsent(gn, () => []).add(m);
      }
    }

    if (guideN.isNotEmpty && byName.containsKey(nameN)) {
      final exact = byName[nameN]!
          .where((m) => CsvNormalizer.norm(m.guide ?? '') == guideN)
          .toList();
      if (exact.length == 1) {
        return (type: ImportMatchType.exact, reason: 'الاسم + الدليل المالي', member: exact.first);
      }
    }

    if (guideN.isNotEmpty && byGuide[guideN]?.length == 1) {
      return (type: ImportMatchType.guide, reason: 'الدليل المالي', member: byGuide[guideN]!.first);
    }

    if (byName[nameN]?.length == 1) {
      return (type: ImportMatchType.name, reason: 'الاسم', member: byName[nameN]!.first);
    }

    if ((byName[nameN]?.length ?? 0) > 1) {
      return (type: ImportMatchType.review, reason: 'الاسم متكرر في المنتسبين', member: null);
    }

    return (
      type: ImportMatchType.historical,
      reason: 'غير موجود في اللائحة الحالية — سجل تاريخي',
      member: null,
    );
  }

  /// ==================== المرحلة 2: اعتماد الاستيراد ====================
  ///
  /// [manualOverrides] خريطة رقم الصف (index في القائمة) إلى معرّف
  /// المنتسب المختار يدويًا — تطابق map[$rowKey] في PHP الأصلي.
  Future<ImportConfirmResult> confirm(
    List<ImportPreviewItem> items, {
    Map<int, int> manualOverrides = const {},
  }) async {
    final db = await AppDatabase.instance.database;
    final settings = await _subRepo.getSettings();
    var monthly = settings['monthly_amount'] ?? 100.0;
    if (monthly <= 0) monthly = 100;

    final batchId = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    var added = 0, historical = 0, review = 0;
    var total = 0.0, directTotal = 0.0;

    // تتبّع الأشهر المغطاة لكل منتسب/سنة — مطابق لمصفوفة $coverage
    // الأصلية: يبدأ من الشهر 1 ثم يستأنف من آخر شهر غُطِّي.
    final coverage = <String, int>{};

    try {
      await db.transaction((txn) async {
        for (var idx = 0; idx < items.length; idx++) {
          final item = items[idx];
          final override = manualOverrides[idx];

          Member? member = item.autoMatchedMember;
          String matchedBy = 'automatic';

          if (override != null && override > 0) {
            final rows = await txn.query('members', where: 'id = ?', whereArgs: [override]);
            if (rows.isEmpty) {
              review++;
              continue;
            }
            member = Member.fromMap(rows.first);
            matchedBy = 'manual';

            final alias = item.row.name.trim();
            if (alias.isNotEmpty) {
              await txn.insert(
                'subscription_name_aliases',
                {
                  'alias_name': alias,
                  'normalized_alias': CsvNormalizer.norm(alias),
                  'member_id': member.id,
                  'source_type': 'manual',
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          } else {
            if (item.matchType == ImportMatchType.review) {
              review++;
              continue;
            }
            if (item.matchType == ImportMatchType.historical) {
              member = null;
              matchedBy = 'historical';
            } else {
              matchedBy = 'automatic';
            }
          }

          final year = int.tryParse(item.row.year) ?? 0;
          final amount = item.row.amount;
          final card = item.cardFeeCalc;
          final sub = item.subscriptionAmountCalc;

          if (year < 2000 || amount <= 0) {
            review++;
            continue;
          }

          final memberId = member?.id;
          if (memberId == null) historical++;

          final officialName = member?.name ?? item.row.name;
          final guide = (member?.guide ?? item.row.guide).trim();
          final cardNo = (member?.cardNo ?? item.row.cardNo).trim();
          final sourceName = item.row.name;

          final notesParts = [
            item.row.notes,
            if (item.row.details.isNotEmpty) 'تفاصيل: ${item.row.details}',
            if (item.row.batch.isNotEmpty) 'الدفعة: ${item.row.batch}',
            if (item.row.sourcePage.isNotEmpty) 'صفحة المصدر: ${item.row.sourcePage}',
            if (item.row.paymentMethod.isNotEmpty) 'طريقة الدفع: ${item.row.paymentMethod}',
            if (item.directExecCalc) 'دفع مباشر للمكتب التنفيذي',
          ].where((s) => s.isNotEmpty).toList();
          final notes = notesParts.join(' | ');

          // تحديد الأشهر التي تغطيها هذه الدفعة.
          var months = <({int year, int month})>[];
          if (memberId != null && sub > 0) {
            if (item.explicitMonths.isNotEmpty) {
              months = item.explicitMonths.map((m) => (year: year, month: m)).toList();
            } else {
              final count = (sub / monthly).round();
              if (count > 0) {
                months = _allocateMonths(memberId, year, count, coverage);
              }
            }
          }

          final paymentMonth = months.length == 1 ? months.first.month : null;

          final hash = sha256
              .convert(utf8.encode([
                memberId,
                officialName,
                sourceName,
                year,
                paymentMonth,
                amount,
                card,
                item.row.batch,
                item.row.sourceNo,
                item.row.details,
              ].join('|')))
              .toString();

          // memberId=null مسموح به للسجلات التاريخية غير المرتبطة.
          final payment = SubscriptionPayment(
            memberId: memberId,
            memberName: officialName,
            financialGuide: guide.isNotEmpty ? guide : null,
            cardNo: cardNo.isNotEmpty ? cardNo : null,
            paymentYear: year,
            paymentMonth: paymentMonth,
            paymentDate: item.row.paymentDate.isNotEmpty ? item.row.paymentDate : null,
            subscriptionAmount: sub,
            cardFee: card,
            totalAmount: amount,
            source: 'استيراد CSV',
            sourceName: sourceName,
            matchedBy: matchedBy,
            directToExecutive: item.directExecCalc,
            importBatchId: batchId,
            rowHash: hash,
            notes: notes.isNotEmpty ? notes : null,
            createdAt: DateTime.now().toIso8601String(),
          );

          final insertedId = await _insertPaymentIgnoreDuplicates(txn, payment);
          if (insertedId) {
            added++;
            total += amount;
            if (item.directExecCalc) directTotal += amount;
          }

          if (memberId != null && sub > 0 && months.isNotEmpty) {
            for (final mm in months) {
              await txn.insert(
                'subscription_dues',
                {
                  'member_id': memberId,
                  'due_year': mm.year,
                  'due_month': mm.month,
                  'amount': monthly,
                  'created_at': DateTime.now().toIso8601String(),
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
          }
        }

        final matched = items
            .where((x) => [
                  ImportMatchType.exact,
                  ImportMatchType.guide,
                  ImportMatchType.name,
                  ImportMatchType.historical,
                ].contains(x.matchType))
            .length;
        final unmatched =
            items.where((x) => x.matchType == ImportMatchType.unmatched).length;

        await txn.insert('subscription_import_batches', {
          'batch_uuid': batchId,
          'file_name': null,
          'imported_rows': items.length,
          'matched_rows': matched,
          'review_rows': review,
          'unmatched_rows': unmatched,
          'total_amount': total,
          'created_at': DateTime.now().toIso8601String(),
        });
      });

      final unmatchedCount =
          items.where((x) => x.matchType == ImportMatchType.unmatched).length;

      return ImportConfirmResult(
        success: true,
        added: added,
        historical: historical,
        review: review,
        unmatched: unmatchedCount,
        total: total,
        directTotal: directTotal,
      );
    } catch (e) {
      return ImportConfirmResult(success: false, error: e.toString());
    }
  }

  /// يُدرج دفعة مع تجاهل التكرار (row_hash فريد) — يتحقق صراحةً من
  /// SELECT changes() بدل الاعتماد على قيمة العودة من insert()،
  /// لأن سلوكها مع ConflictAlgorithm.ignore غير موثّق بدقة كافية؛
  /// هذا يطابق تمامًا فحص rowCount()>0 في PHP الأصلي بعد INSERT IGNORE.
  Future<bool> _insertPaymentIgnoreDuplicates(
      Transaction txn, SubscriptionPayment payment) async {
    final map = payment.toMap();
    map.remove('id');
    final columns = map.keys.join(', ');
    final placeholders = List.filled(map.length, '?').join(', ');
    await txn.rawInsert(
      'INSERT OR IGNORE INTO subscription_payments ($columns) VALUES ($placeholders)',
      map.values.toList(),
    );
    final changes = Sqflite.firstIntValue(await txn.rawQuery('SELECT changes() AS c'));
    return (changes ?? 0) > 0;
  }

  /// يوزّع عدد الأشهر ابتداءً من أول شهر غير مغطى للمنتسب في تلك
  /// السنة — إن تجاوز الشهر 12 ينتقل للسنة التالية تلقائيًا، تمامًا
  /// كما في sub_allocate_months الأصلية.
  List<({int year, int month})> _allocateMonths(
      int memberId, int startYear, int count, Map<String, int> coverage) {
    final out = <({int year, int month})>[];
    if (count <= 0) return out;

    var year = startYear;
    final cursorKey = '$memberId:$year';
    coverage.putIfAbsent(cursorKey, () => 1);
    var month = coverage[cursorKey]!;

    var remaining = count;
    while (remaining > 0) {
      if (month > 12) {
        year++;
        month = 1;
        coverage.putIfAbsent('$memberId:$year', () => 1);
      }
      out.add((year: year, month: month));
      month++;
      remaining--;
    }
    coverage['$memberId:$year'] = month;
    return out;
  }
}
