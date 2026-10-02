part of 'main.dart';

// Tracks confirmed message IDs, not read receipts or local optimistic writes.
class ChatAlertTracker {
  final String uid;
  final bool owner;
  final Map<String,String> seen = {};
  bool ready = false;
  ChatAlertTracker({required this.uid,required this.owner});
  List<MapEntry<String,Map<String,dynamic>>> accept(Map<String,Map<String,dynamic>> threads,{bool cached=false,bool pending=false}) {
    if(cached || pending) return [];
    final alerts=<MapEntry<String,Map<String,dynamic>>>[];
    for(final entry in threads.entries) {
      final data=entry.value, id='${entry.value['lastMessageId'] ?? ''}';
      if(id.isEmpty) continue;
      final previous=seen[entry.key]; seen[entry.key]=id;
      if(!ready || previous == id || data['lastSenderId'] == uid) continue;
      if(data['lastSenderRole'] != (owner ? 'employee' : 'owner')) continue;
      final sent=data['lastMessageAt'],read=data[owner ? 'ownerReadAt' : 'employeeReadAt'];
      if(sent is! Timestamp || (read is Timestamp && read.compareTo(sent) >= 0)) continue;
      alerts.add(entry);
    }
    ready=true;
    return alerts;
  }
}

class ChatAlerts {
  static final instance=ChatAlerts();
  final warning=ValueNotifier<String?>(null);
  StreamSubscription<dynamic>? subscription;
  int generation=0;
  Future<void> queue=Future.value();
  FlutterLocalNotificationsPlugin get plugin => ChequeReminders.instance.plugin;
  AndroidFlutterLocalNotificationsPlugin? get android => ChequeReminders.instance.android;
  static const details=NotificationDetails(android:AndroidNotificationDetails(
    'vib_chat_v1','رسائل المدير والموظفين',channelDescription:'رنّة وتنبيه عند وصول رسالة جديدة',
    importance:Importance.max,priority:Priority.high,playSound:true,enableVibration:true,
    icon:'vib_notification',visibility:NotificationVisibility.private));
  Future<void> permissions() async {
    await ChequeReminders.instance.initialize();
    await android?.requestNotificationsPermission();
    warning.value=await android?.areNotificationsEnabled() == true ? null : 'اسمح بإشعارات التطبيق عشان تسمع رنّة الرسائل.';
  }
  Future<void> watch(String uid,bool owner) async {
    final token=++generation;
    await subscription?.cancel();
    try {
      await permissions(); if(token != generation) return;
      final tracker=ChatAlertTracker(uid:uid,owner:owner);
      void process(Map<String,Map<String,dynamic>> threads,bool cached,bool pending) {
        if(token != generation) return;
        final alerts=tracker.accept(threads,cached:cached,pending:pending);
        queue=queue.then((_) async {
          for(final alert in alerts) {
            if(token != generation) return;
            await notify(alert.key,alert.value,owner);
          }
        }).catchError((Object error) {if(token == generation) warning.value='تعذر تشغيل تنبيه الرسائل؛ راجع إعدادات إشعارات التطبيق.';});
      }
      void failure(Object error) {if(token == generation) warning.value='تعذر متابعة تنبيهات المحادثة؛ راجع الاتصال وصلاحيات الحساب.';}
      if(owner) {
        subscription=db.collection('staffChats').snapshots(includeMetadataChanges:true).listen((snapshot) {
          process({for(final d in snapshot.docs)d.id:d.data()},snapshot.metadata.isFromCache,snapshot.metadata.hasPendingWrites);
        },onError:failure);
      } else {
        subscription=db.collection('staffChats').doc(uid).snapshots(includeMetadataChanges:true).listen((snapshot) {
          process({if(snapshot.exists)uid:snapshot.data()!},snapshot.metadata.isFromCache,snapshot.metadata.hasPendingWrites);
        },onError:failure);
      }
    } catch(_) {if(token == generation) warning.value='تعذر تفعيل تنبيهات الرسائل.';}
  }
  Future<void> notify(String threadId,Map<String,dynamic> data,bool owner) async {
    if(await android?.areNotificationsEnabled() != true) {warning.value='اسمح بإشعارات التطبيق عشان تسمع رنّة الرسائل.';return;}
    final name=owner ? '${data['employeeName'] ?? 'الموظف'}' : 'المدير';
    final text='${data['lastText'] ?? 'رسالة جديدة'}';
    var hash=0;for(final c in threadId.codeUnits) {hash=(hash*31+c)%100000000;}
    await plugin.show(2000000000+hash,'رسالة من $name',text.length > 100 ? '${text.substring(0,100)}…' : text,details,payload:'chat:$threadId');
  }
  Future<void> stop() async {++generation;final old=subscription;subscription=null;await old?.cancel();}
  Future<void> test() async {
    await permissions();
    if(warning.value != null) throw StateError(warning.value!);
    await plugin.show(2147483645,'تنبيه المحادثة','دي رنّة تجريبية للرسائل الجديدة.',details,payload:'chat:test');
  }
}

class ChatAlertsButton extends StatelessWidget {
  const ChatAlertsButton({super.key});
  @override Widget build(BuildContext context) => IconButton(tooltip:'تنبيهات ورنّة الرسائل',icon:const Icon(Icons.notifications_active_outlined),onPressed:() async {
    await showDialog<void>(context:context,builder:(dialogContext)=>AlertDialog(
      title:const Text('تنبيهات المحادثة'),
      content:ValueListenableBuilder<String?>(valueListenable:ChatAlerts.instance.warning,builder:(_,warning,__)=>Text(warning ?? 'الرنّة تعمل للرسائل الجديدة أثناء تشغيل التطبيق. وصول التنبيه والتطبيق مقفول يحتاج تفعيل خدمة الإشعارات السحابية. لو الموبايل صامت أو وضع عدم الإزعاج مفعل، راجع إعدادات الصوت.')),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('إغلاق')),FilledButton(onPressed:() async {
        try {await ChatAlerts.instance.test();} catch(_) {if(dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content:Text(ChatAlerts.instance.warning.value ?? 'تعذر تشغيل الرنّة التجريبية')));}
      },child:const Text('تفعيل وتجربة الرنّة'))],
    ));
  });
}
