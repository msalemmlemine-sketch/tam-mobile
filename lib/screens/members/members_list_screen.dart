import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../repositories/member_repository.dart';
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
  bool _isLoading = false;
  bool _hasMore = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadMore();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    final results = await _repo.search(
      query: _query,
      limit: _pageSize,
      offset: _members.length,
    );
    setState(() {
      _members.addAll(results);
      _hasMore = results.length == _pageSize;
      _isLoading = false;
    });
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
      _members.clear();
      _hasMore = true;
    });
    _loadMore();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المنتسبون'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'بحث بالاسم، الدليل، رقم البطاقة أو الهاتف',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const MemberFormScreen()),
          );
          if (saved == true) _onSearchChanged(_query);
        },
        child: const Icon(Icons.add),
      ),
      body: _members.isEmpty && !_isLoading
          ? const Center(child: Text('لا يوجد منتسبون بعد'))
          : ListView.builder(
              controller: _scrollController,
              itemCount: _members.length + 1,
              itemBuilder: (context, index) {
                if (index == _members.length) {
                  return _hasMore
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : const SizedBox.shrink();
                }
                final member = _members[index];
                return ListTile(
                  leading:
                      CircleAvatar(child: Text(member.name.characters.first)),
                  title: Text(member.name),
                  subtitle: Text([
                    if (member.guide != null && member.guide!.isNotEmpty)
                      'الدليل: ${member.guide}',
                    if (member.phone != null && member.phone!.isNotEmpty)
                      member.phone!,
                  ].join(' • ')),
                  trailing: member.membershipStatus != 'active'
                      ? const Icon(Icons.info_outline, color: Colors.orange)
                      : null,
                  onTap: () async {
                    final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) =>
                            MemberDetailScreen(memberId: member.id!),
                      ),
                    );
                    if (changed == true) _onSearchChanged(_query);
                  },
                );
              },
            ),
    );
  }
}
