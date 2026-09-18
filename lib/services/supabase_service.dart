import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_config.dart';

class SupabaseService {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (!CloudConfig.enabled || _initialized) return;
    await Supabase.initialize(
      url: CloudConfig.url,
      publishableKey: CloudConfig.publishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    _initialized = true;
  }

  static SupabaseClient get client => Supabase.instance.client;
  static Session? get session => _initialized ? client.auth.currentSession : null;
  static User? get user => session?.user;
}
