import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// طبقة الوصول لقاعدة بيانات SQLite المحلية للتطبيق.
///
/// تُطابق هذه القاعدة بنية قاعدة البيانات الأصلية MySQL
/// (tam_members_registry_v1/database/schema.sql +
/// subscription_accounting_patch.sql) مع إضافة جداول جديدة
/// خاصة بالصندوق السنوي المرحّل (fund_years / fund_opening_overrides)
/// التي لم تكن موجودة في النظام الأصلي، بناءً على قرار صريح
/// بإعادة بناء منطق الصندوق ليكون سنويًا بدل التراكمي.
///
/// الإصدار الحالي لقاعدة البيانات: 1
/// أي تعديل مستقبلي على البنية يجب أن يُضاف كدالة migration جديدة
/// داخل [_onUpgrade] برقم إصدار أعلى — لا يُعدَّل السكيما الحالية مباشرة.
class AppDatabase {
  AppDatabase._internal();
  static final AppDatabase instance = AppDatabase._internal();

  static const int schemaVersion = 2;
  static const String dbFileName = 'tam.db';

  Database? _db;

  /// مسار بديل يُستخدم فقط من اختبارات التكامل (test/*.dart) لتفادي
  /// الاعتماد على path_provider (الذي يحتاج قناة منصّة حقيقية غير
  /// متوفرة في `flutter test` العادي). لا يُستخدم في التطبيق الفعلي.
  static String? testDbPathOverride;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  /// المسار الكامل لملف قاعدة البيانات على الجهاز — يُستخدم من
  /// طبقة النسخ الاحتياطي (Backup) لأخذ نسخة من الملف مباشرة.
  Future<String> databaseFilePath() async {
    if (testDbPathOverride != null) return testDbPathOverride!;
    final dir = await getApplicationDocumentsDirectory();
    return join(dir.path, dbFileName);
  }

  Future<Database> _open() async {
    final path = await databaseFilePath();
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // ---- المستخدمون والإعدادات العامة ----
    batch.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        password_salt TEXT NOT NULL,
        display_name TEXT NOT NULL,
        must_change_password INTEGER NOT NULL DEFAULT 0,
        failed_attempts INTEGER NOT NULL DEFAULT 0,
        locked_until TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT
      )
    ''');

    // ---- المقاطعات والمؤسسات والمنتسبون ----
    batch.execute('''
      CREATE TABLE districts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE institutions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        district_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE (district_id, name),
        FOREIGN KEY (district_id) REFERENCES districts (id) ON DELETE RESTRICT
      )
    ''');

    batch.execute('''
      CREATE TABLE members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        district_id INTEGER NOT NULL,
        institution_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        guide TEXT,
        card_no TEXT,
        phone TEXT,
        notes TEXT,
        membership_status TEXT NOT NULL DEFAULT 'active',
        status_date TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (district_id) REFERENCES districts (id) ON DELETE RESTRICT,
        FOREIGN KEY (institution_id) REFERENCES institutions (id) ON DELETE RESTRICT
      )
    ''');
    batch.execute('CREATE INDEX idx_member_name ON members(name)');
    batch.execute('CREATE INDEX idx_member_guide ON members(guide)');
    batch.execute('CREATE INDEX idx_member_card ON members(card_no)');
    batch.execute('CREATE INDEX idx_member_phone ON members(phone)');
    batch.execute(
        'CREATE INDEX idx_member_institution ON members(institution_id)');

    // ---- وحدة الاشتراكات (كما في subscription_accounting_patch.sql) ----
    batch.execute('''
      CREATE TABLE subscription_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL DEFAULT '0'
      )
    ''');

    batch.execute('''
      CREATE TABLE subscription_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        member_id INTEGER,
        member_name TEXT,
        financial_guide TEXT,
        card_no TEXT,
        payment_year INTEGER NOT NULL,
        payment_month INTEGER,
        payment_date TEXT,
        subscription_amount REAL NOT NULL DEFAULT 0,
        card_fee REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL DEFAULT 0,
        source TEXT,
        source_name TEXT,
        matched_by TEXT,
        direct_to_executive INTEGER NOT NULL DEFAULT 0,
        import_batch_id TEXT,
        row_hash TEXT UNIQUE,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (member_id) REFERENCES members (id) ON DELETE CASCADE
      )
    ''');
    batch.execute(
        'CREATE INDEX idx_sp_member ON subscription_payments(member_id)');
    batch.execute(
        'CREATE INDEX idx_sp_period ON subscription_payments(payment_year, payment_month)');

    batch.execute('''
      CREATE TABLE subscription_dues (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        member_id INTEGER NOT NULL,
        due_year INTEGER NOT NULL,
        due_month INTEGER NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        UNIQUE (member_id, due_year, due_month),
        FOREIGN KEY (member_id) REFERENCES members (id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE membership_card_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        member_id INTEGER NOT NULL,
        member_name TEXT,
        financial_guide TEXT,
        card_no TEXT,
        payment_date TEXT,
        amount REAL NOT NULL DEFAULT 0,
        source TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (member_id) REFERENCES members (id) ON DELETE CASCADE
      )
    ''');
    batch.execute(
        'CREATE INDEX idx_mcp_member ON membership_card_payments(member_id)');

    batch.execute('''
      CREATE TABLE subscription_name_aliases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        alias_name TEXT NOT NULL,
        normalized_alias TEXT NOT NULL UNIQUE,
        member_id INTEGER NOT NULL,
        source_type TEXT NOT NULL DEFAULT 'manual',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (member_id) REFERENCES members (id) ON DELETE CASCADE
      )
    ''');
    batch.execute(
        'CREATE INDEX idx_alias_member ON subscription_name_aliases(member_id)');

    batch.execute('''
      CREATE TABLE subscription_import_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_uuid TEXT NOT NULL UNIQUE,
        file_name TEXT,
        imported_rows INTEGER NOT NULL DEFAULT 0,
        matched_rows INTEGER NOT NULL DEFAULT 0,
        review_rows INTEGER NOT NULL DEFAULT 0,
        unmatched_rows INTEGER NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE regional_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        expense_date TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        description TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // ---- الصندوق السنوي المرحّل (جديد — غير موجود في الأصل) ----
    // رصيد افتتاحي يدوي اختياري لسنة معينة (يُستخدم غالبًا لسنة
    // بداية استعمال التطبيق حين تكون الأرصدة السابقة غير مسجَّلة
    // كعمليات). أي سنة لاحقة تُحسب تلقائيًا: رصيدها الافتتاحي =
    // الرصيد الختامي للسنة السابقة، ولا حاجة لتخزينه.
    batch.execute('''
      CREATE TABLE fund_opening_overrides (
        year INTEGER PRIMARY KEY,
        amount REAL NOT NULL DEFAULT 0,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // سجل تدقيق مبسّط للعمليات الحساسة — جاهز للمراحل القادمة
    // (لا تربطه الشاشات الحالية بعد، سيُفعَّل مع شاشات الحذف/الاستعادة).
    batch.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        entity TEXT NOT NULL,
        entity_id INTEGER,
        details TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await batch.commit(noResult: true);

    await _seedDefaults(db);
  }

  Future<void> _seedDefaults(Database db) async {
    final now = DateTime.now().toIso8601String();

    await db.insert('settings', {
      'setting_key': 'org_name',
      'setting_value': 'نقابة تحالف أساتذة موريتانيا',
    });
    await db.insert('settings', {
      'setting_key': 'org_short',
      'setting_value': 'تام',
    });

    await db.insert('subscription_settings',
        {'setting_key': 'monthly_amount', 'setting_value': '100'});
    await db.insert('subscription_settings',
        {'setting_key': 'card_fee', 'setting_value': '200'});
    await db.insert('subscription_settings',
        {'setting_key': 'executive_share_percent', 'setting_value': '70'});
    await db.insert('subscription_settings',
        {'setting_key': 'regional_share_percent', 'setting_value': '30'});

    // مستخدم افتراضي — كلمة المرور الأولية: admin123
    // (مشفّرة هنا بنفس خوارزمية AuthService: sha256(salt + password)).
    // يجب تغييرها إجباريًا عند أول تسجيل دخول (must_change_password=1)
    // مطابقةً لسلوك lib/helpers.php الأصلي.
    const defaultSalt = 'tam_default_salt_v1';
    final defaultHash =
        sha256.convert(utf8.encode('$defaultSalt admin123')).toString();
    await db.insert('users', {
      'username': 'admin',
      'password_hash': defaultHash,
      'password_salt': defaultSalt,
      'display_name': 'المسؤول',
      'must_change_password': 1,
      'failed_attempts': 0,
      'created_at': now,
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.transaction((txn) async {
        await txn.execute('ALTER TABLE subscription_payments RENAME TO subscription_payments_old');
        await txn.execute("""CREATE TABLE subscription_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          member_id INTEGER,
          member_name TEXT, financial_guide TEXT, card_no TEXT,
          payment_year INTEGER NOT NULL, payment_month INTEGER, payment_date TEXT,
          subscription_amount REAL NOT NULL DEFAULT 0, card_fee REAL NOT NULL DEFAULT 0,
          total_amount REAL NOT NULL DEFAULT 0, source TEXT, source_name TEXT,
          matched_by TEXT, direct_to_executive INTEGER NOT NULL DEFAULT 0,
          import_batch_id TEXT, row_hash TEXT UNIQUE, notes TEXT, created_at TEXT NOT NULL,
          FOREIGN KEY (member_id) REFERENCES members (id) ON DELETE CASCADE
        )""");
        await txn.execute("""INSERT INTO subscription_payments (
          id, member_id, member_name, financial_guide, card_no, payment_year,
          payment_month, payment_date, subscription_amount, card_fee, total_amount,
          source, source_name, matched_by, direct_to_executive, import_batch_id,
          row_hash, notes, created_at)
          SELECT id, member_id, member_name, financial_guide, card_no, payment_year,
          payment_month, payment_date, subscription_amount, card_fee, total_amount,
          source, source_name, matched_by, direct_to_executive, import_batch_id,
          row_hash, notes, created_at FROM subscription_payments_old""");
        await txn.execute('DROP TABLE subscription_payments_old');
        await txn.execute('CREATE INDEX idx_sp_member ON subscription_payments(member_id)');
        await txn.execute('CREATE INDEX idx_sp_period ON subscription_payments(payment_year, payment_month)');
      });
    }
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }

  /// يُستخدم من طبقة الاستعادة (Restore) لإغلاق الاتصال الحالي
  /// قبل استبدال ملف قاعدة البيانات، ثم إعادة الفتح بعدها.
  Future<void> reopen() async {
    await close();
    _db = await _open();
  }

  Future<File> fileHandle() async {
    final path = await databaseFilePath();
    return File(path);
  }
}
