/// إعدادات الاتصال بـ Supabase — تُقرأ حصرًا من متغيرات البيئة عند
/// البناء عبر `--dart-define`، ولا تُكتب أبدًا كنص صريح داخل الشيفرة
/// المصدرية (لا في هذا الملف ولا في أي ملف آخر)، تفاديًا لتسريب
/// روابط/مفاتيح الوصول إذا انتشرت الشيفرة أو رُفعت لمستودع عام.
///
/// طريقة البناء (مطابقة لما هو موثَّق في CLOUD_SETUP.md):
///   flutter build apk --release \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_PUBLISHABLE_KEY=eyJ...
///
/// بدون تمرير هاتين القيمتين، [enabled] تكون false ويعمل التطبيق في
/// وضع SQLite المحلي فقط (مثل ما كان عليه الحال دائمًا قبل هذا
/// التحديث)، فلا ينكسر أي بناء قديم لا يمرّر هذه المتغيرات.
class CloudConfig {
  static const url = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY', defaultValue: '');
  static bool get enabled => url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;
}
