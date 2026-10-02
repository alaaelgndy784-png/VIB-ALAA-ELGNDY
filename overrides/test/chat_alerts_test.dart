import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../lib/main.dart';

Map<String,dynamic> message(String id,{String sender='owner',String role='owner',bool read=false}) => {
  'lastMessageId':id,'lastSenderId':sender,'lastSenderRole':role,'lastMessageAt':Timestamp(100,0),
  if(read)'employeeReadAt':Timestamp(100,0),'employeeName':'أحمد','lastText':'رسالة صوتية',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('opening chat does not ring for history; confirmed new message rings once',() {
    final tracker=ChatAlertTracker(uid:'employee',owner:false);
    expect(tracker.accept({'employee':message('old')},cached:true),isEmpty);
    expect(tracker.accept({'employee':message('old')}),isEmpty);
    expect(tracker.accept({'employee':message('new')},pending:true),isEmpty);
    expect(tracker.accept({'employee':message('new')}).length,1);
    expect(tracker.accept({'employee':message('new')}),isEmpty);
    expect(tracker.accept({'employee':message('new',read:true)}),isEmpty);
  });
  test('own outgoing messages and read updates do not ring',() {
    final tracker=ChatAlertTracker(uid:'employee',owner:false);
    tracker.accept({});
    expect(tracker.accept({'employee':message('self',sender:'employee',role:'employee')}),isEmpty);
    expect(tracker.accept({'employee':message('read',read:true)}),isEmpty);
    expect(tracker.accept({'employee':message('incoming')}).length,1);
  });
  test('manager gets incoming employee alerts including a newly created thread',() {
    final tracker=ChatAlertTracker(uid:'manager',owner:true);tracker.accept({});
    expect(tracker.accept({'employee':message('one',sender:'employee',role:'employee')}).single.key,'employee');
    expect(tracker.accept({'employee':message('reply',sender:'manager',role:'owner')}),isEmpty);
  });
  test('native chat notification requests sound and vibration, denial shows warning',() async {
    debugDefaultTargetPlatformOverride=TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance=AndroidFlutterLocalNotificationsPlugin();
    const channel=MethodChannel('dexterous.com/flutter/local_notifications');
    final calls=<MethodCall>[];var allowed=true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async {
      calls.add(call);if(call.method=='initialize')return true;
      if(call.method=='areNotificationsEnabled' || call.method=='requestNotificationsPermission')return allowed;
      return null;
    });
    try {
      final service=ChatAlerts();await service.test();
      final shown=Map<String,dynamic>.from(calls.singleWhere((c)=>c.method=='show').arguments as Map);
      final native=Map<String,dynamic>.from(shown['platformSpecifics'] as Map);
      expect(native['channelId'],'vib_chat_v1');expect(native['playSound'],true);expect(native['enableVibration'],true);
      calls.clear();allowed=false;await service.notify('employee',message('two'),false);
      expect(calls.where((c)=>c.method=='show'),isEmpty);expect(service.warning.value,isNotNull);
      await expectLater(service.test(),throwsStateError);
    } finally {
      debugDefaultTargetPlatformOverride=null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
    }
  });
}
