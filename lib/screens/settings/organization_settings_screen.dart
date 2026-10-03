import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/database/app_database.dart';

class OrganizationSettingsScreen extends StatefulWidget {
  const OrganizationSettingsScreen({super.key});
  @override
  State<OrganizationSettingsScreen> createState() => _OrganizationSettingsScreenState();
}

class _OrganizationSettingsScreenState extends State<OrganizationSettingsScreen> {
  String? _path;
  bool _busy = true;
  bool _savingNames = false;

  final _orgSecretaryCtrl = TextEditingController();
  final _financeSecretaryCtrl = TextEditingController();
  final _regionalCaptainCtrl = TextEditingController();

  static const _kOrgSecretaryKey = 'organization_secretary_name';
  static const _kFinanceSecretaryKey = 'finance_secretary_name';
  static const _kRegionalCaptainKey = 'regional_captain_name';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _orgSecretaryCtrl.dispose();
    _financeSecretaryCtrl.dispose();
    _regionalCaptainCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final logoRows = await db.query('settings', where: 'setting_key = ?', whereArgs: ['org_logo_path']);
    final nameRows = await db.query('settings', where: 'setting_key IN (?, ?, ?)', whereArgs: [
      _kOrgSecretaryKey,
      _kFinanceSecretaryKey,
      _kRegionalCaptainKey,
    ]);
    final names = {for (final r in nameRows) r['setting_key'] as String: r['setting_value'] as String?};
    if (!mounted) return;
    setState(() {
      _path = logoRows.isEmpty ? null : logoRows.first['setting_value'] as String?;
      _orgSecretaryCtrl.text = names[_kOrgSecretaryKey] ?? '';
      _financeSecretaryCtrl.text = names[_kFinanceSecretaryKey] ?? '';
      _regionalCaptainCtrl.text = names[_kRegionalCaptainKey] ?? '';
      _busy = false;
    });
  }

  Future<void> _saveNames() async {
    setState(() => _savingNames = true);
    final db = await AppDatabase.instance.database;
    final entries = {
      _kOrgSecretaryKey: _orgSecretaryCtrl.text.trim(),
      _kFinanceSecretaryKey: _financeSecretaryCtrl.text.trim(),
      _kRegionalCaptainKey: _regionalCaptainCtrl.text.trim(),
    };
    for (final entry in entries.entries) {
      if (entry.value.isEmpty) {
        await db.delete('settings', where: 'setting_key = ?', whereArgs: [entry.key]);
      } else {
        await db.insert('settings', {'setting_key': entry.key, 'setting_value': entry.value}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    if (mounted) {
      setState(() => _savingNames = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ أسماء الموقّعين')));
    }
  }

  Future<void> _pick() async {
    final pck = await FilePicker.pickFiles(type: FileType.image, withData: false);
    if (pck.isEmpty || pck.single.path == null) return;
    setState(() => _busy = true);
    try {
      final src = File(pck.single.path!);
      final d = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(d.path, 'organization'));
      await dir.create(recursive: true);
      final ext = p.extension(src.path).isEmpty ? '.png' : p.extension(src.path);
      final target = File(p.join(dir.path, 'logo$ext'));
      await src.copy(target.path);
      final db = await AppDatabase.instance.database;
      await db.insert('settings', {'setting_key': 'org_logo_path', 'setting_value': target.path}, conflictAlgorithm: ConflictAlgorithm.replace);
      if (mounted) setState(() { _path = target.path; _busy = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ الشعار: $e')));
      }
    }
  }

  Future<void> _remove() async {
    final path = _path;
    final db = await AppDatabase.instance.database;
    await db.delete('settings', where: 'setting_key = ?', whereArgs: ['org_logo_path']);
    if (path != null) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    if (mounted) setState(() => _path = null);
  }

  @override
  Widget build(BuildContext context) {
    final has = _path != null && File(_path!).existsSync();
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات النقابة')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('الشعار', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                Center(
                  child: has
                      ? Image.file(File(_path!), width: 160, height: 160, fit: BoxFit.contain)
                      : const Icon(Icons.image_outlined, size: 100),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _pick,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(has ? 'تغيير الشعار' : 'اختيار الشعار'),
                  ),
                ),
                if (has)
                  OutlinedButton.icon(
                    onPressed: _remove,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('حذف الشعار'),
                  ),
                const Divider(height: 36),
                const Text('أسماء الموقّعين في التقارير واللوائح', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                const Text('تُستخدم هذه الأسماء في توقيعات كل التقارير الصادرة من التطبيق.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                TextField(
                  controller: _orgSecretaryCtrl,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: 'اسم أمين التنظيم', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _financeSecretaryCtrl,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: 'اسم أمين المالية', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _regionalCaptainCtrl,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: 'اسم النقيب الجهوي', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _savingNames ? null : _saveNames,
                    icon: _savingNames
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('حفظ الأسماء'),
                  ),
                ),
              ],
            ),
    );
  }
}
