/// إعدادات Supabase الخاصة بتطبيق TAM Mobile.
/// الـ publishable key مصمم أصلًا ليكون قابلًا للشحن داخل تطبيق العميل؛
/// لا تضع أبدًا Secret/Service Role key هنا.
class CloudConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bgimwyrnzujnnumdgpvi.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_t3STKPnfMORAsSe6cI9XDQ_yTJjyMbO',
  );
  static bool get enabled =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;
}
