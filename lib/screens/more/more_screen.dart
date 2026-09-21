import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../models/app_role.dart';
import '../../services/permission_service.dart';
import '../../widgets/app_widgets.dart';
import '../auth_gate.dart';
import '../auth/change_password_screen.dart';
import '../institutions/institutions_list_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/backup_screen.dart';
import '../settings/member_import_screen.dart';
import '../settings/organization_settings_screen.dart';
import '../settings/sync_status_screen.dart';
import '../subscriptions/import_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  void _open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  @override
  Widget build(BuildContext context) {
    final role = PermissionService.role;
    final canReports = PermissionService.can(Permission.viewReports);
    final canInstitutions = PermissionService.can(Permission.manageInstitutions) ||
        PermissionService.can(Permission.editInstitutionStats);
    final canImport = PermissionService.can(Permission.importData);
    return Scaffold(
      appBar: AppBar(title: Text(role.label)),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 100), children: [
        if (canReports || canInstitutions) ...[
          AppSection(title: 'الإدارة', child: Card(child: Column(children: [
            if (canReports) _Item(icon: Icons.bar_chart_rounded, title: 'التقارير والتحليلات', subtitle: 'تقارير المنتسبين والمتأخرات والصندوق والمؤسسات', onTap: () => _open(context, const ReportsScreen())),
            if (canInstitutions) _Item(icon: Icons.apartment_rounded, title: 'المؤسسات', subtitle: 'إدارة المؤسسات والطاقم ونسب الانتساب', onTap: () => _open(context, const InstitutionsListScreen())),
          ]))),
        ],
        if (canImport) ...[
          const SizedBox(height: 8),
          AppSection(title: 'البيانات', child: Card(child: Column(children: [
            _Item(icon: Icons.group_add_rounded, title: 'استيراد المنتسبين', subtitle: 'إضافة قائمة من ملف CSV', onTap: () => _open(context, const MemberImportScreen())),
            _Item(icon: Icons.receipt_long_rounded, title: 'استيراد الاشتراكات', subtitle: 'استيراد الدفعات الحالية والتاريخية', onTap: () => _open(context, const ImportScreen())),
            _Item(icon: Icons.backup_rounded, title: 'النسخ الاحتياطي والاستعادة', subtitle: 'حماية قاعدة البيانات واستعادتها', onTap: () => _open(context, const BackupScreen())),
          ]))),
        ],
        const SizedBox(height: 8),
        if (PermissionService.can(Permission.viewReports))
          Card(child: _Item(icon: Icons.sync_rounded, title: 'المزامنة', subtitle: 'Supabase وOutbox وحالة العمليات المعلقة', onTap: () => _open(context, const SyncStatusScreen()))),
        const SizedBox(height: 8),
        Card(child: _Item(icon: Icons.lock_reset_rounded, title: 'تغيير كلمة المرور', subtitle: 'تحديث بيانات الدخول', onTap: () async {
          final user = PermissionService.currentUser;
          if (user != null) _open(context, ChangePasswordScreen(userId: user.id, isForced: false));
        })),
        const SizedBox(height: 8),
        Card(child: _Item(icon: Icons.logout_rounded, title: 'تسجيل الخروج', subtitle: 'إنهاء الجلسة الحالية', destructive: true, onTap: () async { await AuthService().logout(); if (context.mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthGate()), (route) => false); })),
        const SizedBox(height: 16),
        Center(child: Text('TAM Mobile • ${role.label}', style: Theme.of(context).textTheme.labelSmall)),
      ]),
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icon; final String title; final String? subtitle; final VoidCallback onTap; final bool destructive;
  const _Item({required this.icon, required this.title, this.subtitle, required this.onTap, this.destructive = false});
  @override
  Widget build(BuildContext context) { final scheme = Theme.of(context).colorScheme; final color = destructive ? scheme.error : scheme.primary; return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4), leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: destructive ? scheme.errorContainer : scheme.primaryContainer, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: destructive ? scheme.onErrorContainer : scheme.onPrimaryContainer)), title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: destructive ? color : null)), subtitle: subtitle == null ? null : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: Icon(Icons.chevron_left_rounded, color: scheme.onSurfaceVariant), onTap: onTap); }
}
