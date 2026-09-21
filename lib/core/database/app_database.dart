import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

  static const int schemaVersion = 14;
  static const String dbFileName = 'tam.db';

  Database? _db;

  /// يحمي عملية الفتح من التنفيذ أكثر من مرة عند وجود أكثر من
  /// استدعاء متزامن لـ [database] وقت الإقلاع (مثلاً أكثر من شاشة
  /// تطلبها بنفس اللحظة). بدون هذا القفل، كل استدعاء يجد `_db`
  /// لا تزال `null` فيبدأ عملية `_open()` مستقلة خاصة به، وبالتالي
  /// `_onCreate`/`_seedDefaults` قد يُنفَّذ أكثر من مرة بالتوازي على
  /// نفس ملف القاعدة، فيصطدم إدراج المستخدم الافتراضي admin بقيد
  /// UNIQUE ويرمي استثناء غير معالج يُعلّق التطبيق بشاشة بيضاء.
  Future<Database>? _openingFuture;

  /// مسار بديل يُستخدم فقط من اختبارات التكامل (test/*.dart) لتفادي
  /// الاعتماد على path_provider (الذي يحتاج قناة منصّة حقيقية غير
  /// متوفرة في `flutter test` العادي). لا يُستخدم في التطبيق الفعلي.
  static String? testDbPathOverride;

  Future<Database> get database async {
    if (_db != null) return _db!;
    if (_openingFuture != null) return _openingFuture!;
    _openingFuture = _open();
    try {
      _db = await _openingFuture!;
    } finally {
      _openingFuture = null;
    }
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
        role TEXT NOT NULL DEFAULT 'organization_secretary',
        must_change_password INTEGER NOT NULL DEFAULT 0,
        failed_attempts INTEGER NOT NULL DEFAULT 0,
        locked_until TEXT,
        member_id INTEGER REFERENCES members (id) ON DELETE CASCADE,
        cloud_user_id TEXT UNIQUE,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    batch.execute('CREATE UNIQUE INDEX idx_users_member ON users(member_id) WHERE member_id IS NOT NULL');

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
        sync_uuid TEXT UNIQUE,
        name TEXT NOT NULL UNIQUE,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    batch.execute('''
      CREATE TABLE institutions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_uuid TEXT UNIQUE,
        district_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        total_staff INTEGER NOT NULL DEFAULT 0,
        sipes_members INTEGER NOT NULL DEFAULT 0,
        snes_members INTEGER NOT NULL DEFAULT 0,
        other_union_members INTEGER NOT NULL DEFAULT 0,
        non_union_staff INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (district_id, name),
        FOREIGN KEY (district_id) REFERENCES districts (id) ON DELETE RESTRICT
      )
    ''');

    batch.execute('''
      CREATE TABLE members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_uuid TEXT UNIQUE,
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
        sync_uuid TEXT UNIQUE,
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
        payment_method TEXT NOT NULL DEFAULT 'cash',
        payment_reference TEXT,
        matched_by TEXT,
        direct_to_executive INTEGER NOT NULL DEFAULT 0,
        import_batch_id TEXT,
        row_hash TEXT UNIQUE,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
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
    batch.execute('CREATE INDEX idx_due_member_period ON subscription_dues(member_id, due_year, due_month)');

    batch.execute('''
      CREATE TABLE payment_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_id INTEGER NOT NULL,
        due_id INTEGER NOT NULL,
        allocated_amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(payment_id, due_id),
        FOREIGN KEY (payment_id) REFERENCES subscription_payments(id) ON DELETE CASCADE,
        FOREIGN KEY (due_id) REFERENCES subscription_dues(id) ON DELETE CASCADE
      )
    ''');
    batch.execute('CREATE INDEX idx_alloc_payment ON payment_allocations(payment_id)');
    batch.execute('CREATE INDEX idx_alloc_due ON payment_allocations(due_id)');

    batch.execute('''
      CREATE TABLE subscription_rates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        due_year INTEGER NOT NULL,
        due_month INTEGER NOT NULL,
        amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(due_year, due_month)
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
        sync_uuid TEXT UNIQUE,
        expense_date TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        category TEXT NOT NULL DEFAULT 'أخرى',
        description TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // ---- الصندوق السنوي المرحّل (جديد — غير موجود في الأصل) ----
    // رصيد افتتاحي يدوي اختياري لسنة معينة (يُستخدم غالبًا لسنة
    // بداية استعمال التطبيق حين تكون الأرصدة السابقة غير مسجَّلة
    // كعمليات). أي سنة لاحقة تُحسب تلقائيًا: رصيدها الافتتاحي =
    // الرصيد الختامي للسنة السابقة، ولا حاجة لتخزينه.
    batch.execute('''
      CREATE TABLE fund_opening_overrides (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        year INTEGER NOT NULL UNIQUE,
        sync_uuid TEXT UNIQUE,
        amount REAL NOT NULL DEFAULT 0,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
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

    batch.execute('''
      CREATE TABLE sync_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        local_row_id INTEGER NOT NULL,
        operation TEXT NOT NULL CHECK (operation IN ('upsert','delete')),
        payload_json TEXT,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL,
        synced_at TEXT
      )
    ''');
    batch.execute('CREATE INDEX idx_outbox_pending ON sync_outbox(synced_at, created_at)');

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

    for (var month = 1; month <= 12; month++) {
      await db.insert('subscription_rates', {'due_year': 2026, 'due_month': month, 'amount': 100, 'created_at': now});
    }

    await _seedBraeknaInstitutions(db);

    // مستخدم افتراضي — كلمة المرور الأولية: admin123
    // (مشفّرة هنا بنفس خوارزمية AuthService: sha256(salt + password)).
    // يجب تغييرها إجباريًا عند أول تسجيل دخول (must_change_password=1)
    // مطابقةً لسلوك lib/helpers.php الأصلي.
    // استخدام INSERT OR IGNORE (بدل db.insert العادي) كإجراء وقائي
    // إضافي: لو حصل أي استدعاء متكرر لهذه الدالة لأي سبب مستقبلي
    // (خطأ برمجي، إعادة محاولة بعد فشل جزئي، ...)، لا يتوقف التطبيق
    // بخطأ UNIQUE constraint غير معالج — يتجاهل الإدراج المكرر بأمان.
    const defaultSalt = 'tam_default_salt_v1';
    final defaultHash =
        sha256.convert(utf8.encode('$defaultSalt admin123')).toString();
    await db.rawInsert('''
      INSERT OR IGNORE INTO users
      (username, password_hash, password_salt, display_name, role, must_change_password, failed_attempts, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', ['admin', defaultHash, defaultSalt, 'المسؤول', 'administrator', 1, 0, now]);

    await _seedRoleUsers(db);
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
          payment_method TEXT NOT NULL DEFAULT 'cash', payment_reference TEXT,
          matched_by, direct_to_executive INTEGER NOT NULL DEFAULT 0,
          import_batch_id TEXT, row_hash TEXT UNIQUE, notes TEXT, created_at TEXT NOT NULL,
          FOREIGN KEY (member_id) REFERENCES members (id) ON DELETE CASCADE
        )""");
        await txn.execute("""INSERT INTO subscription_payments (
          id, member_id, member_name, financial_guide, card_no, payment_year,
          payment_month, payment_date, subscription_amount, card_fee, total_amount,
          source, source_name, payment_method, payment_reference, matched_by, direct_to_executive, import_batch_id,
          row_hash, notes, created_at)
          SELECT id, member_id, member_name, financial_guide, card_no, payment_year,
          payment_month, payment_date, subscription_amount, card_fee, total_amount,
          source, source_name, 'cash', NULL, matched_by, direct_to_executive, import_batch_id,
          row_hash, notes, created_at FROM subscription_payments_old""");
        await txn.execute('DROP TABLE subscription_payments_old');
        await txn.execute('CREATE INDEX idx_sp_member ON subscription_payments(member_id)');
        await txn.execute('CREATE INDEX idx_sp_period ON subscription_payments(payment_year, payment_month)');
      });
    }

    if (oldVersion < 3) {
      await db.transaction((txn) async {
        await txn.execute('ALTER TABLE institutions ADD COLUMN total_staff INTEGER NOT NULL DEFAULT 0');
        await txn.execute('ALTER TABLE institutions ADD COLUMN other_union_members INTEGER NOT NULL DEFAULT 0');
        await txn.execute('ALTER TABLE institutions ADD COLUMN non_union_staff INTEGER NOT NULL DEFAULT 0');
        await _seedBraeknaInstitutions(txn);
      });
    }

    if (oldVersion < 4) {
      await db.transaction((txn) async {
        await txn.execute("ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'organization_secretary'");
        await txn.update('users', {'role': 'administrator'}, where: 'username = ?', whereArgs: ['admin']);
        await _seedRoleUsers(txn);
      });
    }

    if (oldVersion >= 2 && oldVersion < 5) {
      await db.transaction((txn) async {
        await txn.execute("ALTER TABLE subscription_payments ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash'");
        await txn.execute("ALTER TABLE subscription_payments ADD COLUMN payment_reference TEXT");
      });
    }

    if (oldVersion < 6) {
      await db.transaction((txn) async {
        await txn.execute('ALTER TABLE users ADD COLUMN member_id INTEGER REFERENCES members (id) ON DELETE CASCADE');
        await txn.execute('CREATE UNIQUE INDEX idx_users_member ON users(member_id) WHERE member_id IS NOT NULL');
        await _backfillMemberAccounts(txn);
      });
    }
    if (oldVersion < 7) {
      await db.transaction((txn) async {
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_due_member_period ON subscription_dues(member_id, due_year, due_month)');
        await txn.execute('''CREATE TABLE IF NOT EXISTS payment_allocations (id INTEGER PRIMARY KEY AUTOINCREMENT, payment_id INTEGER NOT NULL, due_id INTEGER NOT NULL, allocated_amount REAL NOT NULL, created_at TEXT NOT NULL, UNIQUE(payment_id,due_id), FOREIGN KEY(payment_id) REFERENCES subscription_payments(id) ON DELETE CASCADE, FOREIGN KEY(due_id) REFERENCES subscription_dues(id) ON DELETE CASCADE)''');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_alloc_payment ON payment_allocations(payment_id)');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_alloc_due ON payment_allocations(due_id)');
        await txn.execute('''CREATE TABLE IF NOT EXISTS subscription_rates (id INTEGER PRIMARY KEY AUTOINCREMENT, due_year INTEGER NOT NULL, due_month INTEGER NOT NULL, amount REAL NOT NULL, created_at TEXT NOT NULL, UNIQUE(due_year,due_month))''');
        final now = DateTime.now().toIso8601String();
        for (var m = 1; m <= 12; m++) { await txn.rawInsert('INSERT OR IGNORE INTO subscription_rates(due_year,due_month,amount,created_at) VALUES(?,?,?,?)',[2026,m,100,now]); }
        final payments = await txn.query('subscription_payments');
        for (final p in payments) {
          final memberId = p['member_id'] as int?;
          final paymentId = p['id'] as int;
          final amount = (p['subscription_amount'] as num?)?.toDouble() ?? 0;
          if (memberId == null || amount <= 0) continue;
          final year = p['payment_year'] as int;
          for (var m = 1; m <= 12; m++) {
            await txn.rawInsert('INSERT OR IGNORE INTO subscription_dues(member_id,due_year,due_month,amount,created_at) VALUES(?,?,?,?,?)',[memberId,year,m,100,now]);
          }
          var left = amount;
          final start = (p['payment_month'] as int?) ?? 1;
          final dueRows = await txn.query('subscription_dues', where:'member_id=? AND due_year=? AND due_month>=?', whereArgs:[memberId,year,start], orderBy:'due_month');
          for (final d in dueRows) {
            if (left <= 0) break;
            final paidRow = await txn.rawQuery('SELECT COALESCE(SUM(allocated_amount),0) AS x FROM payment_allocations WHERE due_id=?',[d['id']]);
            final paid = (paidRow.first['x'] as num).toDouble();
            final open = (d['amount'] as num).toDouble()-paid;
            if (open<=0) continue;
            final a = left<open?left:open;
            await txn.insert('payment_allocations', {'payment_id':paymentId,'due_id':d['id'],'allocated_amount':a,'created_at':now}, conflictAlgorithm: ConflictAlgorithm.ignore);
            left -= a;
          }
        }
      });
    }
    if (oldVersion < 9) {
      await db.transaction((txn) async {
        await txn.execute('ALTER TABLE institutions ADD COLUMN sipes_members INTEGER NOT NULL DEFAULT 0');
        await txn.execute('ALTER TABLE institutions ADD COLUMN snes_members INTEGER NOT NULL DEFAULT 0');
      });
    }
    if (oldVersion < 10) {
      await db.execute("ALTER TABLE regional_expenses ADD COLUMN category TEXT NOT NULL DEFAULT 'أخرى'");
    }

    if (oldVersion < 11) {
      await db.transaction((txn) async {
        // ---- صف انتظار المزامنة (Outbox Pattern) ----
        // كل عملية كتابة على جدول "مشترك" (يُزامَن مع Supabase) تُضاف
        // كسطر هنا بدل أن تُدفع فورًا؛ عامل مزامنة منفصل (انظر
        // CloudSyncEngine) يقرأ هذا الصف ويرفعه عند توفر الإنترنت،
        // مع إعادة محاولة عند الفشل دون فقدان العملية. هذا يفصل
        // "الكتابة المحلية" (تنجح دومًا فورًا، أوفلاين) عن "الرفع
        // السحابي" (قد يتأخر أو يفشل مؤقتًا)، وهو ما كان مفقودًا
        // تمامًا قبل هذا الإصلاح (الكتابة المحلية كانت الوسيلة
        // الوحيدة، بلا أي مسار لإعادة المحاولة لاحقًا).
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS sync_outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            local_row_id INTEGER NOT NULL,
            operation TEXT NOT NULL CHECK (operation IN ('upsert','delete')),
            payload_json TEXT,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            created_at TEXT NOT NULL,
            synced_at TEXT
          )
        ''');
        await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_outbox_pending ON sync_outbox(synced_at, created_at)');

        // ---- أعمدة updated_at اللازمة لحل التعارض "آخر تعديل يفوز" ----
        // (members تملكها مسبقًا). دون هذا العمود لا يمكن لمحرّك
        // المزامنة أن يقرر أي نسخة (المحلية أم السحابية) هي الأحدث.
        final now = DateTime.now().toIso8601String();
        for (final table in ['subscription_payments', 'districts', 'institutions']) {
          try {
            await txn.execute('ALTER TABLE $table ADD COLUMN updated_at TEXT');
            await txn.execute(
                "UPDATE $table SET updated_at = COALESCE(created_at, ?) WHERE updated_at IS NULL",
                [now]);
          } catch (_) {
            // العمود موجود مسبقًا في ترقية سابقة — تجاهل بأمان.
          }
        }
      });
    }

    if (oldVersion < 12) {
      await db.transaction((txn) async {
        await txn.execute('ALTER TABLE users ADD COLUMN cloud_user_id TEXT');
        await txn.execute('ALTER TABLE users ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1');
        for (final table in ['districts','institutions','members','subscription_payments']) {
          try { await txn.execute('ALTER TABLE $table ADD COLUMN sync_uuid TEXT'); } catch (_) {}
          await txn.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_${table}_sync_uuid ON $table(sync_uuid)');
          final rows = await txn.query(table, columns: ['id','sync_uuid']);
          for (final row in rows) {
            if (row['sync_uuid'] != null) continue;
            await txn.update(table, {'sync_uuid': _newSyncUuid()}, where: 'id = ?', whereArgs: [row['id']]);
          }
        }
      });
    }

    if (oldVersion < 13) {
      await db.execute('DROP TABLE IF EXISTS whatsapp_messages');
    }

    if (oldVersion < 14) {
      await db.transaction((txn) async {
        // Expense sync metadata.
        try { await txn.execute('ALTER TABLE regional_expenses ADD COLUMN sync_uuid TEXT'); } catch (_) {}
        try { await txn.execute('ALTER TABLE regional_expenses ADD COLUMN updated_at TEXT'); } catch (_) {}
        await txn.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_regional_expenses_sync_uuid ON regional_expenses(sync_uuid)');
        final expenseRows = await txn.query('regional_expenses', columns:['id','sync_uuid','created_at']);
        for (final row in expenseRows) {
          final values=<String,Object?>{'updated_at':row['created_at'] ?? DateTime.now().toIso8601String()};
          if (row['sync_uuid']==null) values['sync_uuid']=_newSyncUuid();
          await txn.update('regional_expenses',values,where:'id=?',whereArgs:[row['id']]);
        }

        // Upgrade opening overrides from year-as-PK to a normal local integer id.
        await txn.execute('''CREATE TABLE fund_opening_overrides_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT, year INTEGER NOT NULL UNIQUE, sync_uuid TEXT UNIQUE,
          amount REAL NOT NULL DEFAULT 0, notes TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        )''');
        final openings=await txn.query('fund_opening_overrides');
        for(final row in openings){
          await txn.insert('fund_opening_overrides_new',{
            'year':row['year'],'amount':row['amount']??0,'notes':row['notes'],
            'sync_uuid':_newSyncUuid(),'created_at':row['created_at']??DateTime.now().toIso8601String(),
            'updated_at':row['created_at']??DateTime.now().toIso8601String(),
          });
        }
        await txn.execute('DROP TABLE fund_opening_overrides');
        await txn.execute('ALTER TABLE fund_opening_overrides_new RENAME TO fund_opening_overrides');
        await txn.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_fund_opening_overrides_sync_uuid ON fund_opening_overrides(sync_uuid)');
      });
    }

  }

  static String _newSyncUuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2,'0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20,32)}';
  }

  /// عند الترقية لأول مرة: تُنشأ حسابات الدخول الذاتي للمنتسبين
  /// الموجودين مسبقًا (الدليل المالي = اسم المستخدم، الهاتف = كلمة
  /// المرور)، لمن تتوفر له دليل مالي ورقم هاتف معًا فقط. من لا يملك
  /// أحدهما ستُنشأ له لاحقًا تلقائيًا بمجرد استكمال بياناته من واجهة
  /// تعديل المنتسب (انظر MemberRepository.update).
  Future<void> _backfillMemberAccounts(DatabaseExecutor txn) async {
    final members = await txn.query('members',
        where: "guide IS NOT NULL AND TRIM(guide) != '' AND phone IS NOT NULL AND TRIM(phone) != ''");
    final now = DateTime.now().toIso8601String();
    for (final m in members) {
      final memberId = m['id'] as int;
      final guide = (m['guide'] as String).trim();
      final phone = (m['phone'] as String).trim();
      final name = m['name'] as String;
      final rnd = Random.secure();
      final salt = base64UrlEncode(List<int>.generate(16, (_) => rnd.nextInt(256)));
      final hash = sha256.convert(utf8.encode('$salt $phone')).toString();
      try {
        await txn.insert('users', {
          'username': guide,
          'password_hash': hash,
          'password_salt': salt,
          'display_name': name,
          'role': 'member',
          'must_change_password': 0,
          'failed_attempts': 0,
          'member_id': memberId,
          'created_at': now,
        });
      } catch (_) {
        // تعارض دليل مالي مكرر — يُتجاهل، يمكن إصلاحه لاحقًا يدويًا.
      }
    }
  }


  Future<void> _seedRoleUsers(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();
    const users = <Map<String, String>>[
      {
        'username': 'organization',
        'password': 'TAM@2026Org',
        'display_name': 'أمين التنظيم',
        'role': 'organization_secretary',
      },
      {
        'username': 'finance',
        'password': 'TAM@2026Fin',
        'display_name': 'أمين المالية',
        'role': 'finance_secretary',
      },
      {
        'username': 'captain',
        'password': 'TAM@2026Cap',
        'display_name': 'النقيب الجهوي',
        'role': 'regional_captain',
      },
    ];
    for (final u in users) {
      const salt = 'tam_role_seed_v1';
      final hash = sha256.convert(utf8.encode('$salt ${u['password']}')).toString();
      await db.rawInsert('''
        INSERT OR IGNORE INTO users
        (username, password_hash, password_salt, display_name, role, must_change_password, failed_attempts, created_at)
        VALUES (?, ?, ?, ?, ?, 1, 0, ?)
      ''', [u['username'], hash, salt, u['display_name'], u['role'], now]);
    }
  }

  /// أسماء المؤسسات والمقاطعات مأخوذة من سجل منتسبي TAM المرفوع.
  /// تبقى المؤسسات قابلة للإضافة والتعديل بعد ذلك.
  Future<void> _seedBraeknaInstitutions(DatabaseExecutor db) async {
    const districts = <String, int>{
      'ألاك': 0,
      'مقطع لحجار': 1,
      'بوكي': 2,
      'بابابي': 3,
      'مال': 4,
      'امباني': 5,
    };
    const institutions = <String, List<String>>{
      'ألاك': ['ثانوية ألاك', 'إعدادية ألاك', 'ثانوية بوحديدة', 'ثانوية شكار', 'ثانوية أغشوركيت'],
      'مقطع لحجار': ['ثانوية مقطع لحجار', 'إعدادية مقطع لحجار', 'ثانوية صنكرافة', 'ثانوية جونابة', 'إعدادية لخطيط', 'إعدادية كيمي', 'إعدادية واد آمور', 'إ.شكار كادل', 'إعدادية ليردي', 'إ.اتويجكجيت', 'إ.بجنكل'],
      'بوكي': ['ثانوية بوكي', 'إعدادية بوكي', 'ثانوية تولدة', 'ثانوية تيدة', 'إ.وابندة', 'إ.ول بيرم', 'إ.تالكو', 'إ.صرندوكو', 'إ.دار البركة', 'إ.دار السلام', 'إ.حمد الله'],
      'بابابي': ['ثانوية بابابي', 'إ.بابابي', 'إ.هايرى امبار', 'إ.الفرع'],
      'مال': ['ثانوية مال', 'إ.البطحة', 'إ.بورات'],
      'امباني': ['ثانوية امباني', 'إ.امباني', 'إ.أدباي الحجاج', 'ث.باكودين', 'ث.انيابينا', 'إ.افوندو', 'إ.جارلول'],
    };
    final now = DateTime.now().toIso8601String();
    for (final entry in institutions.entries) {
      final districtId = await _ensureDistrict(db, entry.key, districts[entry.key] ?? 99, now);
      for (final name in entry.value) {
        await db.rawInsert(
          'INSERT OR IGNORE INTO institutions (district_id, name, total_staff, other_union_members, non_union_staff, created_at) VALUES (?, ?, 0, 0, 0, ?)',
          [districtId, name, now],
        );
      }
    }
  }

  Future<int> _ensureDistrict(DatabaseExecutor db, String name, int sortOrder, String now) async {
    final rows = await db.query('districts', where: 'name = ?', whereArgs: [name], limit: 1);
    if (rows.isNotEmpty) return rows.first['id'] as int;
    return db.insert('districts', {'name': name, 'sort_order': sortOrder, 'created_at': now});
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
