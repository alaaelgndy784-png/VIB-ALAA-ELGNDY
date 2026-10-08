part of 'main.dart';

class ManagerConnectionStatus extends StatelessWidget {
  const ManagerConnectionStatus({super.key});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
      stream: db.collection('settings').doc('cash').snapshots(includeMetadataChanges: true),
      builder: (context, snapshot) {
        final offline = snapshot.hasError || (snapshot.hasData && snapshot.data!.metadata.isFromCache);
        final pendingWrites = snapshot.data?.metadata.hasPendingWrites == true;
        final label = snapshot.hasError ? 'تعذر الاتصال بالخادم' : offline ? 'عرض البيانات المخزنة؛ المبيعات والقبض والصرف والمصروفات المدعومة تُحفظ محليًا' : pendingWrites ? 'جارٍ مزامنة التغييرات' : 'متصل بالخادم';
        final icon = snapshot.hasError || offline ? Icons.cloud_off : pendingWrites ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined;
        return Tooltip(message: label, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(icon, color: offline ? Colors.orangeAccent : Colors.lightGreenAccent)));
      },
    ),
    AnimatedBuilder(animation: ManagerOfflineOutbox.instance, builder: (context, _) {
      final box = ManagerOfflineOutbox.instance;
      if (box.pendingCount == 0) return const SizedBox.shrink();
      return IconButton(
        tooltip: '${box.pendingCount} حركة بانتظار المزامنة أو المراجعة',
        onPressed: () => showManagerOfflineQueue(context),
        icon: Badge(label: Text('${box.pendingCount}'), child: Icon(
          box.hasReviewItems ? Icons.sync_problem : Icons.cloud_upload_outlined,
          color: box.hasReviewItems ? Colors.orangeAccent : gold)),
      );
    }),
  ]);
}

({double accountAfter, double cashAfter}) voucherCancellationBalances(
  num accountBalance, num cashBalance, num amount, {required bool receipt}) {
  if (!accountBalance.toDouble().isFinite || !cashBalance.toDouble().isFinite ||
      !amount.toDouble().isFinite || amount <= 0) {
    throw StateError('بيانات الرصيد أو قيمة السند غير صحيحة');
  }
  final amountCents = (amount * 100).round();
  final accountCents = (accountBalance * 100).round();
  final cashCents = (cashBalance * 100).round();
  return (
    accountAfter: (accountCents + amountCents) / 100,
    cashAfter: (cashCents + (receipt ? -amountCents : amountCents)) / 100,
  );
}

Future<String?> _askVoucherCancellationReason(BuildContext context, {
  required String title,
  required String details,
}) async {
  final reason = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(details),
        const SizedBox(height: 12),
        TextField(
          controller: reason,
          maxLength: 240,
          decoration: const InputDecoration(labelText: 'سبب الإلغاء (مطلوب)'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('رجوع')),
        FilledButton(
          onPressed: () {
            if (reason.text.trim().isEmpty) {
              ScaffoldMessenger.of(dialog).showSnackBar(
                const SnackBar(content: Text('اكتب سبب الإلغاء قبل التأكيد')),
              );
              return;
            }
            Navigator.pop(dialog, reason.text.trim());
          },
          child: const Text('تأكيد الإلغاء'),
        ),
      ],
    ),
  );
  reason.dispose();
  return result;
}

Future<void> cancelReceiptVoucher(
  BuildContext context,
  String receiptId,
) async {
  final reason = await _askVoucherCancellationReason(
    context,
    title: 'إلغاء سند القبض',
    details: 'سيظل السند الأصلي محفوظًا. سيُعاد المبلغ إلى مديونية العميل ويُخصم من الصندوق.',
  );
  if (reason == null || !context.mounted) return;
  try {
    final actor = FirebaseAuth.instance.currentUser?.uid;
    if (actor == null) throw StateError('سجّل الدخول كمدير أولًا');
    final marker = db.collection('voucherCancellations').doc('receipt_$receiptId');
    final receiptRef = db.collection('receipts').doc(receiptId);
    final cancellationCustomerMovement = db.collection('accountMovements').doc();
    final cancellationCashMovement = db.collection('accountMovements').doc();
    await db.runTransaction((tx) async {
      final markerSnapshot = await tx.get(marker);
      final receiptSnapshot = await tx.get(receiptRef);
      final userSnapshot = await tx.get(db.collection('users').doc(actor));
      if (markerSnapshot.exists) throw StateError('السند ملغي بالفعل');
      if (!receiptSnapshot.exists) throw StateError('سند القبض غير موجود');
      final user = userSnapshot.data();
      if (user?['role'] != 'owner' || user?['active'] != true) {
        throw StateError('إلغاء السند متاح للمدير فقط');
      }
      final receipt = receiptSnapshot.data()!;
      final customerId = '${receipt['customerId'] ?? ''}';
      final amountValue = receipt['amount'];
      if (customerId.isEmpty || amountValue is! num || !amountValue.isFinite || amountValue <= 0) {
        throw StateError('بيانات السند غير مكتملة؛ راجعه قبل الإلغاء');
      }
      final amountCents = (amountValue * 100).round();
      final amount = amountCents / 100;
      if (amountCents <= 0) throw StateError('قيمة السند غير صحيحة');
      final customerRef = db.collection('customers').doc(customerId);
      final cashRef = db.collection('settings').doc('cash');
      final customerSnapshot = await tx.get(customerRef);
      final cashSnapshot = await tx.get(cashRef);
      final invoiceId = '${receipt['invoiceId'] ?? ''}';
      DocumentSnapshot<Map<String, dynamic>>? invoiceSnapshot;
      if (invoiceId.isNotEmpty) {
        invoiceSnapshot = await tx.get(db.collection('sales').doc(invoiceId));
      }
      if (!customerSnapshot.exists) throw StateError('العميل المرتبط بالسند غير موجود');
      if (invoiceId.isNotEmpty &&
          (invoiceSnapshot == null || !invoiceSnapshot.exists ||
              invoiceSnapshot.data()?['receiptId'] != receiptId)) {
        throw StateError('السند مرتبط بفاتورة تحتاج مراجعة المدير قبل الإلغاء');
      }
      final customer = customerSnapshot.data()!;
      final customerBefore = (customer['balance'] as num?)?.toDouble();
      final cashBefore = (cashSnapshot.data()?['balance'] as num?)?.toDouble() ?? 0;
      if (customerBefore == null || !customerBefore.isFinite || !cashBefore.isFinite) {
        throw StateError('الرصيد الحالي غير صحيح؛ لا يمكن إلغاء السند');
      }
      final after = voucherCancellationBalances(customerBefore, cashBefore, amount, receipt: true);
      final customerAfter = after.accountAfter;
      final cashAfter = after.cashAfter;
      final now = FieldValue.serverTimestamp();
      tx.update(customerRef, {'balance': customerAfter, 'updatedAt': now});
      tx.set(cashRef, {'balance': cashAfter, 'updatedAt': now}, SetOptions(merge: true));
      tx.set(marker, {
        'voucherType': 'receipt', 'voucherId': receiptId, 'customerId': customerId,
        'amount': amount, 'reason': reason, 'actorId': actor,
        'actorName': user?['name'] ?? '', 'createdAt': now,
        'customerBalanceBefore': customerBefore, 'customerBalanceAfter': customerAfter,
        'cashBefore': cashBefore, 'cashAfter': cashAfter,
      });
      tx.set(cancellationCustomerMovement, {
        'accountType': 'customers', 'accountId': customerId,
        'accountName': receipt['customerName'] ?? customer['name'] ?? '',
        'kind': 'receiptCancellation', 'amount': amount,
        'balanceBefore': customerBefore, 'balanceAfter': customerAfter,
        'referenceId': receiptId, 'reason': reason, 'actorId': actor,
        'actorName': user?['name'] ?? '', 'createdAt': now,
      });
      tx.set(cancellationCashMovement, {
        'accountType': 'cash', 'accountId': customerId,
        'accountName': receipt['customerName'] ?? customer['name'] ?? '',
        'kind': 'customerCollectionCancellation', 'amount': amount,
        'delta': -amount, 'balanceBefore': cashBefore, 'balanceAfter': cashAfter,
        'referenceId': receiptId, 'reason': reason, 'actorId': actor,
        'actorName': user?['name'] ?? '', 'createdAt': now,
      });
      if (invoiceId.isNotEmpty && invoiceSnapshot != null) {
        final invoice = invoiceSnapshot.data()!;
        final paid = (invoice['receiptPaid'] as num?)?.toDouble() ?? amount;
        if (paid + 0.000001 < amount) throw StateError('قيمة التحصيل المرتبط لا تطابق السند');
        tx.update(db.collection('sales').doc(invoiceId), {
          'receiptId': FieldValue.delete(),
          'receiptPaid': ((paid * 100).round() - amountCents) / 100,
        });
      }
    });
    if (context.mounted) await showInvoiceSaveProblem(
      context, 'تم إلغاء السند وتسجيل الحركة العكسية. السند الأصلي ما زال محفوظًا للمراجعة.',
      title: 'تم إلغاء سند القبض', button: 'تمام', success: true,
    );
  } catch (e) {
    if (ManagerOfflineOutbox.isOfflineError(e)) {
      try {
        final synced = await submitManagerOfflineCommand(id:marker.id,kind:'receiptCancellation',payload:{
          'voucherId':receiptId,'customerMovementId':cancellationCustomerMovement.id,
          'cashMovementId':cancellationCashMovement.id,'reason':reason,
        });
        if (context.mounted) await showInvoiceSaveProblem(context,
          synced ? 'تمت مزامنة إلغاء السند.' : 'حُفظ طلب الإلغاء على الجهاز، وينتظر المزامنة عند رجوع الإنترنت.',
          title: 'إلغاء سند القبض', button: 'تمام', success: synced);
        return;
      } catch (queueError) {
        if (context.mounted) await showInvoiceSaveProblem(context,
          'تعذر حفظ طلب الإلغاء للمزامنة: $queueError', title: 'إلغاء سند القبض', button: 'تمام');
        return;
      }
    }
    if (context.mounted) await showInvoiceSaveProblem(
      context, 'تعذر إلغاء سند القبض: $e', title: 'إلغاء سند القبض', button: 'تمام',
    );
  }
}

Future<void> cancelSupplierPaymentVoucher(
  BuildContext context,
  String movementId,
) async {
  final reason = await _askVoucherCancellationReason(
    context,
    title: 'إلغاء سند الصرف',
    details: 'سيظل السند الأصلي محفوظًا. سيُعاد المبلغ إلى الصندوق وتُعاد مديونية المورد.',
  );
  if (reason == null || !context.mounted) return;
  try {
    final actor = FirebaseAuth.instance.currentUser?.uid;
    if (actor == null) throw StateError('سجّل الدخول كمدير أولًا');
    final marker = db.collection('voucherCancellations').doc('supplierPayment_$movementId');
    final voucherRef = db.collection('accountMovements').doc(movementId);
    final cancellationSupplierMovement = db.collection('accountMovements').doc();
    final cancellationCashMovement = db.collection('accountMovements').doc();
    await db.runTransaction((tx) async {
      final markerSnapshot = await tx.get(marker);
      final voucherSnapshot = await tx.get(voucherRef);
      final userSnapshot = await tx.get(db.collection('users').doc(actor));
      if (markerSnapshot.exists) throw StateError('السند ملغي بالفعل');
      if (!voucherSnapshot.exists) throw StateError('سند الصرف غير موجود');
      final user = userSnapshot.data();
      if (user?['role'] != 'owner' || user?['active'] != true) {
        throw StateError('إلغاء السند متاح للمدير فقط');
      }
      final voucher = voucherSnapshot.data()!;
      final supplierId = '${voucher['accountId'] ?? ''}';
      final amountValue = voucher['amount'];
      if (voucher['accountType'] != 'suppliers' || voucher['kind'] != 'payment' ||
          supplierId.isEmpty || amountValue is! num || !amountValue.isFinite || amountValue <= 0) {
        throw StateError('الحركة المحددة ليست سند صرف صالحًا');
      }
      final amountCents = (amountValue * 100).round();
      final amount = amountCents / 100;
      final supplierRef = db.collection('suppliers').doc(supplierId);
      final cashRef = db.collection('settings').doc('cash');
      final supplierSnapshot = await tx.get(supplierRef);
      final cashSnapshot = await tx.get(cashRef);
      if (!supplierSnapshot.exists) throw StateError('المورد المرتبط بالسند غير موجود');
      final supplier = supplierSnapshot.data()!;
      final supplierBefore = (supplier['balance'] as num?)?.toDouble();
      final cashBefore = (cashSnapshot.data()?['balance'] as num?)?.toDouble() ?? 0;
      if (supplierBefore == null || !supplierBefore.isFinite || !cashBefore.isFinite) {
        throw StateError('الرصيد الحالي غير صحيح؛ لا يمكن إلغاء السند');
      }
      final after = voucherCancellationBalances(supplierBefore, cashBefore, amount, receipt: false);
      final supplierAfter = after.accountAfter;
      final cashAfter = after.cashAfter;
      final now = FieldValue.serverTimestamp();
      tx.update(supplierRef, {'balance': supplierAfter, 'updatedAt': now});
      tx.set(cashRef, {'balance': cashAfter, 'updatedAt': now}, SetOptions(merge: true));
      tx.set(marker, {
        'voucherType': 'supplierPayment', 'voucherId': movementId, 'supplierId': supplierId,
        'amount': amount, 'reason': reason, 'actorId': actor,
        'actorName': user?['name'] ?? '', 'createdAt': now,
        'supplierBalanceBefore': supplierBefore, 'supplierBalanceAfter': supplierAfter,
        'cashBefore': cashBefore, 'cashAfter': cashAfter,
      });
      tx.set(cancellationSupplierMovement, {
        'accountType': 'suppliers', 'accountId': supplierId,
        'accountName': voucher['accountName'] ?? supplier['name'] ?? '',
        'kind': 'paymentCancellation', 'amount': amount,
        'balanceBefore': supplierBefore, 'balanceAfter': supplierAfter,
        'referenceId': movementId, 'reason': reason, 'actorId': actor,
        'actorName': user?['name'] ?? '', 'createdAt': now,
      });
      tx.set(cancellationCashMovement, {
        'accountType': 'cash', 'accountId': supplierId,
        'accountName': voucher['accountName'] ?? supplier['name'] ?? '',
        'kind': 'supplierPaymentCancellation', 'amount': amount,
        'delta': amount, 'balanceBefore': cashBefore, 'balanceAfter': cashAfter,
        'referenceId': movementId, 'reason': reason, 'actorId': actor,
        'actorName': user?['name'] ?? '', 'createdAt': now,
      });
    });
    if (context.mounted) await showInvoiceSaveProblem(
      context, 'تم إلغاء السند وتسجيل الحركة العكسية. السند الأصلي ما زال محفوظًا للمراجعة.',
      title: 'تم إلغاء سند الصرف', button: 'تمام', success: true,
    );
  } catch (e) {
    if (ManagerOfflineOutbox.isOfflineError(e)) {
      try {
        final synced = await submitManagerOfflineCommand(id:marker.id,kind:'supplierPaymentCancellation',payload:{
          'voucherId':movementId,'supplierMovementId':cancellationSupplierMovement.id,
          'cashMovementId':cancellationCashMovement.id,'reason':reason,
        });
        if (context.mounted) await showInvoiceSaveProblem(context,
          synced ? 'تمت مزامنة إلغاء السند.' : 'حُفظ طلب الإلغاء على الجهاز، وينتظر المزامنة عند رجوع الإنترنت.',
          title: 'إلغاء سند الصرف', button: 'تمام', success: synced);
        return;
      } catch (queueError) {
        if (context.mounted) await showInvoiceSaveProblem(context,
          'تعذر حفظ طلب الإلغاء للمزامنة: $queueError', title: 'إلغاء سند الصرف', button: 'تمام');
        return;
      }
    }
    if (context.mounted) await showInvoiceSaveProblem(
      context, 'تعذر إلغاء سند الصرف: $e', title: 'إلغاء سند الصرف', button: 'تمام',
    );
  }
}
