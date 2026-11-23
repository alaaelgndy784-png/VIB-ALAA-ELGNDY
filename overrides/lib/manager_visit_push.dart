part of 'main.dart';

// Firebase notifications are shown by Android when the manager app is in the
// background. In the foreground, the app shows the same alert locally.
class ManagerVisitPushNotifications {
  static final ManagerVisitPushNotifications instance =
      ManagerVisitPushNotifications();
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _foreground;
  int _generation = 0;
  String? _lastToken;

  static const String channelId = 'vib_manager_visit_push_v1';
  static const AndroidNotificationChannel channel = AndroidNotificationChannel(
    channelId,
    'زيارات الموظفين',
    description: 'تنبيه باسم الموظف والتاجر عند تسجيل زيارة',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );
  static const NotificationDetails details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId, 'زيارات الموظفين',
      channelDescription: 'تنبيه باسم الموظف والتاجر عند تسجيل زيارة',
      importance: Importance.high, priority: Priority.high,
      playSound: true, enableVibration: true,
      icon: 'vib_notification',
      visibility: NotificationVisibility.private,
    ),
  );

  Future<void> watch(String ownerUid) async {
    final generation = ++_generation;
    await _foreground?.cancel();
    await _tokenRefresh?.cancel();
    _foreground = null;
    _tokenRefresh = null;
    if (staffApp || FirebaseAuth.instance.currentUser?.uid != ownerUid) return;
    try {
      await ChequeReminders.instance.initialize();
      final plugin = ChequeReminders.instance.plugin;
      await plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
      final fcm = FirebaseMessaging.instance;
      await fcm.requestPermission(alert: true, sound: true, badge: true);
      if (generation != _generation) return;
      _foreground = FirebaseMessaging.onMessage.listen((message) {
        if (generation != _generation ||
            message.data['type'] != 'employee_visit') return;
        final notice = message.notification;
        if (notice == null) return;
        var id = 19;
        for (final unit in (message.messageId ??
            message.data['visitId'] ?? '').codeUnits) {
          id = (id * 31 + unit) % 100000000;
        }
        unawaited(plugin.show(1600000000 + id, notice.title, notice.body,
          details, payload: 'employeeVisit:${message.data['visitId'] ?? ''}'));
      });
      _tokenRefresh = fcm.onTokenRefresh.listen((token) {
        if (generation == _generation) {
          unawaited(_saveToken(ownerUid, token));
        }
      });
      final token = await fcm.getToken();
      if (generation == _generation && token != null && token.isNotEmpty) {
        await _saveToken(ownerUid, token);
      }
    } catch (error) {
      debugPrint('Manager visit push setup failed: $error');
    }
  }

  Future<void> _saveToken(String ownerUid, String token) async {
    if (FirebaseAuth.instance.currentUser?.uid != ownerUid ||
        token.trim().isEmpty || staffApp) return;
    try {
      await db.collection('users').doc(ownerUid)
          .update({'managerFcmToken': token});
      _lastToken = token;
    } catch (error) {
      debugPrint('Unable to register manager visit notification token: $error');
    }
  }

  Future<void> unregister(String uid) async {
    // Clear a token before account switching so another user cannot receive
    // the previous manager's visit notifications on this phone.
    if (FirebaseAuth.instance.currentUser?.uid == uid && _lastToken != null) {
      try {
        final profile = await db.collection('users').doc(uid).get();
        if (profile.data()?['managerFcmToken'] == _lastToken) {
          await db.collection('users').doc(uid).update({
            'managerFcmToken': FieldValue.delete(),
          });
        }
      } catch (error) {
        debugPrint('Unable to clear manager token on sign out: $error');
      }
    }
    await stop();
  }

  Future<void> stop() async {
    ++_generation;
    await _tokenRefresh?.cancel();
    await _foreground?.cancel();
    _tokenRefresh = null;
    _foreground = null;
  }
}
