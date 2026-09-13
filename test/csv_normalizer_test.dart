import 'package:flutter_test/flutter_test.dart';
import 'package:tam_mobile/services/import/csv_normalizer.dart';

void main() {
  group('CsvNormalizer.norm', () {
    test('يوحّد الألف والياء والتاء المربوطة ويحذف المسافات الزائدة', () {
      expect(CsvNormalizer.norm('  أحمد   ولد   محمدٱ  '), 'احمد ولد محمدا');
      expect(CsvNormalizer.norm('فاطمة'), 'فاطمه');
      expect(CsvNormalizer.norm('يحيى'), 'يحيي');
    });
  });

  group('CsvNormalizer.headerKey', () {
    test('يتعرف على أعمدة عربية وإنجليزية متعددة لنفس الحقل', () {
      expect(CsvNormalizer.headerKey('الاسم الكامل'), 'name');
      expect(CsvNormalizer.headerKey('Name'), 'name');
      expect(CsvNormalizer.headerKey('المبلغ (MRU)'), 'amount');
      expect(CsvNormalizer.headerKey('عمود غير معروف'), '');
    });
  });

  group('CsvNormalizer.parseAmount', () {
    test('يحذف الفواصل والمسافات ويحوّل لرقم', () {
      expect(CsvNormalizer.parseAmount('1,200'), 1200);
      expect(CsvNormalizer.parseAmount(' 600 '), 600);
      expect(CsvNormalizer.parseAmount(''), 0);
    });
  });

  group('CsvNormalizer.extractMonths', () {
    test('يستخرج أسماء الأشهر العربية المذكورة صراحة', () {
      expect(CsvNormalizer.extractMonths('اشتراك يناير وفبراير'), [1, 2]);
    });

    test('يستخرج صيغة "شهر 3"', () {
      expect(CsvNormalizer.extractMonths('شهر 3'), [3]);
    });

    test('يعيد قائمة فارغة إن لم تُذكر أشهر صراحة', () {
      expect(CsvNormalizer.extractMonths('اشتراك سنة كاملة'), isEmpty);
    });
  });

  group('CsvNormalizer.subscriptionMonthCount', () {
    test('1200 تعني سنة كاملة', () {
      expect(CsvNormalizer.subscriptionMonthCount('سنة كاملة', 1200, 100), 12);
    });

    test('600 بلا تفاصيل تعني 6 أشهر (600/100)', () {
      expect(CsvNormalizer.subscriptionMonthCount('', 600, 100), 6);
    });

    test('نصف السنة تعني 6 أشهر حتى لو اختلف المبلغ', () {
      expect(CsvNormalizer.subscriptionMonthCount('نصف السنة', 550, 100), 6);
    });
  });

  group('CsvNormalizer.isDirectExecutive', () {
    test('علم "نعم" الصريح يُفعِّل الدفع المباشر', () {
      expect(CsvNormalizer.isDirectExecutive('نعم', '', ''), isTrue);
    });

    test('ذكر "مباشر" و"تنفيذي" معًا في التفاصيل يُفعِّله', () {
      expect(CsvNormalizer.isDirectExecutive('', '', 'دفع مباشر للتنفيذي'), isTrue);
    });

    test('لا يُفعَّل بدون أي من الإشارات الثلاث', () {
      expect(CsvNormalizer.isDirectExecutive('لا', 'نقدًا', 'اشتراك عادي'), isFalse);
    });
  });
}
