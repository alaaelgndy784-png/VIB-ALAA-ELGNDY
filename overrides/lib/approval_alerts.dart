part of 'main.dart';

// A new, server-confirmed pending request produces one message-style alert.
// Historical requests, offline snapshots and local uncommitted writes never ring.
class ApprovalAlertTracker {
  final Map<String, Set<String>> _known = {};
  final Set<String> _initialized = {};

  List<String> accept(String kind, Map<String, Map<String, dynamic>> entries,
      {bool cached = false, bool pending = false}) {
    if (cached || pending) return const [];
    final active = entries.entries.where((entry) {
      final data = entry.value;
      return data['status'] == 'pending' &&
          (kind != 'sales' || pendingSaleIsVisible(data));
    }).map((entry) => entry.key).toSet();
    final old = _known[kind] ?? <String>{};
    final fresh = _initialized.contains(kind)
        ? active.difference(old).toList() : <String>[];
    _known[kind] = active;
    _initialized.add(kind);
    fresh.sort();
    return fresh;
  }
}

class ManagerApprovalAlerts {
  static final ManagerApprovalAlerts instance = ManagerApprovalAlerts();
  ApprovalAlertTracker _tracker = ApprovalAlertTracker();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sales;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _receipts;
  Future<void> _queue = Future<void>.value();
  int _generation = 0;

  FlutterLocalNotificationsPlugin get plugin =>
      ChequeReminders.instance.plugin;

  // Android's *notification* sound, not the phone ringtone. Separate channel
  // so it can be changed/muted in Android Settings without affecting calls.
  static const notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'vib_manager_approvals_message_short_v1',
      'اعتمادات فواتير وسندات الموظفين',
      channelDescription: 'تنبيه رسالة لاعتماد فاتورة مبيعات أو سند قبض',
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
    await _sales?.cancel();
    await _receipts?.cancel();
    _sales = null;
    _receipts = null;
    _tracker = ApprovalAlertTracker();
    try {
      await ChequeReminders.instance.initialize();
      await ChequeReminders.instance.android
          ?.requestNotificationsPermission();
      if (generation != _generation) return;

      void handle(String kind,
          QuerySnapshot<Map<String, dynamic>> snapshot) {
        if (generation != _generation) return;
        final entries = <String, Map<String, dynamic>>{
          for (final doc in snapshot.docs) doc.id: doc.data(),
        };
        final newIds = _tracker.accept(kind, entries,
          cached: snapshot.metadata.isFromCache,
          pending: snapshot.metadata.hasPendingWrites);
        if (newIds.isEmpty) return;
        // A short alert for a burst of new requests, not a long ringtone
        // or a stream of 10+ tones on reconnect.
        final id = newIds.last;
        final count = newIds.length;
        final row = entries[id]!;
        _queue = _queue.then((_) async {
          if (generation != _generation) return;
          await notify(kind, id, row, additional: count - 1);
        }).catchError((Object e) {
          debugPrint('Unable to show approval notification: $e');
        });
      }

      _sales = pendingSalesQuery(true)
          .snapshots(includeMetadataChanges: true)
          .listen((snapshot) => handle('sales', snapshot),
              onError: (Object e) =>
                  debugPrint('Sales approval listener failed: $e'));
      _receipts = pendingReceiptQuery(true)
          .snapshots(includeMetadataChanges: true)
          .listen((snapshot) => handle('receipts', snapshot),
              onError: (Object e) =>
                  debugPrint('Receipt approval listener failed: $e'));
    } catch (e) {
      debugPrint('Unable to start manager approval alerts: $e');
    }
  }

  Future<void> notify(String kind, String id, Map<String, dynamic> data,
      {int additional = 0}) async {
    if (await ChequeReminders.instance.android
        ?.areNotificationsEnabled() != true) return;
    final sale = kind == 'sales';
    final name = '${data[sale ? 'employeeName' : 'actorName'] ?? 'الموظف'}';
    final party = '${data[sale ? 'customerName' : 'customerName'] ?? ''}';
    final amount = data[sale ? 'total' : 'amount'];
    final money = amount is num ? amount.toStringAsFixed(2) : '';
    final title = sale
        ? 'فاتورة موظف تنتظر الاعتماد'
        : 'سند قبض موظف ينتظر الاعتماد';
    final detail = [
      name,
      if (party.trim().isNotEmpty) party,
      if (money.isNotEmpty) '$money ج.م',
      if (additional > 0) 'ومعه $additional طلب آخر',
    ].join(' • ');
    var hash = sale ? 1 : 2;
    for (final c in id.codeUnits) {
      hash = (hash * 31 + c) % 100000000;
    }
    await plugin.show(
      1900000000 + hash, title, detail, notificationDetails,
      payload: 'approval:$kind:$id',
    );
  }

  Future<void> stop() async {
    ++_generation;
    await _sales?.cancel();
    await _receipts?.cancel();
    _sales = null;
    _receipts = null;
  }
}
