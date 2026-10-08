part of 'main.dart';

/// Durable, encrypted, manager-only queue for operations that require a
/// Firestore transaction. Commands are replayed in order after a server read
/// succeeds; each command carries stable document IDs so retries are safe.
class ManagerOfflineCommand {
  final String id, ownerUid, kind, createdAt, state;
  final Map<String, dynamic> payload;
  final String? error;

  const ManagerOfflineCommand({required this.id, required this.ownerUid,
    required this.kind, required this.createdAt, required this.state,
    required this.payload, this.error});

  factory ManagerOfflineCommand.fromJson(Map<String, dynamic> value) =>
      ManagerOfflineCommand(
        id: value['id'] as String,
        ownerUid: value['ownerUid'] as String,
        kind: value['kind'] as String,
        createdAt: value['createdAt'] as String,
        state: value['state'] as String? ?? 'pending',
        payload: Map<String, dynamic>.from(value['payload'] as Map),
        error: value['error'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'id': id, 'ownerUid': ownerUid, 'kind': kind, 'createdAt': createdAt,
    'state': state, 'payload': payload, if (error != null) 'error': error,
  };
}

class ManagerOfflineOutbox extends ChangeNotifier {
  ManagerOfflineOutbox._();
  static final instance = ManagerOfflineOutbox._();
  static const _secure = FlutterSecureStorage();
  static const _maxCommands = 100;
  String? _uid;
  List<ManagerOfflineCommand> _commands = [];
  bool _loaded = false, _syncing = false;
  List<ManagerOfflineCommand> get commands => List.unmodifiable(_commands);
  int get pendingCount => _commands.length;
  bool get hasReviewItems => _commands.any((x) => x.state == 'needsReview');
  bool contains(String id) => _commands.any((x) => x.id == id);
  String get _key => 'vib_manager_offline_outbox_${_uid ?? ''}';

  Future<void> bind(String uid) async {
    if (_loaded && _uid == uid) return;
    _uid = uid;
    final raw = await _secure.read(key: _key);
    if (raw == null || raw.isEmpty) {
      _commands = [];
    } else {
      final decoded = jsonDecode(raw) as List;
      _commands = decoded.map((x) => ManagerOfflineCommand.fromJson(
        Map<String, dynamic>.from(x as Map))).toList();
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    if (_uid == null) throw StateError('سجل دخول المدير أولًا');
    await _secure.write(key: _key,
      value: jsonEncode(_commands.map((x) => x.toJson()).toList()));
    notifyListeners();
  }

  Future<void> _put(ManagerOfflineCommand command) async {
    final index = _commands.indexWhere((x) => x.id == command.id);
    if (index < 0) {
      if (_commands.length >= _maxCommands) {
        throw StateError('قائمة الحركات المؤجلة ممتلئة؛ اتصل بالإنترنت لمزامنتها');
      }
      _commands.add(command);
    } else {
      _commands[index] = command;
    }
    await _save();
  }

  Future<bool> submit({required String id, required String kind,
    required Map<String, dynamic> payload}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجل دخول المدير أولًا');
    if (staffApp) throw StateError('الحفظ المؤجل متاح لتطبيق المدير فقط');
    await bind(uid);
    final command = ManagerOfflineCommand(id: id, ownerUid: uid, kind: kind,
      createdAt: DateTime.now().toUtc().toIso8601String(), state: 'pending',
      payload: Map<String, dynamic>.from(payload));
    await _put(command);
    await sync();
    final current = _commands.where((x) => x.id == id).firstOrNull;
    if (current != null && current.state == 'needsReview') {
      throw StateError(current.error ?? 'الحركة تحتاج مراجعة قبل المزامنة');
    }
    return current == null;
  }

  Future<void> sync() async {
    if (_syncing || !_loaded || _uid == null ||
        FirebaseAuth.instance.currentUser?.uid != _uid || staffApp) return;
    _syncing = true;
    try {
      try {
        final check = await db.collection('settings').doc('cash')
            .get(const GetOptions(source: Source.server));
        if (check.metadata.isFromCache) return;
      } catch (e) {
        if (isOfflineError(e)) return;
        rethrow;
      }
      for (final command in List<ManagerOfflineCommand>.from(_commands)) {
        if (command.state == 'needsReview') break;
        try {
          await _commit(command);
          _commands.removeWhere((x) => x.id == command.id);
          await _save();
        } catch (e) {
          if (isOfflineError(e)) break;
          final message = _shortError(e);
          await _put(ManagerOfflineCommand(id: command.id,
            ownerUid: command.ownerUid, kind: command.kind,
            createdAt: command.createdAt, state: 'needsReview',
            payload: command.payload, error: message));
          break;
        }
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _commit(ManagerOfflineCommand command) async {
    if (FirebaseAuth.instance.currentUser?.uid != command.ownerUid) {
      throw StateError('سجّل دخول نفس حساب المدير لمزامنة الحركة');
    }
    switch (command.kind) {
      case 'sale':
        final p = command.payload;
        final entries = (p['entries'] as List).map((raw) {
          final x = Map<String, dynamic>.from(raw as Map);
          return (id: x['id'] as String, name: x['name'] as String,
            qty: x['qty'] as int, price: (x['price'] as num).toDouble(),
            cost: (x['cost'] as num?)?.toDouble(),
            discount: (x['discount'] as num).toDouble(),
            basePrice: (x['basePrice'] as num).toDouble());
        }).toList();
        await commitGroupedSale(owner: true, branchId: p['branchId'] as String,
          entries: entries, total: (p['total'] as num).toDouble(),
          payment: (p['payment'] as num).toDouble(), credit: p['credit'] as bool,
          customerId: p['customerId'] as String,
          saleRef: db.collection('sales').doc(p['saleId'] as String),
          invoiceNote: p['invoiceNote'] as String? ?? '',
          allowShortage: p['allowShortage'] as bool? ?? false,
          allowBelowCost: p['allowBelowCost'] as bool? ?? false,
          overrideReason: p['overrideReason'] as String? ?? '');
        return;
      case 'cashMovement':
        await _commitCashMovement(command);
        return;
      case 'customerReceipt':
        await _commitCustomerReceipt(command);
        return;
      case 'supplierPayment':
        await _commitSupplierPayment(command);
        return;
      case 'expense':
        await _commitExpense(command);
        return;
      default:
        throw StateError('نوع حركة مؤجلة غير معروف: ${command.kind}');
    }
  }

  Future<void> _commitCashMovement(ManagerOfflineCommand command) async {
    final p = command.payload, actor = command.ownerUid;
    final cashRef = db.collection('settings').doc('cash');
    final movementRef = db.collection('accountMovements').doc(p['movementId'] as String? ?? command.id);
    await db.runTransaction((tx) async {
      if ((await tx.get(movementRef)).exists) return;
      final user = (await tx.get(db.collection('users').doc(actor))).data();
      if (user?['role'] != 'owner' || user?['active'] != true) throw StateError('الحركة متاحة للمدير فقط');
      final cash = (await tx.get(cashRef)).data();
      final before = ((cash?['balance'] as num?) ?? 0).toDouble();
      final amount = (p['amount'] as num).toDouble();
      final delta = (p['deposit'] as bool) ? amount : -amount;
      if (!amount.isFinite || amount <= 0 || before + delta < 0) throw StateError('راجع المبلغ ورصيد الصندوق');
      tx.set(cashRef, {'balance': before + delta, 'updatedAt': FieldValue.serverTimestamp()});
      tx.set(movementRef, {'accountType': 'cash', 'kind': p['deposit'] == true ? 'deposit' : 'withdrawal',
        'amount': amount, 'delta': delta, 'balanceBefore': before, 'balanceAfter': before + delta,
        'reason': p['reason'], 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
    });
  }

  Future<void> _commitCustomerReceipt(ManagerOfflineCommand command) async {
    final p = command.payload, actor = command.ownerUid;
    final receiptRef = db.collection('receipts').doc(p['receiptId'] as String);
    final customerRef = db.collection('customers').doc(p['customerId'] as String);
    final cashRef = db.collection('settings').doc('cash');
    final customerMovement = db.collection('accountMovements').doc(p['customerMovementId'] as String);
    final cashMovement = db.collection('accountMovements').doc(p['cashMovementId'] as String);
    final receiptDate = Timestamp.fromMillisecondsSinceEpoch(p['receiptDate'] as int);
    final amount = (p['amount'] as num).toDouble();
    await db.runTransaction((tx) async {
      if ((await tx.get(receiptRef)).exists) return;
      final user = (await tx.get(db.collection('users').doc(actor))).data();
      final customer = await tx.get(customerRef), cash = await tx.get(cashRef);
      if (user?['role'] != 'owner' || user?['active'] != true) throw StateError('سند القبض متاح للمدير فقط');
      if (!customer.exists || customer.data()?['active'] == false) throw StateError('العميل غير متاح');
      final data = customer.data()!, balance = ((data['balance'] as num?) ?? 0).toDouble();
      if (!amount.isFinite || amount <= 0 || amount > balance) throw StateError('المبلغ أكبر من المديونية الحالية للعميل');
      final beforeCash = ((cash.data()?['balance'] as num?) ?? 0).toDouble();
      final name = '${data['name'] ?? ''}', phone = '${data['phone'] ?? ''}';
      final now = FieldValue.serverTimestamp();
      final number = 'VIB-RC-${DateFormat('yyyyMMdd').format(receiptDate.toDate())}-${receiptRef.id.substring(0,6).toUpperCase()}';
      tx.update(customerRef, {'balance': balance - amount, 'lastReceiptId': receiptRef.id, 'updatedAt': now});
      tx.set(cashRef, {'balance': beforeCash + amount, 'lastReceiptId': receiptRef.id, 'updatedAt': now}, SetOptions(merge: true));
      tx.set(receiptRef, {'customerId': customerRef.id, 'customerName': name, 'customerPhone': phone,
        'receiptDate': receiptDate, 'amount': amount, 'balanceBefore': balance, 'balanceAfter': balance - amount,
        'cashBefore': beforeCash, 'cashAfter': beforeCash + amount, 'actorId': actor,
        'actorName': '${user?['name'] ?? ''}', 'branchId': p['branchId'], 'note': p['note'],
        'paymentMethod': p['paymentMethod'], 'receiptNumber': number, 'createdAt': now,
        'customerMovementId': customerMovement.id, 'cashMovementId': cashMovement.id});
      tx.set(customerMovement, {'accountType': 'customers', 'accountId': customerRef.id, 'accountName': name,
        'kind': 'collection', 'amount': amount, 'balanceBefore': balance, 'balanceAfter': balance - amount,
        'referenceId': receiptRef.id, 'actorId': actor, 'branchId': p['branchId'], 'createdAt': now, 'receiptDate': receiptDate});
      tx.set(cashMovement, {'accountType': 'cash', 'accountId': customerRef.id, 'accountName': name,
        'kind': 'customerCollection', 'amount': amount, 'delta': amount, 'balanceBefore': beforeCash,
        'balanceAfter': beforeCash + amount, 'referenceId': receiptRef.id, 'reason': 'سند قبض من عميل',
        'actorId': actor, 'branchId': p['branchId'], 'createdAt': now, 'receiptDate': receiptDate});
    });
  }

  Future<void> _commitSupplierPayment(ManagerOfflineCommand command) async {
    final p = command.payload, actor = command.ownerUid;
    final voucherRef = db.collection('accountMovements').doc(p['voucherId'] as String);
    final cashMovement = db.collection('accountMovements').doc(p['cashMovementId'] as String);
    final supplierRef = db.collection('suppliers').doc(p['supplierId'] as String);
    final cashRef = db.collection('settings').doc('cash');
    final paid = (p['amount'] as num).toDouble();
    await db.runTransaction((tx) async {
      final existing = await tx.get(voucherRef);
      if (existing.exists) {
        if (existing.data()?['accountId'] != supplierRef.id || existing.data()?['amount'] != paid) throw StateError('سند الصرف موجود ببيانات مختلفة');
        return;
      }
      final user = (await tx.get(db.collection('users').doc(actor))).data();
      final supplier = await tx.get(supplierRef), cash = await tx.get(cashRef);
      if (user?['role'] != 'owner' || user?['active'] != true) throw StateError('سند الصرف متاح للمدير فقط');
      if (!supplier.exists || supplier.data()?['active'] == false) throw StateError('المورد غير متاح');
      final data = supplier.data()!, balance = ((data['balance'] as num?) ?? 0).toDouble();
      final beforeCash = ((cash.data()?['balance'] as num?) ?? 0).toDouble();
      final after = supplierPaymentBalances(balance, beforeCash, paid);
      final now = FieldValue.serverTimestamp(), name = '${data['name'] ?? ''}';
      tx.update(supplierRef, {'balance': after.supplierAfter, 'updatedAt': now});
      tx.set(cashRef, {'balance': after.cashAfter, 'updatedAt': now}, SetOptions(merge: true));
      tx.set(voucherRef, {'accountType': 'suppliers', 'accountId': supplierRef.id, 'accountName': name,
        'supplierPhone': data['phone'] ?? '', 'kind': 'payment', 'amount': paid,
        'balanceBefore': balance, 'balanceAfter': after.supplierAfter, 'cashBefore': beforeCash,
        'cashAfter': after.cashAfter, 'referenceId': voucherRef.id, 'cashMovementId': cashMovement.id,
        'note': p['note'], 'actorId': actor, 'actorName': user?['name'] ?? '', 'createdAt': now});
      tx.set(cashMovement, {'accountType': 'cash', 'accountId': supplierRef.id, 'accountName': name,
        'kind': 'supplierPayment', 'amount': paid, 'delta': -paid, 'balanceBefore': beforeCash,
        'balanceAfter': after.cashAfter, 'referenceId': voucherRef.id, 'reason': 'سند صرف لمورد',
        'actorId': actor, 'createdAt': now});
    });
  }

  Future<void> _commitExpense(ManagerOfflineCommand command) async {
    final p = command.payload, actor = command.ownerUid;
    final expenseRef = db.collection('accountMovements').doc(p['expenseId'] as String);
    final cashMovement = db.collection('accountMovements').doc(p['cashMovementId'] as String);
    final cashRef = db.collection('settings').doc('cash');
    final amount = (p['amount'] as num).toDouble();
    await db.runTransaction((tx) async {
      if ((await tx.get(expenseRef)).exists) return;
      final user = (await tx.get(db.collection('users').doc(actor))).data();
      final cash = (await tx.get(cashRef)).data();
      if (user?['role'] != 'owner' || user?['active'] != true) throw StateError('تسجيل المصروف متاح للمدير فقط');
      final before = ((cash?['balance'] as num?) ?? 0).toDouble();
      if (!amount.isFinite || amount <= 0 || before < amount) throw StateError('رصيد الصندوق غير كافٍ للمصروف');
      final now = FieldValue.serverTimestamp();
      tx.set(cashRef, {'balance': before - amount, 'updatedAt': now}, SetOptions(merge: true));
      tx.set(expenseRef, {'accountType': 'expenses', 'category': p['category'], 'reason': p['reason'],
        'amount': amount, 'actorId': actor, 'createdAt': now});
      tx.set(cashMovement, {'accountType': 'cash', 'kind': 'expense', 'accountId': expenseRef.id,
        'accountName': p['category'], 'amount': amount, 'delta': -amount,
        'balanceBefore': before, 'balanceAfter': before - amount, 'reason': p['reason'],
        'actorId': actor, 'createdAt': now});
    });
  }

  Future<void> dismissForReview(String id) async {
    _commands.removeWhere((x) => x.id == id && x.state == 'needsReview');
    await _save();
  }

  static bool isOfflineError(Object error) {
    if (error is SocketException || error is TimeoutException) return true;
    if (error is FirebaseException) return const {
      'unavailable', 'deadline-exceeded', 'network-request-failed', 'cancelled',
    }.contains(error.code);
    return false;
  }

  static String _shortError(Object error) => error.toString()
      .replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '').trim();
}

Future<void> runManagerOfflineCommand({required String id, required String kind,
  required Map<String, dynamic> payload}) async {
  await ManagerOfflineOutbox.instance.submit(id: id, kind: kind, payload: payload);
}

Future<bool> submitManagerOfflineCommand({required String id, required String kind,
  required Map<String, dynamic> payload}) => ManagerOfflineOutbox.instance.submit(
    id: id, kind: kind, payload: payload);

class ManagerOutboxSyncer extends StatefulWidget {
  final Widget child;
  const ManagerOutboxSyncer({super.key, required this.child});
  @override State<ManagerOutboxSyncer> createState() => _ManagerOutboxSyncerState();
}

class _ManagerOutboxSyncerState extends State<ManagerOutboxSyncer> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  @override void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && !staffApp) {
      unawaited(ManagerOfflineOutbox.instance.bind(uid).then((_) => ManagerOfflineOutbox.instance.sync()));
      _subscription = db.collection('settings').doc('cash')
        .snapshots(includeMetadataChanges: true).listen((snapshot) {
          if (!snapshot.metadata.isFromCache) unawaited(ManagerOfflineOutbox.instance.sync());
        }, onError: (_) {});
    }
  }
  @override void dispose() { _subscription?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) => widget.child;
}

Future<void> showManagerOfflineQueue(BuildContext context) async {
  final box = ManagerOfflineOutbox.instance;
  await showDialog<void>(context: context, builder: (dialog) => AnimatedBuilder(
    animation: box, builder: (context, _) => AlertDialog(
      title: const Text('الحركات المحفوظة على الجهاز'),
      content: SizedBox(width: 480, child: box.commands.isEmpty
        ? const Text('لا توجد حركات معلقة.')
        : ListView(shrinkWrap: true, children: [
            for (final item in box.commands) ListTile(
              leading: Icon(item.state == 'needsReview' ? Icons.error_outline : Icons.cloud_upload_outlined,
                color: item.state == 'needsReview' ? Colors.orangeAccent : gold),
              title: Text(item.kind == 'sale' ? 'فاتورة مبيعات' : item.kind == 'customerReceipt' ? 'سند قبض' : item.kind == 'supplierPayment' ? 'سند صرف مورد' : item.kind == 'expense' ? 'مصروف' : 'حركة صندوق'),
              subtitle: Text(item.error ?? 'بانتظار الاتصال والمزامنة'),
              trailing: item.state == 'needsReview' ? IconButton(tooltip: 'إزالة من قائمة المراجعة',
                onPressed: () => box.dismissForReview(item.id), icon: const Icon(Icons.delete_outline)) : null,
            ),
          ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إغلاق'))],
    )));
}
