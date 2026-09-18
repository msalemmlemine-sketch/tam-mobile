/// أدوات تطبيع النص والتحليل — منقولة حرفيًا من الدوال sub_norm،
/// sub_header_key، sub_parse_amount، sub_extract_months،
/// sub_is_direct_exec، sub_card_fee_from_details،
/// sub_subscription_month_count الموجودة في subscription_import.php
/// الأصلي، حتى تُعطي نفس نتيجة المطابقة والتحليل بالضبط.
class CsvNormalizer {
  /// علامات التشكيل العربي (فتحة/ضمة/كسرة/سكون/شدة/تنوين/الوصلة...)
  /// النطاق Arabic diacritics: U+0610–U+061A و U+064B–U+065F و U+0670
  /// و U+06D6–U+06ED. إزالتها ضرورية قبل المطابقة لأن نفس الاسم قد
  /// يَرِد مُشكَّلًا في ملف ومجردًا من التشكيل في آخر (أو في قاعدة
  /// البيانات)، فيفشل التطابق الحرفي رغم أنه نفس الاسم فعليًا.
  static final RegExp _tashkeel = RegExp(
    r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]',
  );

  static String norm(String v) {
    var s = v.trim();
    // إزالة BOM (قد يتكرر داخل النص نفسه وليس فقط في أول الملف، إذا
    // أُعيد لصق محتوى من مصدر آخر يحمل BOM مضمّنًا).
    s = s.replaceAll('\uFEFF', '');
    s = s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    // إزالة التشكيل قبل أي معالجة أخرى.
    s = s.replaceAll(_tashkeel, '');
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

  /// ينظّف رقم هاتف موريتاني وارد من CSV بأي صيغة شائعة
  /// (مسافات، شرطات، أقواس، بادئة 00 أو + دولية، أو بدون بادئة أصلاً)
  /// ويحوّله إلى صيغة دولية موحّدة +222XXXXXXXX (8 أرقام محلية).
  /// يعيد القيمة الأصلية إن تعذّر التعرف عليها كرقم موريتاني صالح،
  /// بدل إسقاطها بصمت، حتى لا يُفقَد رقم صحيح بصيغة غير متوقعة.
  static String normalizePhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;

    // إزالة كل شيء عدا الأرقام و+ في البداية.
    var s = trimmed.replaceAll(RegExp(r'[^\d+]'), '');
    if (s.isEmpty) return trimmed;

    var hadPlus = s.startsWith('+');
    if (hadPlus) s = s.substring(1);

    // بادئة دولية بصيغة 00.
    if (!hadPlus && s.startsWith('00')) {
      s = s.substring(2);
      hadPlus = true; // كانت بادئة دولية صريحة، عاملها كذلك.
    }

    // رمز موريتانيا الدولي 222.
    if (s.startsWith('222') && s.length == 11) {
      s = s.substring(3);
    }

    // أرقام الهاتف المحلية في موريتانيا 8 خانات (تبدأ عادة بـ 2/3/4).
    if (RegExp(r'^\d{8}$').hasMatch(s)) {
      return '+222$s';
    }

    // لم يتطابق مع أي نمط موريتاني معروف — أعد الرقم كما ورد بعد
    // تنظيف بسيط للمسافات فقط، بدل حذفه أو تخمين تحويل خاطئ.
    return trimmed;
  }

  static const Map<String, String> _headerMap = {
    'الاسم': 'name', 'الإسم': 'name', 'اسم': 'name', 'اسم المنتسب': 'name',
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

  static const Map<String, String> _memberHeaderMap = {
    'الاسم': 'name', 'الإسم': 'name', 'اسم': 'name', 'اسم المنتسب': 'name',
    'الاسم الكامل': 'name', 'name': 'name',
    'المقاطعة': 'district', 'المقاطعه': 'district', 'الولاية': 'district', 'الولايه': 'district', 'district': 'district',
    'المؤسسة': 'institution', 'الموسسة': 'institution', 'الموسسه': 'institution', 'مكان العمل': 'institution',
    'institution': 'institution',
    'الدليل المالي': 'guide', 'الدليل': 'guide', 'guide': 'guide',
    'رقم البطاقة': 'card_no', 'البطاقة': 'card_no', 'card_no': 'card_no',
    'الهاتف': 'phone', 'رقم الهاتف': 'phone', 'phone': 'phone',
    'ملاحظات': 'notes', 'notes': 'notes',
  };

  static String headerKey(String header) => _headerMap[norm(header)] ?? '';

  static String memberHeaderKey(String header) =>
      _memberHeaderMap[norm(header)] ?? '';

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
