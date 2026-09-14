import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../auth_gate.dart';
import '../auth/change_password_screen.dart';
import '../institutions/institutions_list_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/backup_screen.dart';
import '../settings/member_import_screen.dart';
import '../settings/organization_settings_screen.dart';
import '../subscriptions/import_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.bar_chart_outlined),
            title: const Text('التقارير'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReportsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.apartment_outlined),
            title: const Text('المؤسسات'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InstitutionsListScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.people_alt_outlined),
            title: const Text('استيراد المنتسبين (CSV)'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MemberImportScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('استيراد بيانات الاشتراكات (CSV)'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ImportScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('شعار النقابة'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OrganizationSettingsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('النسخ الاحتياطي والاستعادة'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BackupScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.lock_reset_outlined),
            title: const Text('تغيير كلمة المرور'),
            onTap: () {
              // ملاحظة: بما أن النظام بمستخدم واحد، لا حاجة لمعرفة
              // هوية المستخدم الحالي هنا — يُستدعى بمعرّف admin=1.
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ChangePasswordScreen(userId: 1, isForced: false),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('تسجيل الخروج', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await AuthService().logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthGate()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
