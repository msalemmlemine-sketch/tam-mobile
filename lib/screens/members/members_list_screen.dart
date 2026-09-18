import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../models/app_role.dart';
import '../../services/permission_service.dart';
import '../../repositories/member_repository.dart';
import '../../widgets/app_widgets.dart';
import 'member_detail_screen.dart';
import 'member_form_screen.dart';

class MembersListScreen extends StatefulWidget {
  const MembersListScreen({super.key});
  @override
  State<MembersListScreen> createState() => _MembersListScreenState();
}

class _MembersListScreenState extends State<MembersListScreen> {
  final _repo = MemberRepository();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  static const _pageSize = 30;
  final List<Member> _members = [];
  bool _isLoading = false, _hasMore = true;
  String _query = '';
  int? _total;
  bool _includeArchived = false;

  @override
  void initState() {
    super.initState();
    _loadMore();
    _scrollController.addListener(() { if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 250) _loadMore(); });
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      final results = await _repo.search(query: _query, includeArchived: _includeArchived, limit: _pageSize, offset: _members.length);
      final total = await _repo.countSearch(query: _query, includeArchived: _includeArchived);
      if (!mounted) return;
      setState(() { _members.addAll(results); _total = total; _hasMore = _members.length < total; _isLoading = false; });
    } catch (_) { if (mounted) setState(() => _isLoading = false); }
  }

  void _toggleIncludeArchived() {
    setState(() { _includeArchived = !_includeArchived; _members.clear(); _hasMore = true; _total = null; });
    _loadMore();
  }

  void _onSearchChanged(String value) {
    setState(() { _query = value; _members.clear(); _hasMore = true; _total = null; });
    _loadMore();
  }

  Future<void> _refresh() async { setState(() { _members.clear(); _hasMore = true; _total = null; }); await _loadMore(); }
  @override
  void dispose() { _searchController.dispose(); _scrollController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canManage = PermissionService.can(Permission.manageMembers);
    final canSeeArchived = PermissionService.can(Permission.freezeMembers) || PermissionService.can(Permission.deleteMembers);
    return Scaffold(
      appBar: AppBar(title: const Text('المنتسبون'), actions: [
        if (canSeeArchived) IconButton(
          tooltip: _includeArchived ? 'إخفاء المؤرشفين' : 'عرض المؤرشفين أيضاً',
          icon: Icon(_includeArchived ? Icons.archive : Icons.archive_outlined),
          onPressed: _toggleIncludeArchived,
        ),
        if (_total != null) Padding(padding: const EdgeInsetsDirectional.only(end: 16), child: Center(child: Text('$_total', style: Theme.of(context).textTheme.titleMedium))),
      ]),
      floatingActionButton: canManage ? FloatingActionButton.extended(onPressed: () async { final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const MemberFormScreen())); if (saved == true) _onSearchChanged(_query); }, icon: const Icon(Icons.person_add_alt_1), label: const Text('إضافة منتسب')) : null,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), sliver: SliverToBoxAdapter(child: Card(child: Padding(padding: const EdgeInsets.all(12), child: TextField(controller: _searchController, onChanged: _onSearchChanged, decoration: InputDecoration(hintText: 'ابحث بالاسم أو الدليل أو البطاقة أو الهاتف', prefixIcon: const Icon(Icons.search), suffixIcon: _query.isEmpty ? null : IconButton(onPressed: () { _searchController.clear(); _onSearchChanged(''); }, icon: const Icon(Icons.clear)))))))),
            if (_total != null) SliverPadding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 4), sliver: SliverToBoxAdapter(child: Text(_query.isEmpty ? (_includeArchived ? 'جميع المنتسبين (مع المؤرشفين)' : 'جميع المنتسبين') : 'نتائج البحث', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)))),
            if (_members.isEmpty && !_isLoading)
              const SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Icons.people_outline, title: 'لا يوجد منتسبون', subtitle: 'أضف منتسبًا جديدًا أو استورد قائمة CSV.'))
            else
              SliverPadding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 100), sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) {
                if (index == _members.length) return _hasMore ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())) : const SizedBox(height: 20);
                final member = _members[index];
                final initial = member.name.trim().isEmpty ? '?' : member.name.trim().characters.first;
                return Card(child: InkWell(borderRadius: BorderRadius.circular(20), onTap: () async { final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => MemberDetailScreen(memberId: member.id!))); if (changed == true) _onSearchChanged(_query); }, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Row(children: [CircleAvatar(radius: 24, backgroundColor: scheme.primaryContainer, foregroundColor: scheme.onPrimaryContainer, child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w800))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(member.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text([if (member.guide?.isNotEmpty == true) 'الدليل ${member.guide}', if (member.phone?.isNotEmpty == true) member.phone!].join(' • '), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)])), const SizedBox(width: 8), if (member.isArchived) const Padding(padding: EdgeInsets.only(left: 6), child: Chip(label: Text('مؤرشف'), visualDensity: VisualDensity.compact)), StatusChip(member.membershipStatus)]))));
              }, childCount: _members.length + 1))),
          ],
        ),
      ),
    );
  }
}
