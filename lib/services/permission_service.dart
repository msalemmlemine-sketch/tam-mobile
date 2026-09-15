import '../models/app_role.dart';
import '../repositories/user_repository.dart';

class PermissionService {
  static AppUser? currentUser;

  static AppRole get role => currentUser?.role ?? AppRole.organizationSecretary;
  static bool can(Permission permission) => RolePermissions.can(role, permission);
  static String get roleLabel => role.label;
  static void require(Permission permission) { if (!can(permission)) throw StateError('لا تملك صلاحية تنفيذ هذه العملية'); }
}
