part of 'main.dart';

// The employee explicitly registers the customer visit and agrees that the
// employee name, visit time and GPS position are visible to the manager.
// This class NEVER tracks a device or location in the background.
class EmployeeVisitAlertTracker {
  final Set<String> _known = <String>{};
  bool _ready = false;

  List<String> accept(Iterable<String> ids,
      {bool cached = false, bool pending = false}) {
    if (cached || pending) return const <String>[];
    final current = ids.toSet();
    final fresh = _ready ? current.difference(_known).toList() : <String>[];
    _known
      ..clear()
      ..addAll(current);
    _ready = true;
    return fresh;
  }
}

// Alerts the manager for successful, employee-submitted customer visits.
// Like other in-app notifications, this listener runs while the app is alive;
// background/closed-app push notifications require a separate FCM service.
class ManagerVisitAlerts {
  static final ManagerVisitAlerts instance = ManagerVisitAlerts();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  EmployeeVisitAlertTracker _tracker = EmployeeVisitAlertTracker();
  int _generation = 0;

  FlutterLocalNotificationsPlugin get _plugin =>
      ChequeReminders.instance.plugin;

  static const NotificationDetails details = NotificationDetails(
    android: AndroidNotificationDetails(
      'vib_manager_customer_visits_v1',
      'زيارات الموظفين للعملاء',
      channelDescription: 'تنبيه عند تسجيل زيارة عميل بواسطة الموظف',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: 'vib_notification',
      visibility: NotificationVisibility.private,
    ),
  );

  Future<void> watch() async {
    final generation = ++_generation;
    await _subscription?.cancel();
    _subscription = null;
    _tracker = EmployeeVisitAlertTracker();
    try {
      await ChequeReminders.instance.initialize();
      await ChequeReminders.instance.android
          ?.requestNotificationsPermission();
      if (generation != _generation) return;
      _subscription = db.collection('employeeVisits')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(includeMetadataChanges: true)
          .listen((snapshot) {
        if (generation != _generation) return;
        final ids = _tracker.accept(
          snapshot.docs.map((doc) => doc.id),
          cached: snapshot.metadata.isFromCache,
          pending: snapshot.metadata.hasPendingWrites,
        );
        if (ids.isEmpty) return;
        final freshIds = ids.toSet();
        final freshDocs = snapshot.docs
            .where((doc) => freshIds.contains(doc.id)).toList();
        if (freshDocs.isEmpty) return;
        // Limit bursts to one phone notification per snapshot.
        final row = freshDocs.first;
        unawaited(_notify(row.id, row.data(),
          additional: freshDocs.length - 1).catchError((Object error) {
          debugPrint('Manager visit notification failed: $error');
        }));
      }, onError: (Object error) {
        debugPrint('Manager visit listener failed: $error');
      });
    } catch (error) {
      debugPrint('Unable to start manager visit notifications: $error');
    }
  }

  Future<void> _notify(String id, Map<String, dynamic> visit,
      {int additional = 0}) async {
    if (await ChequeReminders.instance.android
        ?.areNotificationsEnabled() != true) return;
    final name = '${visit['employeeName'] ?? 'موظف'}';
    final customer = '${visit['customerName'] ?? 'عميل'}';
    final extra = additional > 0 ? ' • و${additional} زيارة أخرى' : '';
    var hash = 3;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) % 100000000;
    }
    await _plugin.show(
      1700000000 + hash,
      'زيارة عميل جديدة',
      '$name سجّل زيارة عند $customer$extra',
      details,
      payload: 'employeeVisit:$id',
    );
  }

  Future<void> stop() async {
    ++_generation;
    await _subscription?.cancel();
    _subscription = null;
  }
}
