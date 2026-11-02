part of 'main.dart';

// Deliberate cancellation of a mistaken sale is distinct from a customer
// return. Keep the original invoice, its serial number, and a reversal audit.
bool saleInvoiceCanBeCancelled(Map<String, dynamic> sale) {
  if (sale['status'] != 'completed') return false;
  if (((sale['onlinePaid'] as num?) ?? 0) > 0 || sale['onlinePaymentEver'] == true) return false;
  if (((sale['partialReturnTotal'] as num?) ?? 0) > 0) return false;
  final partial = sale['partialReturnQuantities'];
  return partial is! Map || partial.isEmpty;
}

// Compare the actual financial facts, not Firestore map insertion order or
// unrelated invoice metadata (printing, numbering, presentation updates).
// The earlier raw jsonEncode(items) signature could reject an unchanged sale
// when the deserialized map key order changed between two server reads.
String saleCancellationFinancialSnapshot(Map<String, dynamic> sale) {
  int cents(dynamic value) => value is num && value.isFinite
      ? (value * 100).round() : -1;
  final items = _saleReturnInvoiceItems(sale);
  final rows = [
    for (final item in items)
      [
        '${item['productId'] ?? ''}',
        (item['quantity'] as num?)?.toInt() ?? -1,
        cents(item['unitPrice']),
        cents(item['lineTotal']),
      ],
  ];
  return jsonEncode([
    '${sale['status'] ?? ''}',
    '${sale['customerId'] ?? ''}',
    '${sale['branchId'] ?? ''}',
    '${sale['stockBranchId'] ?? ''}',
    cents(sale['total']), cents(sale['paid']), cents(sale['due']),
    cents(sale['receiptPaid'] ?? 0),
    sale['onlinePaymentEver'] == true,
    cents(sale['onlinePaid'] ?? 0),
    rows,
  ]);
}

// A cancelled receipt already reversed its own customer and cash movements.
// Never refund it again when cancelling the sale itself.
({double cash, double debt}) saleCancellationSettlement(Map<String, dynamic> sale) =>
  returnSettlement({...sale, 'receiptPaid': 0}, sales: true);

Future<List<String>> cancelledInvoiceReceiptIds(
    String invoiceId, Map<String, dynamic> sale) async {
  final linked = await db.collection('receipts')
      .where('invoiceId', isEqualTo: invoiceId)
      .get(const GetOptions(source: Source.server));
  if (linked.metadata.isFromCache || linked.metadata.hasPendingWrites) {
    throw StateError('لا يمكن التحقق من سندات القبض دون تأكيد السيرفر');
  }
  var recordedCents = 0;
  final ids = <String>[];
  for (final row in linked.docs) {
    final amount = row.data()['amount'];
    if (amount is! num || !amount.isFinite || amount <= 0) {
      throw StateError('سند قبض مرتبط بالفاتورة وبياناته غير صحيحة');
    }
    final cancellation = await db.collection('voucherCancellations')
        .doc('receipt_${row.id}').get(const GetOptions(source: Source.server));
    if (!cancellation.exists ||
        cancellation.data()?['type'] != 'receipt' ||
        cancellation.data()?['originalId'] != row.id) {
      throw StateError('فاتورة مرتبطة بسند قبض لم يُلغَ. ألغِ سند القبض من «سندات القبض» أولًا، ثم ارجع لإلغاء الفاتورة.');
    }
    recordedCents += (amount * 100).round();
    ids.add(row.id);
  }
  final linkedId = '${sale['receiptId'] ?? ''}'.trim();
  if (linkedId.isNotEmpty && !ids.contains(linkedId)) {
    throw StateError('هناك سند قبض مرتبط غير مطابق لسجلات الفاتورة. راجع سندات القبض قبل الإلغاء.');
  }
  final actualCents = (((sale['receiptPaid'] as num?) ?? 0) * 100).round();
  if (actualCents != recordedCents) {
    throw StateError('إجمالي سندات القبض لا يطابق المبالغ المرتبطة بالفاتورة؛ لا يمكن إلغاؤها بأمان قبل المراجعة.');
  }
  return ids;
}

Future<bool> confirmSalesInvoiceCancellation(BuildContext context, String invoiceId) async {
  try {
    final currentSnap = await db.collection('sales').doc(invoiceId)
        .get(const GetOptions(source: Source.server));
    final sale = currentSnap.data();
    if (sale == null || !visibleAfterReset(sale)) {
      throw StateError('الفاتورة غير موجودة أو تخص دورة سابقة');
    }
    if (!saleInvoiceCanBeCancelled(sale)) {
      throw StateError('لا يمكن إلغاء الفاتورة: يجب أن تكون مكتملة وبدون مرتجعات جزئية أو سداد بالكارت. الفاتورة الملغاة أو المرتجعة لا تُلغى مرة ثانية.');
    }
    final actor = FirebaseAuth.instance.currentUser?.uid;
    if (actor == null) throw StateError('سجّل الدخول بحساب المدير أولًا');
    final profile = (await db.collection('users').doc(actor)
        .get(const GetOptions(source: Source.server))).data();
    if (profile?['role'] != 'owner' || profile?['active'] != true) {
      throw StateError('إلغاء فواتير المبيعات متاح للمدير فقط');
    }
    final receiptIds = await cancelledInvoiceReceiptIds(invoiceId, sale);
    final settlement = saleCancellationSettlement(sale);
    final currentCustomerId = '${sale['customerId'] ?? ''}';
    if (settlement.debt > 0 && currentCustomerId.isEmpty) {
      throw StateError('فاتورة آجل دون حساب عميل مسجل؛ راجع الفاتورة قبل الإلغاء');
    }
    if (!context.mounted) return false;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: const Text('إلغاء فاتورة مبيعات أُنشئت بالخطأ'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('رقم الفاتورة: ${invoiceDisplayNumber('sales',invoiceId,sale)}'),
          Text('العميل: ${sale['customerName'] ?? 'بدون عميل'}'),
          Text('الإجمالي: ${sale['total'] ?? 0} ج.م'),
          const SizedBox(height: 8),
          const Text('سترجع جميع كميات الفاتورة إلى المخزون، وتُعكس المديونية وحركة الصندوق المحصلة من الفاتورة.'),
          Text('تخفيض دين العميل: ${settlement.debt.toStringAsFixed(2)} ج.م'),
          Text('المبلغ المطلوب رده من الصندوق: ${settlement.cash.toStringAsFixed(2)} ج.م'),
          if (receiptIds.isNotEmpty)
            const Text('سندات القبض المرتبطة أُلغيت بالفعل، لذلك لن تُعكس مبالغها مرة ثانية.',
              style: TextStyle(color: Colors.orangeAccent)),
          const Text('سيبقى رقم الفاتورة والسجل محفوظين بعلامة «ملغاة»، ولن يمكن إلغاؤها مرتين.',
            style: TextStyle(color: Colors.orangeAccent)),
          const SizedBox(height: 10),
          TextField(controller: reason, maxLength: 300,
            decoration: const InputDecoration(labelText: 'سبب الإلغاء (إلزامي)', hintText: 'مثال: فاتورة مكررة بالخطأ')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('تراجع')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('تأكيد إلغاء الفاتورة'),
            onPressed: () {
              if (reason.text.trim().length < 5) {
                ScaffoldMessenger.of(dialog).showSnackBar(
                  const SnackBar(content: Text('اكتب سبب الإلغاء بوضوح، 5 حروف على الأقل')));
                return;
              }
              Navigator.pop(dialog, true);
            },
          ),
        ],
      ),
    ) ?? false;
    final reasonText = reason.text.trim();
    reason.dispose();
    if (!confirmed || !context.mounted) return false;
    await returnInvoice('sales', invoiceId,
      expectedCancellationSnapshot: saleCancellationFinancialSnapshot(sale),
      cancellationReason: reasonText, cancelledReceiptIds: receiptIds);
    if (context.mounted) {
      await showInvoiceSaveProblem(context,
        'تم إلغاء الفاتورة وحفظ أصلها، وإرجاع الكميات للمخزون وعكس حساب العميل والصندوق. احتفظ برقم الفاتورة للرجوع لسجل الإلغاء.',
        title: 'تم إلغاء فاتورة المبيعات', button: 'تمام', success: true);
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      await showInvoiceSaveProblem(context,
        'لم تُلغَ الفاتورة ولم يُجرَ أي تعديل مقصود على حساباتها: $error',
        title: 'تعذر إلغاء الفاتورة', button: 'رجوع');
    }
    return false;
  }
}
