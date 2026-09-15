import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database/app_database.dart';
import 'import/csv_normalizer.dart';
import 'drive_sync_service.dart';

class MemberImportResult {
  final bool success; final int added; final int skipped; final int errors;
  final List<String> messages; final String? error;
  const MemberImportResult({required this.success, this.added=0, this.skipped=0, this.errors=0, this.messages=const [], this.error});
}

class MemberImporter {
  Future<MemberImportResult> importFile(String filePath) async {
    try {
      final raw=await File(filePath).readAsBytes(); final content=_decode(raw);
      final first=content.split(RegExp(r'[\r\n]')).firstWhere((x)=>x.trim().isNotEmpty,orElse:()=>'' );
      final c=','.allMatches(first).length, s=';'.allMatches(first).length, t='\t'.allMatches(first).length;
      var delimiter=','; if(s>c&&s>t) delimiter=';'; if(t>c&&t>s) delimiter='\t';
      final table=const CsvToListConverter(eol:'\n').convert(content.replaceAll('\r\n','\n'),fieldDelimiter:delimiter);
      if(table.isEmpty) return const MemberImportResult(success:false,error:'ملف CSV فارغ.');
      final headers=table.first.map((e)=>e.toString().trim()).toList(); final mapped=<String,int>{};
      for(var i=0;i<headers.length;i++){final k=CsvNormalizer.memberHeaderKey(headers[i]); if(k.isNotEmpty)mapped[k]=i;}
      for(final r in ['name','district','institution']) if(!mapped.containsKey(r)) return MemberImportResult(success:false,error:'العمود المطلوب غير موجود: $r');
      String get(List<dynamic> row,String key){final i=mapped[key]; return i==null||i>=row.length?'':row[i].toString().trim();}
      final db=await AppDatabase.instance.database; var added=0,skipped=0,errors=0; final messages=<String>[];
      await db.transaction((txn) async {
        for(var i=1;i<table.length;i++){
          final row=table[i]; if(row.every((v)=>v.toString().trim().isEmpty))continue;
          final name=get(row,'name'), district=get(row,'district'), institution=get(row,'institution');
          if(name.isEmpty||district.isEmpty||institution.isEmpty){errors++;messages.add('السطر ${i+1}: الاسم/المقاطعة/المؤسسة ناقص.');continue;}
          final districtId=await _district(txn,district); final institutionId=await _institution(txn,districtId,institution);
          final guide=get(row,'guide'); final duplicate=await txn.query('members',where:"name = ? AND district_id = ? AND institution_id = ? AND COALESCE(guide,'') = ?",whereArgs:[name,districtId,institutionId,guide],limit:1);
          if(duplicate.isNotEmpty){skipped++;continue;}
          final now=DateTime.now().toIso8601String();
          await txn.insert('members',{'district_id':districtId,'institution_id':institutionId,'name':name,'guide':guide.isEmpty?null:guide,'card_no':_null(get(row,'card_no')),'phone':_null(get(row,'phone')),'notes':_null(get(row,'notes')),'membership_status':'active','status_date':null,'is_archived':0,'created_at':now,'updated_at':now});
          added++;
        }
      });
      if (added > 0) await DriveSyncService().markDirty();
      return MemberImportResult(success:errors==0,added:added,skipped:skipped,errors:errors,messages:messages,error:errors==0?null:'تم الاستيراد مع وجود $errors أخطاء.');
    } catch(e){return MemberImportResult(success:false,error:e.toString());}
  }
  String? _null(String v)=>v.isEmpty?null:v;
  String _decode(List<int> b){
    if(b.length>=3&&b[0]==0xEF&&b[1]==0xBB&&b[2]==0xBF)return utf8.decode(b.sublist(3),allowMalformed:true);
    if(b.length>=2&&b[0]==0xFF&&b[1]==0xFE)return _utf16(b.sublist(2),true);
    if(b.length>=2&&b[0]==0xFE&&b[1]==0xFF)return _utf16(b.sublist(2),false);
    return utf8.decode(b,allowMalformed:true);
  }
  String _utf16(List<int>b,bool le){final u=<int>[];for(var i=0;i+1<b.length;i+=2)u.add(le?b[i]|b[i+1]<<8:b[i]<<8|b[i+1]);return String.fromCharCodes(u);}
  Future<int> _district(Transaction tx,String name)async{final n=CsvNormalizer.norm(name);final rows=await tx.query('districts');for(final r in rows)if(CsvNormalizer.norm(r['name'] as String)==n)return r['id'] as int;return tx.insert('districts',{'name':name,'sort_order':0,'created_at':DateTime.now().toIso8601String()});}
  Future<int> _institution(Transaction tx,int did,String name)async{final n=CsvNormalizer.norm(name);final rows=await tx.query('institutions',where:'district_id = ?',whereArgs:[did]);for(final r in rows)if(CsvNormalizer.norm(r['name'] as String)==n)return r['id'] as int;return tx.insert('institutions',{'district_id':did,'name':name,'created_at':DateTime.now().toIso8601String()});}
}
