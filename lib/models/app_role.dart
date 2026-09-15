enum AppRole {
  organizationSecretary,
  financeSecretary,
  regionalCaptain,
  administrator,
}

extension AppRoleX on AppRole {
  String get key => switch (this) {
        AppRole.organizationSecretary => 'organization_secretary',
        AppRole.financeSecretary => 'finance_secretary',
        AppRole.regionalCaptain => 'regional_captain',
        AppRole.administrator => 'administrator',
      };

  String get label => switch (this) {
        AppRole.organizationSecretary => 'أمين التنظيم',
        AppRole.financeSecretary => 'أمين المالية',
        AppRole.regionalCaptain => 'النقيب الجهوي',
        AppRole.administrator => 'مدير النظام',
      };

  static AppRole fromKey(String? key) => switch (key) {
        'organization_secretary' => AppRole.organizationSecretary,
        'finance_secretary' => AppRole.financeSecretary,
        'regional_captain' => AppRole.regionalCaptain,
        'administrator' => AppRole.administrator,
        _ => AppRole.organizationSecretary,
      };
}

enum Permission {
  manageMembers,
  freezeMembers,
  deleteMembers,
  viewReports,
  viewAnalytics,
  addPayments,
  editPayments,
  deletePayments,
  manageInstitutions,
  exportLists,
  importData,
  manageSettings,
}

class RolePermissions {
  static bool can(AppRole role, Permission permission) {
    if (role == AppRole.administrator) return true;
    return switch (role) {
      AppRole.organizationSecretary => const {
          Permission.manageMembers,
          Permission.freezeMembers,
          Permission.deleteMembers,
          Permission.viewReports,
          Permission.viewAnalytics,
          Permission.addPayments,
          Permission.editPayments,
          Permission.deletePayments,
          Permission.manageInstitutions,
          Permission.exportLists,
          Permission.importData,
        }.contains(permission),
      AppRole.financeSecretary => const {
          Permission.addPayments,
          Permission.editPayments,
        }.contains(permission),
      AppRole.regionalCaptain => permission == Permission.exportLists,
      AppRole.administrator => true,
    };
  }
}
