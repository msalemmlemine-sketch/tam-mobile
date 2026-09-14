import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/database/app_database.dart';

class OrganizationSettingsScreen extends StatefulWidget { const OrganizationSettingsScreen({super.key}); @override State<OrganizationSettingsScreen> createState()=>_OrganizationSettingsScreenState(); }
class _OrganizationSettingsScreenState extends State<OrganizationSettingsScreen>{String? _path;bool _busy=true;
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{final db=await AppDatabase.instance.database;final r=await db.query('settings',where:'setting_key = ?',whereArgs:['org_logo_path']);if(mounted)setState(() { _path=r.isEmpty?null:r.first['setting_value'] as String?; _busy=false; });}
  Future<void> _pick()async{final pck=await FilePicker.pickFiles(type:FileType.image,withData:false);if(pck.isEmpty||pck.single.path==null)return;setState(()=>_busy=true);try{final src=File(pck.single.path!);final d=await getApplicationDocumentsDirectory();final dir=Directory(p.join(d.path,'organization'));await dir.create(recursive:true);final ext=p.extension(src.path).isEmpty?'.png':p.extension(src.path);final target=File(p.join(dir.path,'logo$ext'));await src.copy(target.path);final db=await AppDatabase.instance.database;await db.insert('settings',{'setting_key':'org_logo_path','setting_value':target.path},conflictAlgorithm:ConflictAlgorithm.replace);if(mounted)setState(() { _path=target.path; _busy=false; });}catch(e){if(mounted){setState(()=>_busy=false);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذر حفظ الشعار: $e')));}}}
  Future<void> _remove()async{final path=_path;final db=await AppDatabase.instance.database;await db.delete('settings',where:'setting_key = ?',whereArgs:['org_logo_path']);if(path!=null){final f=File(path);if(await f.exists())await f.delete();}if(mounted)setState(()=>_path=null);}
  @override Widget build(BuildContext context){final has=_path!=null&&File(_path!).existsSync();return Scaffold(appBar:AppBar(title:const Text('شعار النقابة')),body:_busy?const Center(child:CircularProgressIndicator()):Padding(padding:const EdgeInsets.all(24),child:Column(children:[Expanded(child:Center(child:has?Image.file(File(_path!),width:220,height:220,fit:BoxFit.contain):const Icon(Icons.image_outlined,size:120))),SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:_pick,icon:const Icon(Icons.photo_library_outlined),label:Text(has?'تغيير الشعار':'اختيار الشعار'))),if(has)OutlinedButton.icon(onPressed:_remove,icon:const Icon(Icons.delete_outline),label:const Text('حذف الشعار'))])));}
}
