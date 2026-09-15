import 'package:flutter/material.dart';

import '../../models/app_role.dart';
import '../../services/permission_service.dart';

import '../fund/fund_screen.dart';
import 'institutions_report_screen.dart';
import 'members_report_screen.dart';
import 'overdue_report_screen.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = PermissionService.role;
    if (role == AppRole.regionalCaptain) {
      return Scaffold(
        appBar: AppBar(title: const Text('سحب اللوائح')),
        body: ListView(children: [
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('لائحة المنتسبين'),
            subtitle: const Text('عرض وتصدير القائمة فقط'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MembersReportScreen())),
          ),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير والتحليلات')),
      body: ListView(children: [
        ListTile(leading: const Icon(Icons.people_outline), title: const Text('تقرير المنتسبين'), subtitle: const Text('قائمة كاملة قابلة للتصفية والتصدير'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MembersReportScreen()))),
        ListTile(leading: const Icon(Icons.warning_amber_outlined), title: const Text('تقرير المتأخرات'), subtitle: const Text('المنتسبون الذين عليهم رصيد متبقٍّ'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OverdueReportScreen()))),
        ListTile(leading: const Icon(Icons.business_outlined), title: const Text('تقرير المؤسسات والتحليل'), subtitle: const Text('الطاقم، TAM، النقابات الأخرى، غير النقابيين ونسب الانتساب'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InstitutionsReportScreen()))),
        ListTile(leading: const Icon(Icons.account_balance_wallet_outlined), title: const Text('تقرير الصندوق'), subtitle: const Text('الرصيد السنوي المرحّل + المصاريف'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FundScreen()))),
      ]),
    );
  }
}
