part of 'main.dart';

tz.Location get chequeZone => tz.getLocation('Africa/Cairo');
void initializeChequeTimeZones() => tzdata.initializeTimeZones();
String chequeDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
DateTime chequeReminderBefore(DateTime due, int days, int hour, int minute) =>
    tz.TZDateTime(chequeZone, due.year, due.month, due.day - days, hour, minute);
String chequeTimeLabel(Timestamp stamp) => DateFormat('yyyy/MM/dd • HH:mm').format(tz.TZDateTime.from(stamp.toDate(), chequeZone));

class ChequeReminderJob {
  final int id;
  final String title, body, payload;
  final DateTime when;
  const ChequeReminderJob(this.id, this.title, this.body, this.payload, this.when);
}

List<ChequeReminderJob> planChequeReminders(List<Map<String,dynamic>> rows, DateTime now) {
  final jobs = <ChequeReminderJob>[], used = <int>{};
  for (final row in rows) {
    if (row['status'] == 'done' || row['reminderEnabled'] != true) continue;
    final stamp = row['reminderAt'];
    if (stamp is! Timestamp || !stamp.toDate().isAfter(now)) continue;
    final id = row['notificationId'];
    if (id is! int || id < 1 || id >= 2147483646 || !used.add(id)) throw StateError('راجع أرقام تنبيهات الشيكات');
    final amount = (row['amount'] as num).toDouble().toStringAsFixed(2);
    final body = 'شيك ${row['type'] == 'received' ? 'وارد' : 'صادر'} رقم ${row['number']} • ${row['party']} • $amount ج.م • يستحق ${row['dueDate']}';
    jobs.add(ChequeReminderJob(id, 'تذكير بموعد شيك', body,
      'cheque:${row['id']}:${stamp.millisecondsSinceEpoch}:${jsonEncode([row['number'],row['party'],row['amount'],row['dueDate'],row['type']])}',stamp.toDate()));
  }
  jobs.sort((a,b) => a.when.compareTo(b.when));
  if (jobs.length > 300) throw StateError('الحد الأقصى 300 تذكير قادم؛ أغلق الشيكات المنتهية أولًا');
  return jobs;
}

({List<Map<String,dynamic>> records, int nextId}) editChequeLedger(
    List<Map<String,dynamic>> records, Map<String,dynamic> item, int nextId, {int? expectedRevision, bool remove=false}) {
  final next = records.map((r) => Map<String,dynamic>.from(r)).toList();
  final index = next.indexWhere((r) => r['id'] == item['id']);
  if (index >= 0) {
    final old = next[index];
    if(expectedRevision == null && !remove && item.entries.every((entry) => old[entry.key] == entry.value)) return (records:next,nextId:nextId);
    if (expectedRevision == null || (old['revision'] ?? 0) != expectedRevision) throw StateError('الشيك اتعدل من جهاز آخر؛ افتحه مجددًا');
    if (remove) next.removeAt(index);
    else next[index] = {...old,...item,'notificationId':old['notificationId'],'revision':expectedRevision+1};
  } else {
    if (remove || expectedRevision != null) throw StateError('الشيك لم يعد موجودًا');
    if (next.length >= 400) throw StateError('احذف شيكات منتهية قبل إضافة شيك جديد');
    if (nextId < 1 || nextId >= 2147483646) throw StateError('تعذر تخصيص رقم للتذكير');
    next.add({...item,'notificationId':nextId,'revision':0}); nextId++;
  }
  return (records:next,nextId:nextId);
}

class ChequeReminders {
  static final instance = ChequeReminders();
  final plugin = FlutterLocalNotificationsPlugin();
  final warning = ValueNotifier<String?>(null);
  Future<void>? initialization;
  Future<void> queue = Future.value();
  StreamSubscription<DocumentSnapshot<Map<String,dynamic>>>? subscription;
  List<Map<String,dynamic>> latest = [];
  int generation = 0;
  String? ownerId;
  Future<void> initialize() => initialization ??= _initialize();
  Future<void> _initialize() async {
    initializeChequeTimeZones();
    await plugin.initialize(const InitializationSettings(android:AndroidInitializationSettings('vib_notification')));
  }
  AndroidFlutterLocalNotificationsPlugin? get android => plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  Future<void> requestPermissions() async {
    await initialize();
    await android?.requestNotificationsPermission();
    if (await android?.areNotificationsEnabled() == true && await android?.canScheduleExactNotifications() != true) await android?.requestExactAlarmsPermission();
    await synchronize();
  }
  Future<void> watch(String uid) async {
    final token = ++generation; ownerId = uid; latest=[];
    try {
      await subscription?.cancel(); await initialize();
      if (token != generation) return;
      subscription = db.collection('settings').doc('cheques_$uid').snapshots(includeMetadataChanges:true).listen((snapshot) {
        if (token != generation || snapshot.metadata.hasPendingWrites) return;
        latest = ((snapshot.data()?['records'] as List?) ?? []).map((r) => Map<String,dynamic>.from(r as Map)).toList();
        synchronize();
      },onError:(Object error) { if(token == generation) warning.value='تعذر مزامنة مواعيد الشيكات: $error'; });
    } catch(e) { if(token == generation) warning.value='تعذر تفعيل تذكيرات الشيكات: $e'; }
  }
  Future<void> stop() async {
    final token=++generation; ownerId=null; latest=[];
    try { await subscription?.cancel(); await queue; if(initialization != null) await initialization; if(token == generation && ownerId == null && initialization != null) await cancelChequeNotifications(); } catch(_) {}
  }
  Future<void> cancelChequeNotifications() async {
    for(final pending in await plugin.pendingNotificationRequests()) {
      if(pending.payload?.startsWith('cheque:') == true) await plugin.cancel(pending.id);
    }
  }
  Future<void> synchronize() {
    final token=generation, rows=latest.map((r) => Map<String,dynamic>.from(r)).toList();
    queue=queue.catchError((_) {}).then((_) async {
      if(token != generation || ownerId == null) return;
      try {
        await initialize();
        final enabled=await android?.areNotificationsEnabled() == true;
        final exact=await android?.canScheduleExactNotifications() == true;
        if(token != generation) return;
        if(!enabled) { await cancelChequeNotifications(); warning.value='التذكير غير مفعل: اسمح بإشعارات التطبيق من زر تفعيل التنبيهات.'; return; }
        final jobs=planChequeReminders(rows,DateTime.now());
        final pending=await plugin.pendingNotificationRequests();
        if(token != generation) return;
        final byId={for(final p in pending) if(p.payload?.startsWith('cheque:') == true) p.id:p};
        final ids=jobs.map((j) => j.id).toSet();
        for(final id in byId.keys.where((id) => !ids.contains(id))) { if(token != generation) return; await plugin.cancel(id); }
        for(final job in jobs) {
          if(token != generation) return;
          final payload='${job.payload}:${exact ? 'exact' : 'approximate'}';
          if(byId[job.id]?.payload == payload) continue;
          if(!job.when.isAfter(DateTime.now())) continue;
          await plugin.zonedSchedule(job.id,job.title,job.body,tz.TZDateTime.from(job.when,chequeZone),
            const NotificationDetails(android:AndroidNotificationDetails('vib_cheques_v1','مواعيد الشيكات',channelDescription:'تذكير بمواعيد استحقاق الشيكات',importance:Importance.high,priority:Priority.high,icon:'vib_notification',visibility:NotificationVisibility.private)),
            androidScheduleMode:exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,payload:payload);
        }
        if(token == generation) warning.value=exact ? null : 'التذكير مفعل بتوقيت تقريبي. فعّل «المنبهات والتذكيرات» لتظهر الإشعارات في الساعة المحددة.';
      } catch(e) { if(token == generation) warning.value='تعذر جدولة التذكيرات: $e'; }
    });
    return queue;
  }
  Future<void> refresh(String uid) async {
    if(ownerId != uid) return;
    try {
      final token=generation,snapshot=await db.collection('settings').doc('cheques_$uid').get(const GetOptions(source:Source.server));
      if(token != generation) return;
      latest=((snapshot.data()?['records'] as List?) ?? []).map((r) => Map<String,dynamic>.from(r as Map)).toList();
      await synchronize();
    } catch(e) {warning.value='تم حفظ الشيك، لكن تعذر تحديث التذكيرات: $e';}
  }
  Future<void> test() async {
    await requestPermissions();
    if(await android?.areNotificationsEnabled() != true) throw StateError('اسمح بإشعارات التطبيق أولًا');
    await plugin.show(2147483646,'تذكيرات الشيكات','ده إشعار تجريبي من VIB؛ التنبيهات مسموح بها على الموبايل.',const NotificationDetails(android:AndroidNotificationDetails('vib_cheques_v1','مواعيد الشيكات',importance:Importance.high,priority:Priority.high,icon:'vib_notification')));
  }
}

class ChequeAgenda extends StatefulWidget {
  final String uid;
  const ChequeAgenda({super.key,required this.uid});
  @override State<ChequeAgenda> createState() => _ChequeAgendaState();
}
class _ChequeAgendaState extends State<ChequeAgenda> with WidgetsBindingObserver {
  bool completed=false;
  @override void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if(state == AppLifecycleState.resumed) { ChequeReminders.instance.synchronize(); if(mounted) setState(() {}); } }
  Future<void> notificationAction(bool test) async {
    try { if(test) await ChequeReminders.instance.test(); else await ChequeReminders.instance.requestPermissions(); }
    catch(e) { if(mounted) await showInvoiceSaveProblem(context,'تعذر تفعيل التنبيهات: $e',title:'تذكيرات الشيكات',button:'تمام'); }
  }
  @override Widget build(BuildContext context) => Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      FilledButton.icon(onPressed:() => editChequeDialog(context,widget.uid),icon:const Icon(Icons.add),label:const Text('تسجيل شيك جديد')),
      Wrap(spacing:8,children:[OutlinedButton.icon(onPressed:() => notificationAction(false),icon:const Icon(Icons.notifications_active),label:const Text('تفعيل التنبيهات')),TextButton(onPressed:() => notificationAction(true),child:const Text('اختبار إشعار'))]),
      const Text('المواعيد بتوقيت القاهرة. تسجيل الشيك لتنظيم المواعيد؛ السداد الفعلي بسند صرف أو قبض.',style:TextStyle(fontSize:12),textAlign:TextAlign.center),
      ValueListenableBuilder<String?>(valueListenable:ChequeReminders.instance.warning,builder:(_,message,__) => message == null ? const SizedBox.shrink() : Padding(padding:const EdgeInsets.only(top:8),child:Text(message,style:const TextStyle(color:Colors.orangeAccent)))),
      Wrap(spacing:8,children:[ChoiceChip(label:const Text('القادمة والمتأخرة'),selected:!completed,onSelected:(_) => setState(() => completed=false)),ChoiceChip(label:const Text('تم التنفيذ'),selected:completed,onSelected:(_) => setState(() => completed=true))]),
    ])),
    Expanded(child:StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:db.collection('settings').doc('cheques_${widget.uid}').snapshots(includeMetadataChanges:true),builder:(context,snapshot) {
      if(snapshot.hasError) return Center(child:Text('تعذر تحميل الشيكات: ${snapshot.error}'));
      if(!snapshot.hasData) return const Center(child:CircularProgressIndicator());
      final rows=((snapshot.data!.data()?['records'] as List?) ?? []).map((r) => Map<String,dynamic>.from(r as Map)).where((r) => (r['status'] == 'done') == completed).toList()..sort((a,b) => '${a['dueDate']}'.compareTo('${b['dueDate']}'));
      if(rows.isEmpty) return Center(child:Text(completed ? 'لا توجد شيكات منفذة' : 'سجل أول شيك وحدد ميعاد تذكيره'));
      final today=chequeDate(tz.TZDateTime.now(chequeZone));
      return ListView.builder(itemCount:rows.length,itemBuilder:(context,i) {
        final row=rows[i],due='${row['dueDate']}',late=!completed && due.compareTo(today)<0;
        final status=completed ? 'تم التنفيذ' : late ? 'متأخر' : due == today ? 'مستحق اليوم' : 'قادم';
        return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text('${row['party']} • شيك ${row['type'] == 'received' ? 'وارد' : 'صادر'}',style:const TextStyle(color:gold,fontWeight:FontWeight.bold)),
          Text('رقم الشيك: ${row['number']} • البنك: ${row['bank']}'),
          Text('${(row['amount'] as num).toDouble().toStringAsFixed(2)} ج.م • الاستحقاق: $due'),
          Text(status,style:TextStyle(color:late ? Colors.redAccent : gold)),
          if(row['reminderEnabled'] == true && row['reminderAt'] is Timestamp && !completed) Text('التذكير: ${chequeTimeLabel(row['reminderAt'])}'),
          if('${row['note'] ?? ''}'.isNotEmpty) Text('${row['note']}'),
          Wrap(spacing:6,children:[TextButton.icon(onPressed:() => editChequeDialog(context,widget.uid,existing:row),icon:const Icon(Icons.edit),label:const Text('تعديل')),TextButton.icon(onPressed:() => changeChequeStatus(context,widget.uid,row,!completed),icon:Icon(completed ? Icons.restore : Icons.check_circle),label:Text(completed ? 'إعادة فتح' : 'تم التنفيذ')),IconButton(tooltip:'حذف الشيك',onPressed:() => deleteCheque(context,widget.uid,row),icon:const Icon(Icons.delete_outline,color:Colors.redAccent))]),
        ])));
      });
    })),
  ]);
}

Future<void> saveChequeRecord(String uid,Map<String,dynamic> item,{int? expectedRevision,bool remove=false}) async {
  final ref=db.collection('settings').doc('cheques_$uid');
  await db.runTransaction((tx) async {
    final snap=await tx.get(ref),profile=(await tx.get(db.collection('users').doc(uid))).data();
    if(FirebaseAuth.instance.currentUser?.uid != uid || profile?['role'] != 'owner' || profile?['active'] != true) throw StateError('مواعيد الشيكات متاحة للمدير فقط');
    final data=snap.data() ?? {}, rows=((data['records'] as List?) ?? []).map((r) => Map<String,dynamic>.from(r as Map)).toList();
    final edited=editChequeLedger(rows,item,(data['nextId'] as int?) ?? 1,expectedRevision:expectedRevision,remove:remove);
    planChequeReminders(edited.records,DateTime.now());
    tx.set(ref,{'kind':'chequeLedger','ownerId':uid,'records':edited.records,'nextId':edited.nextId,'updatedAt':FieldValue.serverTimestamp()});
  });
  await ChequeReminders.instance.refresh(uid);
}

Future<void> editChequeDialog(BuildContext context,String uid,{Map<String,dynamic>? existing}) async {
  final number=TextEditingController(text:existing?['number'] ?? ''),party=TextEditingController(text:existing?['party'] ?? ''),bank=TextEditingController(text:existing?['bank'] ?? ''),amount=TextEditingController(text:existing == null ? '' : '${existing['amount']}'),note=TextEditingController(text:existing?['note'] ?? '');
  final now=tz.TZDateTime.now(chequeZone),id=existing?['id'] ?? db.collection('settings').doc().id;
  DateTime due=existing == null ? DateTime(now.year,now.month,now.day+7) : DateTime.parse(existing['dueDate']);
  DateTime remind=existing?['reminderAt'] is Timestamp ? tz.TZDateTime.from((existing!['reminderAt'] as Timestamp).toDate(),chequeZone) : chequeReminderBefore(due,1,9,0);
  String type=existing?['type'] ?? 'issued';
  bool enabled=existing?['reminderEnabled'] ?? true,saving=false;
  int? days=existing == null ? 1 : existing['leadDays'] as int?;
  Future<void> pickReminder(BuildContext dialog,StateSetter update) async {
    final date=await showDatePicker(context:dialog,initialDate:DateTime(remind.year,remind.month,remind.day),firstDate:DateTime(2000),lastDate:DateTime(2100));
    if(date == null || !dialog.mounted) return;
    final time=await showTimePicker(context:dialog,initialTime:TimeOfDay(hour:remind.hour,minute:remind.minute));
    if(time != null && dialog.mounted) update(() { remind=tz.TZDateTime(chequeZone,date.year,date.month,date.day,time.hour,time.minute);days=null; });
  }
  await showDialog<void>(context:context,barrierDismissible:false,builder:(dialog) => StatefulBuilder(builder:(dialog,update) => AlertDialog(
    title:Text(existing == null ? 'تسجيل موعد شيك' : 'تعديل موعد الشيك'),
    content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      DropdownButtonFormField<String>(initialValue:type,isExpanded:true,decoration:const InputDecoration(labelText:'نوع الشيك'),items:const [DropdownMenuItem(value:'issued',child:Text('صادر — عليّ')),DropdownMenuItem(value:'received',child:Text('وارد — ليا'))],onChanged:saving ? null : (v) => update(() => type=v!)),
      TextField(controller:number,enabled:!saving,maxLength:60,decoration:const InputDecoration(labelText:'رقم الشيك *')),
      TextField(controller:party,enabled:!saving,maxLength:120,decoration:const InputDecoration(labelText:'اسم المستفيد / صاحب الشيك *')),
      TextField(controller:bank,enabled:!saving,maxLength:120,decoration:const InputDecoration(labelText:'البنك (اختياري)')),
      TextField(controller:amount,enabled:!saving,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'قيمة الشيك *')),
      OutlinedButton.icon(onPressed:saving ? null : () async { final date=await showDatePicker(context:dialog,initialDate:due,firstDate:DateTime(2000),lastDate:DateTime(2100));if(date != null && dialog.mounted) update(() {due=date;if(days != null) remind=chequeReminderBefore(due,days!,remind.hour,remind.minute);}); },icon:const Icon(Icons.calendar_month),label:Text('تاريخ الاستحقاق: ${chequeDate(due)}')),
      SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('تذكير على الموبايل'),value:enabled,onChanged:saving ? null : (v) => update(() => enabled=v)),
      if(enabled) ...[
        DropdownButtonFormField<int>(key:ValueKey(days),isExpanded:true,initialValue:days ?? -1,decoration:const InputDecoration(labelText:'وقت التذكير'),items:const [DropdownMenuItem(value:0,child:Text('يوم الاستحقاق')),DropdownMenuItem(value:1,child:Text('قبلها بيوم')),DropdownMenuItem(value:3,child:Text('قبلها بثلاثة أيام')),DropdownMenuItem(value:7,child:Text('قبلها بأسبوع')),DropdownMenuItem(value:-1,child:Text('تاريخ وساعة أحددهم'))],onChanged:saving ? null : (v) { if(v == -1) {update(() => days=null);pickReminder(dialog,update);} else if(v != null) update(() {days=v;remind=chequeReminderBefore(due,v,remind.hour,remind.minute);}); }),
        OutlinedButton.icon(onPressed:saving ? null : () => pickReminder(dialog,update),icon:const Icon(Icons.alarm),label:Text('التذكير: ${DateFormat('yyyy/MM/dd • HH:mm').format(remind)}')),
        const Text('بتوقيت القاهرة. الإشعار يحتاج السماح بإشعارات التطبيق والمنبهات.',style:TextStyle(fontSize:12)),
      ],
      TextField(controller:note,enabled:!saving,maxLength:300,maxLines:2,decoration:const InputDecoration(labelText:'ملاحظات')),
    ])),
    actions:[TextButton(onPressed:saving ? null : () => Navigator.pop(dialog),child:const Text('إلغاء')),FilledButton(onPressed:saving ? null : () async {
      final value=double.tryParse(_ocrNumber(amount.text.trim().replaceAll(',', '.')));
      if(number.text.trim().isEmpty || party.text.trim().isEmpty || value == null || !value.isFinite || value <= 0 || (value*100).round() <= 0 || value>1000000000000) { await showInvoiceSaveProblem(dialog,'اكتب رقم الشيك والاسم وقيمة صحيحة أكبر من صفر.',title:'موعد الشيك',button:'رجوع');return; }
      if(enabled && existing?['status'] != 'done' && (!remind.isAfter(DateTime.now()) || !remind.isBefore(tz.TZDateTime(chequeZone,due.year,due.month,due.day+1)))) { await showInvoiceSaveProblem(dialog,'اختر تذكيرًا في المستقبل ويكون قبل نهاية يوم استحقاق الشيك.',title:'وقت التذكير',button:'رجوع');return; }
      update(() => saving=true);
      try {
        await saveChequeRecord(uid,{'id':id,'number':number.text.trim(),'party':party.text.trim(),'bank':bank.text.trim(),'amount':(value*100).round()/100,'type':type,'dueDate':chequeDate(due),'reminderEnabled':enabled,'leadDays':days,'reminderAt':Timestamp.fromDate(remind),'status':existing?['status'] ?? 'open','note':note.text.trim()},expectedRevision:existing?['revision'] as int?);
        if(enabled && existing?['status'] != 'done') {
          try { await ChequeReminders.instance.requestPermissions(); } catch(e) {ChequeReminders.instance.warning.value='تم حفظ الشيك، لكن تعذر تفعيل تذكيره: $e';}
        }
        if(dialog.mounted) Navigator.pop(dialog);
        if(context.mounted) await showInvoiceSaveProblem(context,ChequeReminders.instance.warning.value == null ? 'تم حفظ موعد الشيك${enabled && existing?['status'] != 'done' ? ' وتفعيل تذكيره على هذا الموبايل' : ''}.' : 'تم حفظ موعد الشيك. ${ChequeReminders.instance.warning.value}',title:'مواعيد الشيكات',button:'تمام',success:true);
      } catch(e) {if(dialog.mounted) {update(() => saving=false);await showInvoiceSaveProblem(dialog,'تعذر حفظ الشيك: $e',title:'موعد الشيك',button:'رجوع');}}
    },child:Text(saving ? 'جارٍ الحفظ…' : 'حفظ الشيك'))],
  )));
  for(final c in [number,party,bank,amount,note]) {c.dispose();}
}

Future<void> changeChequeStatus(BuildContext context,String uid,Map<String,dynamic> row,bool done) async {
  try {
    await saveChequeRecord(uid,{'id':row['id'],'status':done ? 'done' : 'open'},expectedRevision:(row['revision'] as int?) ?? 0);
    if(context.mounted) await showInvoiceSaveProblem(context,done ? 'تم تسجيل تنفيذ الشيك وإلغاء تذكيره. سجّل السداد بسند صرف أو قبض عند الحاجة.' : 'تم إعادة فتح الشيك. راجع تاريخ التذكير لو فات موعده.',title:'مواعيد الشيكات',button:'تمام',success:true);
  } catch(e) {if(context.mounted) await showInvoiceSaveProblem(context,'تعذر تحديث الشيك: $e',title:'مواعيد الشيكات',button:'تمام');}
}
Future<void> deleteCheque(BuildContext context,String uid,Map<String,dynamic> row) async {
  final yes=await showDialog<bool>(context:context,builder:(dialog) => AlertDialog(title:const Text('حذف الشيك'),content:Text('حذف الشيك رقم ${row['number']} وإلغاء تذكيره؟'),actions:[TextButton(onPressed:() => Navigator.pop(dialog,false),child:const Text('إلغاء')),FilledButton(onPressed:() => Navigator.pop(dialog,true),child:const Text('حذف'))])) ?? false;
  if(!yes) return;
  try {await saveChequeRecord(uid,{'id':row['id']},expectedRevision:(row['revision'] as int?) ?? 0,remove:true);}
  catch(e) {if(context.mounted) await showInvoiceSaveProblem(context,'تعذر حذف الشيك: $e',title:'مواعيد الشيكات',button:'تمام');}
}
