import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// يستدعي دالة الخادم admin-manage-users لتنفيذ عمليات الحسابات
/// الحساسة (تعطيل/تفعيل حقيقي، حذف نهائي، إعادة تعيين كلمة مرور،
/// إنشاء حساب) التي تتطلب مفتاح service_role السري. الدالة نفسها
/// تتحقق من صلاحية "مدير" للمتصل قبل التنفيذ — هذه الطبقة هنا مجرد
/// نداء HTTP، لا تحمل أي منطق أمان بحد ذاتها.
///
/// كل دالة تُرجع رسالة الخطأ كنص إن فشلت العملية، أو null عند النجاح
/// — لعرضها مباشرة في SnackBar/AlertDialog بالواجهة دون الحاجة لكتلة
/// try/catch متكررة في كل شاشة.
class AdminUsersService {
  Future<String?> _invoke(String action, Map<String, dynamic> body) async {
    try {
      final res = await SupabaseService.client.functions.invoke(
        'admin-manage-users',
        body: {'action': action, ...body},
      );
      final data = res.data;
      if (data is Map && data['error'] != null) {
        return data['error'].toString();
      }
      return null;
    } on FunctionException catch (e) {
      final data = e.details;
      if (data is Map && data['error'] != null) return data['error'].toString();
      return 'فشل استدعاء الخادم (${e.status})';
    } catch (e) {
      return 'تعذر الاتصال بالخادم: $e';
    }
  }

  Future<String?> disableUser(String cloudUserId) =>
      _invoke('disable_user', {'target_user_id': cloudUserId});

  Future<String?> enableUser(String cloudUserId) =>
      _invoke('enable_user', {'target_user_id': cloudUserId});

  Future<String?> deleteUser(String cloudUserId) =>
      _invoke('delete_user', {'target_user_id': cloudUserId});

  Future<String?> resetPassword(String cloudUserId, String newPassword) =>
      _invoke('reset_password', {'target_user_id': cloudUserId, 'new_password': newPassword});

  Future<String?> createUser({
    required String email,
    required String password,
    required String username,
    required String displayName,
    required String role,
    int? memberId,
  }) =>
      _invoke('create_user', {
        'email': email,
        'password': password,
        'username': username,
        'display_name': displayName,
        'role': role,
        'member_id': memberId,
      });
}
