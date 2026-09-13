/// أدوات تطبيع النص والتحليل — منقولة حرفيًا من الدوال sub_norm،
/// sub_header_key، sub_parse_amount، sub_extract_months،
/// sub_is_direct_exec، sub_card_fee_from_details،
/// sub_subscription_month_count الموجودة في subscription_import.php
/// الأصلي، حتى تُعطي نفس نتيجة المطابقة والتحليل بالضبط.
class CsvNormalizer {
  static String norm(String v) {
    var s = v.trim();
    s = s.replaceAll('\uFEFF', '');
    s = s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    s = s
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ٱ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');
    return s.toLowerCase();
  }

  static const Map<String, String> _headerMap = {
    'الاسم': 'name', 'اسم': 'name', 'اسم المنتسب': 'name',
    'الاسم الكامل': 'name', 'name': 'name',
    'الدليل المالي': 'guide', 'الدليل': 'guide', 'guide': 'guide',
    'financial guide': 'guide',
    'رقم البطاقة': 'card_no', 'رقم البطاقة النقابية': 'card_no',
    'البطاقة': 'card_no', 'card_no': 'card_no', 'card': 'card_no',
    'السنه': 'year', 'السنة': 'year', 'عام': 'year', 'year': 'year',
    'الدفعة': 'batch', 'دفعة': 'batch', 'batch': 'batch',
    'الرقم': 'source_no', 'رقم': 'source_no', 'no': 'source_no',
    'الشهر': 'month', 'month': 'month',
    'المبلغ': 'amount', 'المبلغ (mru)': 'amount', 'المبلغ mru': 'amount',
    'الاشتراك': 'amount', 'subscription': 'amount', 'amount': 'amount',
    'رسوم البطاقة': 'card_fee', 'card fee': 'card_fee', 'card_fee': 'card_fee',
    'طريقة الدفع': 'payment_method', 'payment method': 'payment_method',
    'تفاصيل الاشتراك': 'details', 'تفاصيل': 'details', 'details': 'details',
    'دفع مباشر للتنفيذي': 'direct_exec', 'direct executive': 'direct_exec',
    'صفحة المصدر': 'source_page', 'source page': 'source_page',
    'تاريخ الدفع': 'payment_date', 'التاريخ': 'payment_date',
    'payment date': 'payment_date', 'date': 'payment_date',
    'ملاحظات': 'notes', 'notes': 'notes',
  };

  static String headerKey(String header) => _headerMap[norm(header)] ?? '';

  static double parseAmount(String v) {
    var s = v.trim().replaceAll('\u00A0', '').replaceAll(' ', '').replaceAll(',', '');
    s = s.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (s.isEmpty) return 0;
    return double.tryParse(s) ?? 0;
  }

  static const Map<String, int> _monthNames = {
    'يناير': 1, 'فبراير': 2, 'مارس': 3, 'ابريل': 4, 'أبريل': 4,
    'مايو': 5, 'يونيو': 6, 'يوليو': 7, 'اغسطس': 8, 'أغسطس': 8,
    'سبتمبر': 9, 'اكتوبر': 10, 'أكتوبر': 10, 'نوفمبر': 11, 'ديسمبر': 12,
  };

  static List<int> extractMonths(String details) {
    final d = norm(details);
    final months = <int>{};
    _monthNames.forEach((name, num) {
      if (d.contains(norm(name))) months.add(num);
    });
    final matches = RegExp(r'شهر\s*(1[0-2]|[1-9])').allMatches(d);
    for (final m in matches) {
      final v = int.tryParse(m.group(1) ?? '');
      if (v != null) months.add(v);
    }
    return months.toList()..sort();
  }

  static bool isDirectExecutive(
      String directFlag, String method, String details) {
    final a = norm(directFlag);
    final b = norm(method);
    final c = norm(details);
    return a == 'نعم' ||
        b.contains(norm('المكتب التنفيذي')) ||
        (c.contains('مباشر') && c.contains('تنفيذي'));
  }

  static double cardFeeFromDetails(
      String details, double total, double configuredCard) {
    final card = configuredCard <= 0 ? 200.0 : configuredCard;
    final d = norm(details);
    if (d.contains(norm('بطاقة')) && total >= card) return card;
    return 0.0;
  }

  static int subscriptionMonthCount(
      String details, double subscriptionAmount, double monthly) {
    final m = monthly <= 0 ? 100 : monthly;
    final d = norm(details);

    final explicit = extractMonths(details);
    if (explicit.isNotEmpty) return explicit.length;

    if (d.contains(norm('سنة كاملة')) || d.contains(norm('سنه كامله'))) {
      return 12;
    }
    if (d.contains(norm('نصف السنة')) ||
        d.contains(norm('نصف السنه')) ||
        d.contains(norm('عن نصف السنه'))) {
      return 6;
    }
    if (d.contains(norm('بقية السنة')) || d.contains(norm('بقيه السنه'))) {
      return subscriptionAmount > 0
          ? (subscriptionAmount / m).round().clamp(1, 999)
          : 1;
    }

    const words = {
      'شهرين': 2,
      'ثلاثة اشهر': 3,
      'ثلاثه اشهر': 3,
      'اربعة اشهر': 4,
      'اربعه اشهر': 4,
      'خمسة أشهر': 5,
      'خمسه اشهر': 5,
      'شهر': 1,
    };
    for (final entry in words.entries) {
      if (d.contains(norm(entry.key))) return entry.value;
    }

    return subscriptionAmount > 0 ? (subscriptionAmount / m).round() : 0;
  }
}
