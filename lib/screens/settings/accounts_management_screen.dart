import 'package:flutter/material.dart';

import '../../models/app_role.dart';
import '../../repositories/user_repository.dart';
import '../../services/admin_users_service.dart';
import '../../services/cloud_config.dart';
import '../../services/permission_service.dart';

/// شاشة إدارة الحسابات — محمية بصلاحية [Permission.manageSettings]،
/// أي المدير (administrator) فقط وفق RolePermissions الحالية.
///
/// ملاحظة تصميمية مهمة: في وضع السحابة (CloudConfig.enabled)، صف
/// `users` المحلي هو نسخة مخزَّنة (cache) من حساب Supabase الحقيقي؛
/// لذلك:
/// - "الحذف" يصبح "تعطيل" (is_active = 0) بدل حذف فعلي، لأن الحذف
///   الحقيقي من Supabase Auth يتطلب مفتاح service_role السري الذي
///   لا يمكن وضعه داخل التطبيق (قرار صريح مع المستخدم: الاقتصار على
///   التعطيل بدل نشر Edge Function حاليًا).
/// - "إعادة تعيين كلمة المرور" لحساب *آخر غير حسابك* غير متاحة في
///   وضع السحابة إطلاقًا (نفس سبب الحذف)، وأيضًا لا يمكن الاعتماد
///   على "استعادة عبر البريد" لأن أسماء المستخدمين هنا تُحوَّل إلى
///   بريد وهمي (user@tam.local) لا يستقبل رسائل حقيقية. الزر يظهر
///   معطّلاً مع توضيح بدل كسر الميزة بصمت.
class AccountsManagementScreen extends StatefulWidget {
  const AccountsManagementScreen({super.key});

  @override
  State<AccountsManagementScreen> createState() => _AccountsManagementScreenState();
}

class _AccountsManagementScreenState extends State<AccountsManagementScreen> {
  final _repo = UserRepository();
  final _admin = AdminUsersService();
  List<AppUser> _users = [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    if (!PermissionService.can(Permission.manageSettings)) {
      // حماية إضافية دفاعية — الوصول الطبيعي إلى هذه الشاشة أصلًا
      // محجوب من قائمة "المزيد" لغير المدير، لكن لا ضرر من تكرار
      // التحقق هنا تحسبًا لأي طريقة وصول أخرى مستقبلية.
      WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.of(context).pop());
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final users = await _repo.getAll();
    if (mounted) setState(() { _users = users; _busy = false; });
  }

  Future<void> _toggleActive(AppUser user) async {
    final wantActive = !user.isActive;

    if (CloudConfig.enabled && user.cloudUserId != null) {
      setState(() => _busy = true);
      final error = wantActive
          ? await _admin.enableUser(user.cloudUserId!)
          : await _admin.disableUser(user.cloudUserId!);
      if (error != null) {
        setState(() => _busy = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        }
        return;
      }
    }

    // تُحدَّث النسخة المحلية دومًا (سواء نجح استدعاء السحابة أو كان
    // التطبيق أصلًا في الوضع المحلي البحت) حتى تعكس الواجهة الحالة
    // الجديدة فورًا دون انتظار مزامنة لاحقة.
    await _repo.setActive(user.id, wantActive);
    await _load();
  }

  Future<void> _changeRole(AppUser user) async {
    final role = await showModalBottomSheet<AppRole>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final r in AppRole.values)
            ListTile(
              title: Text(r.label),
              trailing: user.role == r ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.of(context).pop(r),
            ),
        ]),
      ),
    );
    if (role == null || role == user.role) return;
    await _repo.updateRole(user.id, role);
    await _load();
  }

  Future<void> _resetPassword(AppUser user) async {
    final controller = TextEditingController();
    final newPassword = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('كلمة مرور جديدة لـ ${user.displayName}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة (6 أحرف على الأقل)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (newPassword == null || newPassword.length < 6) return;

    setState(() => _busy = true);

    if (CloudConfig.enabled && user.cloudUserId != null) {
      final error = await _admin.resetPassword(user.cloudUserId!, newPassword);
      setState(() => _busy = false);
      if (error != null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        return;
      }
    } else {
      await _repo.updateLocalPassword(user.id, newPassword);
      setState(() => _busy = false);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تغيير كلمة مرور ${user.displayName}. أبلغه بها.')),
      );
    }
  }

  Future<void> _deleteOrDisable(AppUser user) async {
    final isCloudUser = CloudConfig.enabled && user.cloudUserId != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الحساب نهائيًا؟'),
        content: const Text('سيُحذف الحساب نهائيًا (بما فيه بيانات الدخول) ولا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('حذف نهائيًا'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);

    if (isCloudUser) {
      final error = await _admin.deleteUser(user.cloudUserId!);
      if (error != null) {
        setState(() => _busy = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        return;
      }
    }

    await _repo.deleteLocalUser(user.id);
    await _load();
  }

  Future<void> _createAccount() async {
    final usernameController = TextEditingController();
    final displayNameController = TextEditingController();
    final passwordController = TextEditingController();
    AppRole selectedRole = AppRole.organizationSecretary;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('حساب جديد', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(controller: usernameController, decoration: const InputDecoration(labelText: 'اسم المستخدم', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: displayNameController, decoration: const InputDecoration(labelText: 'الاسم الظاهر', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: passwordController, decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              DropdownButtonFormField<AppRole>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: 'الدور', border: OutlineInputBorder()),
                items: [for (final r in AppRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
                onChanged: (r) => setSheetState(() => selectedRole = r ?? selectedRole),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('إنشاء الحساب'),
              ),
            ],
          ),
        ),
      ),
    );

    if (created != true) return;
    final username = usernameController.text.trim();
    final displayName = displayNameController.text.trim();
    final password = passwordController.text.trim();
    if (username.isEmpty || displayName.isEmpty || password.length < 4) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يلزم اسم مستخدم واسم ظاهر وكلمة مرور من 4 أحرف على الأقل')),
        );
      }
      return;
    }
    try {
      if (CloudConfig.enabled) {
        final email = username.contains('@') ? username : '$username@tam.local';
        final error = await _admin.createUser(
          email: email,
          password: password,
          username: username,
          displayName: displayName,
          role: selectedRole.key,
        );
        if (error != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
          }
          return;
        }
      } else {
        await _repo.createLocalUser(
          username: username,
          password: password,
          displayName: displayName,
          role: selectedRole,
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إنشاء الحساب — ربما اسم المستخدم مستخدم مسبقًا. ($e)')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الحسابات'),
        actions: [IconButton(onPressed: _createAccount, icon: const Icon(Icons.person_add_alt_1_rounded))],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: _users.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final user = _users[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: user.isActive
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.errorContainer,
                        child: Icon(user.isActive ? Icons.person_rounded : Icons.person_off_rounded),
                      ),
                      title: Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${user.username} • ${user.role.label}${user.isActive ? '' : ' • معطّل'}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          switch (action) {
                            case 'role': _changeRole(user); break;
                            case 'toggle': _toggleActive(user); break;
                            case 'password': _resetPassword(user); break;
                            case 'delete': _deleteOrDisable(user); break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'role', child: Text('تعديل الدور')),
                          PopupMenuItem(value: 'toggle', child: Text(user.isActive ? 'تعطيل' : 'تفعيل')),
                          const PopupMenuItem(value: 'password', child: Text('إعادة تعيين كلمة المرور')),
                          const PopupMenuDivider(),
                          const PopupMenuItem(value: 'delete', child: Text('حذف', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
