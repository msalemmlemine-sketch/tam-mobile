import 'package:flutter/material.dart';

import '../../repositories/district_repository.dart';
import '../../repositories/member_repository.dart';
import '../../services/fund_service.dart';
import '../../widgets/app_widgets.dart';
import '../members/member_form_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/member_import_screen.dart';
import '../subscriptions/subscriptions_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _memberRepo = MemberRepository();
  final _districtRepo = DistrictRepository();
  final _fundService = FundService();
  late Future<_DashboardData> _future;

  @override
  void initState() { super.initState(); _future = _load(); }

  Future<_DashboardData> _load() async {
    final year = DateTime.now().year;
    final membersCount = await _memberRepo.countAll();
    final districts = await _districtRepo.getAll();
    final fund = await _fundService.summaryForYear(year);
    return _DashboardData(membersCount: membersCount, districtsCount: districts.length, fundYear: year, fundOpening: fund.openingBalance, fundIncome: fund.income, fundExpenses: fund.expenses, fundClosing: fund.closingBalance);
  }

  Future<void> _refresh() async { setState(() => _future = _load()); await _future; }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12 ? 'صباح الخير' : 'مساء الخير';
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة التحكم'), actions: [IconButton(onPressed: _refresh, tooltip: 'تحديث', icon: const Icon(Icons.refresh_rounded))]),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_DashboardData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Center(child: Text('تعذر تحميل البيانات: ${snapshot.error}'));
            final data = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(24)),
                  child: Row(children: [
                    Container(width: 58, height: 58, padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), shape: BoxShape.circle), child: ClipOval(child: Image.asset('assets/icon.png', fit: BoxFit.cover))),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(greeting, style: TextStyle(color: scheme.onPrimary, fontSize: 14)), const SizedBox(height: 3), Text('إدارة تحالف أساتذة موريتانيا', style: TextStyle(color: scheme.onPrimary, fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('كل بياناتك في مكان واحد', style: TextStyle(color: scheme.onPrimary.withValues(alpha: .85), fontSize: 12))])),
                  ]),
                ),
                const SizedBox(height: 16),
                AppSection(title: 'ملخص المؤسسة', subtitle: 'الأرقام الحالية', child: Row(children: [Expanded(child: MetricCard(icon: Icons.people_alt_rounded, label: 'المنتسبون', value: '${data.membersCount}')), const SizedBox(width: 8), Expanded(child: MetricCard(icon: Icons.location_city_rounded, label: 'المقاطعات', value: '${data.districtsCount}'))])),
                const SizedBox(height: 8),
                AppSection(title: 'إجراءات سريعة', child: Row(children: [Expanded(child: _QuickAction(icon: Icons.person_add_alt_1, label: 'إضافة منتسب', onTap: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MemberFormScreen())); if (mounted) await _refresh(); })), const SizedBox(width: 8), Expanded(child: _QuickAction(icon: Icons.upload_file_rounded, label: 'استيراد CSV', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MemberImportScreen())))), const SizedBox(width: 8), Expanded(child: _QuickAction(icon: Icons.receipt_long_rounded, label: 'الاشتراكات', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionsScreen()))))])),
                const SizedBox(height: 8),
                AppSection(
                  title: 'الصندوق',
                  subtitle: 'السنة المالية ${data.fundYear}',
                  trailing: TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportsScreen())),
                    child: const Text('التقارير'),
                  ),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(children: [
                        _FundLine('الرصيد الافتتاحي', data.fundOpening),
                        _FundLine('المداخيل', data.fundIncome, positive: true),
                        _FundLine('المصاريف', data.fundExpenses, positive: false),
                        const Divider(height: 24),
                        _FundLine('الرصيد الحالي', data.fundClosing, bold: true),
                      ]),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Card(child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6), child: Column(children: [Icon(icon, size: 26, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 8), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))]))));
}

class _DashboardData { final int membersCount, districtsCount, fundYear; final double fundOpening, fundIncome, fundExpenses, fundClosing; _DashboardData({required this.membersCount, required this.districtsCount, required this.fundYear, required this.fundOpening, required this.fundIncome, required this.fundExpenses, required this.fundClosing}); }
class _FundLine extends StatelessWidget { final String label; final double value; final bool? positive; final bool bold; const _FundLine(this.label, this.value, {this.positive, this.bold = false}); @override Widget build(BuildContext context) { final scheme = Theme.of(context).colorScheme; final color = positive == null ? null : positive! ? scheme.primary : scheme.error; final sign = positive == null ? '' : positive! ? '+ ' : '- '; return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)), Text('$sign${value.toStringAsFixed(0)} أوقية', style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: color))])); } }
