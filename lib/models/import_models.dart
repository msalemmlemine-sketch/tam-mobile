import '../models/member.dart';

enum ImportMatchType { exact, guide, name, review, historical, unmatched }

class ImportRawRow {
  final String name;
  final String guide;
  final String cardNo;
  final String year;
  final String batch;
  final String sourceNo;
  final double amount;
  final String paymentMethod;
  final String details;
  final String directExecFlag;
  final String sourcePage;
  final String month;
  final String paymentDate;
  final String notes;
  final int rowNo;

  const ImportRawRow({
    required this.name,
    required this.guide,
    required this.cardNo,
    required this.year,
    required this.batch,
    required this.sourceNo,
    required this.amount,
    required this.paymentMethod,
    required this.details,
    required this.directExecFlag,
    required this.sourcePage,
    required this.month,
    required this.paymentDate,
    required this.notes,
    required this.rowNo,
  });
}

/// عنصر معاينة جاهز للعرض والتعديل اليدوي قبل الاعتماد — يطابق
/// صف الجدول في preview الأصلي (subscription_import.php).
class ImportPreviewItem {
  final ImportRawRow row;
  final ImportMatchType matchType;
  final String matchReason;
  final Member? autoMatchedMember;
  final double cardFeeCalc;
  final double subscriptionAmountCalc;
  final List<int> explicitMonths;
  final bool directExecCalc;

  /// اختيار يدوي من المستخدم في شاشة المعاينة — يُهيَّأ فارغًا
  /// ويُعدَّل عبر الواجهة قبل الاعتماد.
  int? manualMemberId;

  ImportPreviewItem({
    required this.row,
    required this.matchType,
    required this.matchReason,
    required this.autoMatchedMember,
    required this.cardFeeCalc,
    required this.subscriptionAmountCalc,
    required this.explicitMonths,
    required this.directExecCalc,
  });

  bool get needsReview =>
      matchType == ImportMatchType.review ||
      matchType == ImportMatchType.unmatched;
}

class ImportAnalysisResult {
  final String fileName;
  final List<ImportPreviewItem> items;
  final String? error;

  const ImportAnalysisResult({required this.fileName, required this.items, this.error});
}

class ImportConfirmResult {
  final bool success;
  final int added;
  final int historical;
  final int review;
  final int unmatched;
  final double total;
  final double directTotal;
  final String? error;

  const ImportConfirmResult({
    required this.success,
    this.added = 0,
    this.historical = 0,
    this.review = 0,
    this.unmatched = 0,
    this.total = 0,
    this.directTotal = 0,
    this.error,
  });
}
