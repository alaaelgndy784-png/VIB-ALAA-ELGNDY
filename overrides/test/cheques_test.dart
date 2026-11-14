import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../lib/main.dart';

Map<String,dynamic> cheque({String id='one',int notificationId=1,DateTime? when,String status='open',bool enabled=true}) => {
  'id':id,'notificationId':notificationId,'number':'123','party':'مورد أدوات صحية','bank':'البنك',
  'amount':1000.50,'dueDate':'2026-11-01','type':'issued','status':status,'revision':0,
  'reminderEnabled':enabled,'reminderAt':Timestamp.fromDate(when ?? DateTime.utc(2026,10,31,7)),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeChequeTimeZones);
  test('calendar lead days preserve 9am Cairo across DST and month boundary',() {
    final before=chequeReminderBefore(DateTime(2026,10,30),1,9,0);
    final due=chequeReminderBefore(DateTime(2026,10,30),0,9,0);
    expect(before.day,29);expect(before.hour,9);expect(due.hour,9);
    expect(before.timeZoneOffset,const Duration(hours:3));expect(due.timeZoneOffset,const Duration(hours:2));
    expect(due.difference(before),const Duration(hours:25));
    final month=chequeReminderBefore(DateTime(2027,1,1),3,15,30);
    expect(chequeDate(month),'2026-12-29');expect(month.hour,15);expect(month.minute,30);
  });
  test('only future enabled uncompleted cheques are planned in date order',() {
    final now=DateTime.utc(2026,10,1);
    final rows=[cheque(when:now.add(const Duration(days:5))),cheque(id:'two',notificationId:2,when:now.add(const Duration(days:2))),cheque(id:'paid',notificationId:3,status:'done'),cheque(id:'disabled',notificationId:4,enabled:false),cheque(id:'past',notificationId:5,when:now.subtract(const Duration(minutes:1)))];
    final jobs=planChequeReminders(rows,now);
    expect(jobs.map((j) => j.id),[2,1]);expect(jobs.first.body,contains('1,000.50'));
    expect(() => planChequeReminders([cheque(),cheque(id:'collision')],now),throwsStateError);
    expect(() => planChequeReminders(List.generate(301,(i) => cheque(id:'$i',notificationId:i+1)),now),throwsStateError);
  });
  test('nearest cheque with an active reminder stays highlighted until marked done',(){
    final rows=<Map<String,dynamic>>[
      {'id':'far','dueDate':'2026-11-20','status':'open','reminderEnabled':true},
      {'id':'near','dueDate':'2026-10-10','status':'open','reminderEnabled':true},
      {'id':'disabled','dueDate':'2026-10-09','status':'open','reminderEnabled':false},
      {'id':'done','dueDate':'2026-10-09','status':'done','reminderEnabled':true},
    ];
    expect(nearestRemindedChequeId(rows,DateTime(2026,10,9)),'near');
    rows[1]['status']='done';
    expect(nearestRemindedChequeId(rows,DateTime(2026,10,9)),'far');
    rows[0]['status']='done';
    expect(nearestRemindedChequeId(rows,DateTime(2026,10,9)),isNull);
  });
  test('editing, completion and deletion retain notification identity and reject stale edits',() {
    final created=editChequeLedger([],{'id':'one','number':'1'},1);
    expect(created.records.single['notificationId'],1);expect(created.nextId,2);
    final retry=editChequeLedger(created.records,{'id':'one','number':'1'},created.nextId);
    expect(retry.nextId,2);expect(retry.records.length,1);
    final edited=editChequeLedger(created.records,{'id':'one','number':'2','notificationId':99},2,expectedRevision:0);
    expect(edited.records.single['notificationId'],1);expect(edited.records.single['revision'],1);
    expect(() => editChequeLedger(edited.records,{'id':'one','number':'3'},2,expectedRevision:0),throwsStateError);
    final done=editChequeLedger(edited.records,{'id':'one','status':'done'},2,expectedRevision:1);
    expect(done.records.single['revision'],2);
    expect(editChequeLedger(done.records,{'id':'one'},2,expectedRevision:2,remove:true).records,isEmpty);
  });


  group('issued cheque paid by transfer, original still at merchant',() {
    test('new and existing completed cheques are grouped without losing legacy data',() {
      final pending=cheque();
      final oldDone=cheque(id:'old',status:'done');
      final paid=chequeTransferPaidUpdate(pending,DateTime(2026,11,12),'IB-1738');
      final outstanding={...pending,...paid};
      expect(chequeAwaitingOriginal(outstanding),isTrue);
      expect(chequeInSection(outstanding,'waitingOriginal'),isTrue);
      expect(chequeInSection(outstanding,'done'),isFalse);
      expect(chequeInSection(outstanding,'open'),isFalse);
      expect(chequeInSection(oldDone,'done'),isTrue);
      expect(paid['status'],'done');
      expect(paid['transferReference'],'IB-1738');
      expect(paid['originalReceived'],isFalse);
      expect(paid.containsKey('cashBalance'),isFalse);
      expect(paid.containsKey('accountMovements'),isFalse);
    });

    test('physically returning the original closes custody but never touches money',() {
      final issued=cheque();
      final paid=chequeTransferPaidUpdate(issued,DateTime(2026,11,12),'transfer');
      final outstanding={...issued,...paid};
      final received=chequeOriginalReceivedUpdate(outstanding,DateTime(2026,11,14));
      final updated={...outstanding,...received};
      expect(chequeAwaitingOriginal(updated),isFalse);
      expect(chequeInSection(updated,'done'),isTrue);
      expect(received['originalReceivedDate'],'2026-11-14');
      expect(received['originalReminderAt'],isNull);
      expect(() => chequeOriginalReceivedUpdate(updated,DateTime(2026,11,14)),throwsStateError);
      expect(chequeReopenUpdate(updated)['settlementMethod'],isNull);
      expect(chequeReopenUpdate(updated)['status'],'open');
      expect(updated['amount'],1000.50);
    });

    test('an incoming cheque cannot be incorrectly marked paid by bank transfer',() {
      final incoming={...cheque(),'type':'received'};
      expect(() => chequeTransferPaidUpdate(incoming,DateTime(2026,11,12),''),throwsStateError);
    });

    test('bank-transfer pickup reminder replaces due reminder and stops once original is back',() {
      final now=DateTime.now();
      final original=cheque(when:now.add(const Duration(days:2)));
      final newReminder=Timestamp.fromDate(now.add(const Duration(days:4)));
      final fields=chequeTransferPaidUpdate(original,now.subtract(const Duration(days:1)),
        'tx-1',originalReminderAt:newReminder);
      final awaiting={...original,...fields};
      final reminders=planChequeReminders([awaiting],now);
      expect(reminders.length,1);
      expect(reminders.single.id,1);
      expect(reminders.single.title,'تذكير باستلام أصل شيك');
      expect(reminders.single.body,contains('أصله ما زال عند'));
      expect(reminders.single.payload,contains('awaiting-original'));
      final received={...awaiting,...chequeOriginalReceivedUpdate(awaiting,now)};
      expect(planChequeReminders([received],now),isEmpty);
      final noReminder={...original,...chequeTransferPaidUpdate(original,
        now.subtract(const Duration(days:1)),'',originalReminderAt:null)};
      expect(planChequeReminders([noReminder],now),isEmpty);
    });
  });

  group('native notification scheduling contract',() {
    const channel=MethodChannel('dexterous.com/flutter/local_notifications');
    late Map<int,Map<String,dynamic>> pending;
    late List<MethodCall> calls;
    var permission=true,exact=true;
    setUp(() {
      debugDefaultTargetPlatformOverride=TargetPlatform.android;
      FlutterLocalNotificationsPlatform.instance=AndroidFlutterLocalNotificationsPlugin();
      pending={99:{'id':99,'title':'other','body':'other','payload':'other-feature'}};calls=[];permission=true;exact=true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async {
        calls.add(call);
        if(call.method == 'initialize') return true;
        if(call.method == 'areNotificationsEnabled' || call.method == 'requestNotificationsPermission') return permission;
        if(call.method == 'canScheduleExactNotifications' || call.method == 'requestExactAlarmsPermission') return exact;
        if(call.method == 'pendingNotificationRequests') return pending.values.toList();
        if(call.method == 'zonedSchedule') {final a=Map<String,dynamic>.from(call.arguments as Map);pending[a['id']]={'id':a['id'],'title':a['title'],'body':a['body'],'payload':a['payload']};return null;}
        if(call.method == 'cancel') {pending.remove((call.arguments as Map)['id']);return null;}
        return null;
      });
    });
    tearDown(() {debugDefaultTargetPlatformOverride=null;TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);});
    test('same reminder schedules once; changing time replaces it and completion cancels it',() async {
      final service=ChequeReminders()..ownerId='owner';
      final row=cheque(when:DateTime.now().add(const Duration(days:7)));
      service.latest=[row];await service.synchronize();await service.synchronize();
      expect(calls.where((c) => c.method == 'zonedSchedule').length,1);
      expect(service.warning.value,isNull);
      service.latest=[{...row,'reminderAt':Timestamp.fromDate(DateTime.now().add(const Duration(days:8)))}];await service.synchronize();
      expect(calls.where((c) => c.method == 'zonedSchedule').length,2);
      service.latest=[{...row,'status':'done'}];await service.synchronize();
      expect(pending.containsKey(1),isFalse);expect(pending.containsKey(99),isTrue);
    });
    test('notification permission denial never reports reminders enabled',() async {
      permission=false;
      final service=ChequeReminders()..ownerId='owner'..latest=[cheque(when:DateTime.now().add(const Duration(days:7)))];
      await service.synchronize();
      expect(calls.where((c) => c.method == 'zonedSchedule'),isEmpty);
      expect(service.warning.value,contains('غير مفعل'));
    });
    test('denied exact alarm uses approximate scheduling and shows its status',() async {
      exact=false;
      final service=ChequeReminders()..ownerId='owner'..latest=[cheque(when:DateTime.now().add(const Duration(days:7)))];
      await service.synchronize();
      expect(calls.where((c) => c.method == 'zonedSchedule').length,1);
      expect(pending[1]?['payload'],endsWith(':approximate'));
      expect(service.warning.value,contains('تقريبي'));
      await service.stop();expect(pending.containsKey(1),isFalse);expect(pending.containsKey(99),isTrue);
    });
  });
}
