enum AppRole {
  organizationSecretary,
  financeSecretary,
  regionalCaptain,
  administrator,
  member,
}

extension AppRoleX on AppRole {
  String get key => switch (this) {
        AppRole.organizationSecretary => 'organization_secretary',
        AppRole.financeSecretary => 'finance_secretary',
        AppRole.regionalCaptain => 'regional_captain',
        AppRole.administrator => 'administrator',
        AppRole.member => 'member',
      };

  String get label => switch (this) {
        AppRole.organizationSecretary => 'أمين التنظيم',
        AppRole.financeSecretary => 'أمين المالية',
        AppRole.regionalCaptain => 'النقيب الجهوي',
        AppRole.administrator => 'مدير النظام',
        AppRole.member => 'منتسب',
      };

  static AppRole fromKey(String? key) => switch (key) {
        'organization_secretary' => AppRole.organizationSecretary,
        'finance_secretary' => AppRole.financeSecretary,
        'regional_captain' => AppRole.regionalCaptain,
        'administrator' => AppRole.administrator,
        'member' => AppRole.member,
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
  manageFund,
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
          Permission.manageFund,
          Permission.exportLists,
          Permission.importData,
        }.contains(permission),
      AppRole.financeSecretary => const {
          Permission.addPayments,
          Permission.editPayments,
          Permission.viewReports,
          Permission.viewAnalytics,
          Permission.exportLists,
          Permission.manageFund,
        }.contains(permission),
      AppRole.regionalCaptain => const {
          Permission.viewReports,
          Permission.viewAnalytics,
          Permission.exportLists,
        }.contains(permission),
      AppRole.administrator => true,
      AppRole.member => false,
    };
  }
}
