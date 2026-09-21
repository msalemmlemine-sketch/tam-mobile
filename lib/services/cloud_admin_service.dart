import 'package:supabase_flutter/supabase_flutter.dart';
import 'cloud_config.dart';
import 'supabase_service.dart';

class CloudAdminService {
  const CloudAdminService();

  Future<String?> provisionMember({
    required int memberId,
    required String memberSyncUuid,
    required String displayName,
    required String username,
    required String temporaryPassword,
  }) async {
    if (!CloudConfig.enabled || SupabaseService.session == null) return null;
    final result = await SupabaseService.client.functions.invoke('provision-member', body: {
      'member_id': memberId,
      'member_sync_uuid': memberSyncUuid,
      'display_name': displayName,
      'username': username,
      'password': temporaryPassword,
    });
    if (result.data is Map && result.data['user_id'] != null) return result.data['user_id'].toString();
    return null;
  }

  Future<void> resetPassword({required String userId, required String newPassword}) async {
    if (!CloudConfig.enabled || SupabaseService.session == null) throw StateError('لا توجد جلسة Supabase.');
    final result = await SupabaseService.client.functions.invoke('admin-reset-password', body: {
      'user_id': userId,
      'new_password': newPassword,
    });
    if (result.data is Map && (result.data['error']?.toString().isNotEmpty ?? false)) {
      throw StateError(result.data['error'].toString());
    }
  }
}
