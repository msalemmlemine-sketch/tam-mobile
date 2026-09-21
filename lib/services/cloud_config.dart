/// إعدادات Supabase الخاصة بتطبيق TAM Mobile.
/// الـ publishable key مصمم أصلًا ليكون قابلًا للشحن داخل تطبيق العميل؛
/// لا تضع أبدًا Secret/Service Role key هنا.
class CloudConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );
  static bool get enabled =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;
}
