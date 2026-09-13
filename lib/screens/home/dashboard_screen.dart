import 'package:flutter/material.dart';

import '../../repositories/district_repository.dart';
import '../../repositories/member_repository.dart';
import '../../services/fund_service.dart';

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
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final year = DateTime.now().year;
    final membersCount = await _memberRepo.countAll();
    final districts = await _districtRepo.getAll();
    final fundSummary = await _fundService.summaryForYear(year);

    return _DashboardData(
      membersCount: membersCount,
      districtsCount: districts.length,
      fundYear: year,
      fundOpening: fundSummary.openingBalance,
      fundIncome: fundSummary.income,
      fundExpenses: fundSummary.expenses,
      fundClosing: fundSummary.closingBalance,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('نقابة تحالف أساتذة موريتانيا')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_DashboardData>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.people,
                        label: 'المنتسبون',
                        value: '${data.membersCount}',
                      ),
                    ),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.map_outlined,
                        label: 'المقاطعات',
                        value: '${data.districtsCount}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('صندوق سنة ${data.fundYear}',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _FundLine('الرصيد الافتتاحي', data.fundOpening),
                        _FundLine('المداخيل (حصة الجهوي)', data.fundIncome,
                            positive: true),
                        _FundLine('المصاريف', data.fundExpenses,
                            positive: false),
                        const Divider(),
                        _FundLine('الرصيد الحالي', data.fundClosing,
                            bold: true),
                      ],
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

class _DashboardData {
  final int membersCount;
  final int districtsCount;
  final int fundYear;
  final double fundOpening;
  final double fundIncome;
  final double fundExpenses;
  final double fundClosing;

  _DashboardData({
    required this.membersCount,
    required this.districtsCount,
    required this.fundYear,
    required this.fundOpening,
    required this.fundIncome,
    required this.fundExpenses,
    required this.fundClosing,
  });
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _FundLine extends StatelessWidget {
  final String label;
  final double value;
  final bool? positive;
  final bool bold;

  const _FundLine(this.label, this.value, {this.positive, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final color = positive == null
        ? null
        : (positive! ? Colors.green.shade700 : Colors.red.shade700);
    final sign = positive == null ? '' : (positive! ? '+ ' : '- ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
          Text(
            '$sign${value.toStringAsFixed(0)} أوقية',
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
