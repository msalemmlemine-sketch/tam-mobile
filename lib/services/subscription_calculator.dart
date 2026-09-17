/// منطق حساب مستحقات ومتأخرات الاشتراك — منقول حرفيًا من
/// subscriptions.php / member_account.php الأصليين، ومعزول هنا في
/// طبقة Business Logic واحدة حتى تتطابق النتيجة في كل مكان
/// (Dashboard / التقارير / تفاصيل المنتسب) كما اشتُرط.
///
/// هذه الدوال نقيّة (pure) — لا تتعامل مع قاعدة البيانات مباشرة،
/// بل تستقبل المدخلات الجاهزة من الـ Repositories، مما يجعلها
/// قابلة للاختبار بسهولة (انظر test/subscription_calculator_test.dart).
///
/// ⚠️ إصلاح دقة الفاصلة العائمة (2026-09):
/// كانت كل الحسابات التراكمية (الفرق بين المستحق والمدفوع، وتوزيع
/// الدفعات على الأشهر) تُجرى بنوع `double`. جمع/طرح مبالغ عشرية
/// متكررة عبر عشرات الدفعات يراكم أخطاء تقريب صغيرة (مثال:
/// 0.1 + 0.2 != 0.3 في IEEE-754)، مما قد يجعل شهرًا "شبه مسدد"
/// يظهر بمتبقٍ وهمي كـ 0.0000000001 أوقية بدل صفر تمامًا، فيُحسب
/// خطأً كمتأخر. الحل: كل قرارات "هل تمت التسوية بالكامل؟" ومطابقة
/// الدفعات (FIFO) تُجرى الآن حصريًا بأعداد صحيحة (int) تمثل أدنى
/// فئة نقدية معتمدة في هذا المشروع = الأوقية الواحدة (لا توجد كسور
/// أوقية متداولة عمليًا في اشتراكات النقابة). أي مبلغ عشري وارد من
/// واجهة قديمة يُقرَّب أولًا عبر [MoneyUtils.toMinorUnits] قبل أي
/// عملية حسابية، ولا تُستخدم القيم العشرية الأصلية إلا للعرض النهائي.
class MoneyUtils {
  const MoneyUtils._();

  /// يحوّل مبلغًا عشريًا (أوقية) إلى عدد صحيح من "أدنى فئة نقدية"
  /// (هنا: الأوقية نفسها، أي معامل التحويل = 1) بتقريب نصفي قياسي.
  /// عزل هذه النقطة في دالة واحدة يجعل رفع الدقة لاحقًا (مثلاً لو
  /// اعتُمد الخُمس/القرش رسميًا) تغييرًا في مكان واحد فقط.
  static int toMinorUnits(num amount) => amount.round();

  /// التحويل العكسي للعرض في الواجهات القديمة التي ما زالت تتوقع
  /// double (لا يُستخدم هذا الناتج في أي مقارنة أو قرار حسابي).
  static double toDisplayAmount(int minorUnits) => minorUnits.toDouble();
}

/// عنصر مستحق واحد (شهر واحد) يُمرَّر إلى مخصِّص الدفعات — يمثّل صف
/// من subscription_dues مع مجموع ما خُصِّص له مسبقًا من دفعات أخرى.
class DueLineItem {
  final Object id;
  final int amountDue;
  final int amountAlreadyPaid;

  const DueLineItem({
    required this.id,
    required this.amountDue,
    required this.amountAlreadyPaid,
  });

  int get openBalance {
    final open = amountDue - amountAlreadyPaid;
    return open < 0 ? 0 : open;
  }

  bool get isFullySettled => openBalance == 0;
}

/// نتيجة تخصيص جزء من مبلغ دفعة واحدة إلى مستحق (شهر) واحد.
class DueAllocation {
  final Object dueId;
  final int allocatedAmount;
  final bool isFullySettled;

  const DueAllocation({
    required this.dueId,
    required this.allocatedAmount,
    required this.isFullySettled,
  });
}

/// نتيجة تخصيص دفعة واحدة عبر عدة أشهر مستحقة وفق FIFO.
class PaymentAllocationResult {
  /// التخصيصات لكل شهر لُمِسّ من هذه الدفعة، مرتّبة من الأقدم للأحدث.
  final List<DueAllocation> allocations;

  /// أي جزء من مبلغ الدفعة لم يُستهلك بعد تغطية كل الأشهر المستحقة
  /// المُمرَّرة (يُحفظ عادة كدفعة مقدَّمة/جزئية للشهر التالي الذي لم
  /// يُنشأ بعد، أو يُرحَّل كرصيد إيجابي للمنتسب).
  final int unallocatedRemainder;

  /// إجمالي رصيد المتأخرات المتبقي على كل الأشهر المُمرَّرة بعد هذا
  /// التخصيص (لا يشمل أشهرًا مستقبلية لم تُنشأ بعد).
  final int remainingArrearsBalance;

  const PaymentAllocationResult({
    required this.allocations,
    required this.unallocatedRemainder,
    required this.remainingArrearsBalance,
  });
}

class SubscriptionCalculator {
  const SubscriptionCalculator();

  /// عدد الأشهر المستحقة على المنتسب منذ أول شهر يُفترض دفعه
  /// (firstDueDate) وحتى تاريخ المرجع (referenceDate) — أو حتى
  /// statusDate إن كان المنتسب غير نشط (توقف عن الاستحقاق).
  int monthsElapsed({
    required DateTime firstDueDate,
    required DateTime referenceDate,
    DateTime? statusDate,
    required bool isActive,
  }) {
    final effectiveEnd = (!isActive && statusDate != null)
        ? statusDate
        : referenceDate;
    if (effectiveEnd.isBefore(firstDueDate)) return 0;

    final months = (effectiveEnd.year - firstDueDate.year) * 12 +
        (effectiveEnd.month - firstDueDate.month) +
        1; // شامل شهر البداية
    return months < 0 ? 0 : months;
  }

  /// إجمالي المستحق = عدد الأشهر × قيمة الاشتراك الشهري.
  /// (محفوظة كما هي للتوافق مع الشاشات القديمة التي ما زالت تستدعيها؛
  /// المسار المعتمد فعليًا لحساب المتأخرات هو subscription_dues عبر
  /// [allocatePayment] أدناه وليس هذا الضرب التقريبي).
  double totalDue({
    required int monthsElapsed,
    required double monthlyAmount,
  }) =>
      monthsElapsed * monthlyAmount;

  /// المتبقي على المنتسب = المستحق − المدفوع فعليًا (لا يقل عن صفر).
  double remainingBalance({
    required double totalDue,
    required double totalPaid,
  }) {
    final remaining = totalDue - totalPaid;
    return remaining < 0 ? 0.0 : remaining;
  }

  /// عدد الأشهر المغطاة فعليًا بالمدفوعات (يُستخدم لعرض "مسدد حتى
  /// شهر كذا" في تفاصيل المنتسب).
  int monthsCovered({
    required double totalPaid,
    required double monthlyAmount,
  }) {
    if (monthlyAmount <= 0) return 0;
    return (totalPaid / monthlyAmount).floor();
  }

  /// توزيع دفعة اشتراك واحدة بين التنفيذي والجهوي حسب النسب
  /// المعتمدة في subscription_settings. دفعة "مباشرة للتنفيذي"
  /// (directToExecutive) تذهب بالكامل للتنفيذي بلا توزيع.
  ({double executiveShare, double regionalShare}) splitPayment({
    required double subscriptionAmount,
    required bool directToExecutive,
    required double executiveSharePercent,
    required double regionalSharePercent,
  }) {
    if (directToExecutive) {
      return (executiveShare: subscriptionAmount, regionalShare: 0);
    }
    return (
      executiveShare: subscriptionAmount * (executiveSharePercent / 100),
      regionalShare: subscriptionAmount * (regionalSharePercent / 100),
    );
  }

  /// ==================== المخصِّص الرسمي الجديد (FIFO، أعداد صحيحة) ====================
  ///
  /// يخصّص مبلغ دفعة واردة (كاملة أو جزئية) على قائمة أشهر مستحقة،
  /// وفق قاعدة "الوارد أولاً يُصرف أولاً": يبدأ بأقدم شهر غير مسدد في
  /// [outstandingDuesOldestFirst] (يجب أن تكون القائمة مرتّبة تصاعديًا
  /// من الأقدم إلى الأحدث من طرف المستدعي — عادة عبر ORDER BY
  /// due_year, due_month في الاستعلام)، ويُغلق كل شهر بالكامل قبل
  /// الانتقال للتالي. أي متبقٍ من الدفعة بعد تغطية كل الأشهر
  /// المُمرَّرة يُعاد في [PaymentAllocationResult.unallocatedRemainder]
  /// ليقرر المستدعي إن كان يُحفظ كدفعة مقدَّمة لشهر لاحق أو كرصيد.
  ///
  /// كل الحسابات هنا أعداد صحيحة (int) — لا يوجد أي `double` في مسار
  /// اتخاذ القرار، تفاديًا لأخطاء تراكم الفاصلة العائمة الموصوفة أعلاه.
  PaymentAllocationResult allocatePayment({
    required int paymentAmount,
    required List<DueLineItem> outstandingDuesOldestFirst,
  }) {
    var remaining = paymentAmount < 0 ? 0 : paymentAmount;
    final allocations = <DueAllocation>[];
    var totalArrears = 0;

    for (final due in outstandingDuesOldestFirst) {
      final open = due.openBalance;
      if (open <= 0) continue; // شهر مغلق بالكامل مسبقًا — تخطَّه.

      if (remaining <= 0) {
        // لم يعد هناك ما يُخصَّص؛ هذا الشهر (وكل ما بعده) يبقى متأخرًا.
        totalArrears += open;
        continue;
      }

      final allocated = remaining < open ? remaining : open;
      remaining -= allocated;
      final stillOpen = open - allocated;
      totalArrears += stillOpen;

      allocations.add(DueAllocation(
        dueId: due.id,
        allocatedAmount: allocated,
        isFullySettled: stillOpen == 0,
      ));
    }

    return PaymentAllocationResult(
      allocations: allocations,
      unallocatedRemainder: remaining,
      remainingArrearsBalance: totalArrears,
    );
  }
}
