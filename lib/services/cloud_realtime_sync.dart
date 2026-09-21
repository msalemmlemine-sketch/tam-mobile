import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/database/app_database.dart';
import 'cloud_config.dart';
import 'cloud_service.dart';

class CloudRealtimeSync {
  CloudRealtimeSync._();
  static final instance = CloudRealtimeSync._();
  final List<RealtimeChannel> _channels=[];
  bool _started=false;

  Future<void> start() async {
    if (_started || !CloudConfig.enabled || Supabase.instance.client.auth.currentSession==null) return;
    _started=true;
    for (final table in const ['districts','institutions','members','subscription_payments','regional_expenses','fund_opening_overrides']) {
      final channel=Supabase.instance.client.channel('tam-realtime-$table');
      channel.onPostgresChanges(event: PostgresChangeEvent.all, schema:'public', table:table, callback:(payload){ unawaited(_apply(table,payload)); });
      await channel.subscribe();
      _channels.add(channel);
    }
  }

  Future<void> _apply(String table, PostgresChangePayload payload) async {
    final db=await AppDatabase.instance.database;
    final record=payload.eventType==PostgresChangeEvent.delete ? payload.oldRecord : payload.newRecord;
    final sync=record['sync_uuid']?.toString();
    if(sync==null || sync.isEmpty) return;
    if(payload.eventType==PostgresChangeEvent.delete){
      await db.delete(table,where:'sync_uuid=?',whereArgs:[sync]);
      return;
    }
    await CloudService().pullAllToLocal();
  }

  Future<void> stop() async {
    for(final c in _channels){ await Supabase.instance.client.removeChannel(c); }
    _channels.clear(); _started=false;
  }
}
