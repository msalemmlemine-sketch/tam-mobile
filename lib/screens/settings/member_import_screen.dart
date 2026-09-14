import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../services/member_importer.dart';

class MemberImportScreen extends StatefulWidget { const MemberImportScreen({super.key}); @override State<MemberImportScreen> createState()=>_MemberImportScreenState(); }
class _MemberImportScreenState extends State<MemberImportScreen>{
  final _importer=MemberImporter(); bool _busy=false; MemberImportResult? _result;
  Future<void> _pick()async{final p=await FilePicker.pickFiles(type:FileType.custom,allowedExtensions:['csv'],withData:false);if(p.isEmpty||p.single.path==null)return;setState(()=>_busy=true);final r=await _importer.importFile(p.single.path!);if(mounted)setState(() { _busy=false; _result=r; });}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('استيراد المنتسبين')),floatingActionButton:FloatingActionButton.extended(onPressed:_busy?null:_pick,icon:const Icon(Icons.upload_file),label:const Text('اختيار ملف CSV')),body:_busy?const Center(child:CircularProgressIndicator()):_result==null?const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('الأعمدة المطلوبة: الاسم، المقاطعة، المؤسسة\n\nاختياري: الدليل المالي، رقم البطاقة، الهاتف، الملاحظات',textAlign:TextAlign.center))):ListView(padding:const EdgeInsets.all(20),children:[Text(_result!.success?'تم الاستيراد':'تمت العملية مع ملاحظات',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:12),Text('تمت الإضافة: ${_result!.added}'),Text('تم تجاوز الموجود: ${_result!.skipped}'),Text('الأخطاء: ${_result!.errors}'),if(_result!.error!=null)Text(_result!.error!,style:const TextStyle(color:Colors.red)),..._result!.messages.map(Text.new)]));
}
