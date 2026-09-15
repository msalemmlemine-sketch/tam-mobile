import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../services/permission_service.dart';
import '../services/automated_reminder_service.dart';
import '../services/report_service.dart';
import 'fund/fund_screen.dart';
import 'home/dashboard_screen.dart';
import 'members/members_list_screen.dart';
import 'more/more_screen.dart';
import 'subscriptions/subscriptions_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _initializeAutomatedReminders();
  }

  Future<void> _initializeAutomatedReminders() async {
    final role = PermissionService.role;
    if (role != AppRole.organizationSecretary && role != AppRole.financeSecretary) {
      return;
    }

    final reminders = AutomatedReminderService.instance;
    await reminders.initialize();

    // في يومي 24 و26 نحسب المتأخرات الفعلية لحظة فتح التطبيق،
    // بدل الاعتماد على بيانات قديمة داخل إشعار مجدول.
    final overdue = await ReportService().overdueReport();
    await reminders.checkAndSendAutomatedReminders(overdue);
  }

  List<_Destination> get _destinations {
    final role = PermissionService.role;
    if (role == AppRole.financeSecretary) {
      return const [_Destination('الدفعات', Icons.receipt_long_outlined, Icons.receipt_long, SubscriptionsScreen())];
    }
    if (role == AppRole.regionalCaptain) {
      return const [_Destination('سحب اللوائح', Icons.download_outlined, Icons.download, MoreScreen())];
    }
    return const [
      _Destination('الرئيسية', Icons.dashboard_outlined, Icons.dashboard, DashboardScreen()),
      _Destination('المنتسبون', Icons.people_alt_outlined, Icons.people_alt, MembersListScreen()),
      _Destination('الاشتراكات', Icons.receipt_long_outlined, Icons.receipt_long, SubscriptionsScreen()),
      _Destination('الصندوق', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, FundScreen()),
      _Destination('المزيد', Icons.menu_rounded, Icons.menu_rounded, MoreScreen()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations;
    if (_index >= destinations.length) _index = 0;
    return Scaffold(
      body: IndexedStack(index: _index, children: [for (final d in destinations) d.screen]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in destinations) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
        ],
      ),
    );
  }
}

class _Destination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
  const _Destination(this.label, this.icon, this.selectedIcon, this.screen);
}
