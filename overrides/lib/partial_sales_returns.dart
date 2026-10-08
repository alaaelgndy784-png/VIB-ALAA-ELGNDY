part of 'main.dart';

List<Map<String, dynamic>> _saleReturnInvoiceItems(Map<String, dynamic> invoice) {
  final raw = invoice['items'];
  final result = <Map<String, dynamic>>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is Map) result.add(Map<String, dynamic>.from(item));
    }
  }
  if (result.isEmpty) result.add({
    'productId': invoice['productId'],
    'productName': invoice['productName'],
    'quantity': invoice['quantity'] ?? 0,
    'unitPrice': invoice['unitPrice'] ?? 0,
    'lineTotal': invoice['total'] ?? 0,
  });
  return result;
}

Future<void> confirmPartialSalesReturn(BuildContext context, String id) async {
  try {
    final invoice = (await db.collection('sales').doc(id).get(const GetOptions(source: Source.server))).data();
    if (invoice == null || invoice['status'] == 'returned' || !visibleAfterReset(invoice)) {
      throw StateError('الفاتورة غير متاحة للمرتجع');
    }
    if (((invoice['onlinePaid'] as num?) ?? 0) > 0) {
      if (context.mounted) await showInvoiceSaveProblem(context,
        'الفاتورة لها سداد بالكارت. أتمم رد المبلغ من سجل جيديا قبل إرجاع الصنف.',
        title: 'رد الكارت أولًا', button: 'تمام');
      return;
    }
    final returned = await db.collection('salesReturns').where('sourceInvoiceId', isEqualTo: id)
        .get(const GetOptions(source: Source.server));
    final priorLines = returnedQuantitiesBySourceLine(returned.docs
        .where((d) => d.data()['returnType'] == 'partial')
        .map((d) => d.data()).toList());
    final items = _saleReturnInvoiceItems(invoice);
    final available = <int, int>{};
    for (var i = 0; i < items.length; i++) {
      final rawQty = items[i]['quantity'];
      final qty = rawQty is num && rawQty.isFinite ? rawQty.toInt() : 0;
      final remaining = qty - (priorLines[i] ?? 0);
      if (remaining > 0) available[i] = remaining;
    }
    if (available.isEmpty) throw StateError('تم إرجاع كل أصناف الفاتورة بالفعل');
    if (!context.mounted) return;
    final indexes = available.keys.toList();
    var selected = indexes.first;
    final quantity = TextEditingController(text: '1');
    final choice = await showDialog<Map<String, int>>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('إرجاع صنف من الفاتورة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(
            value: selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'الصنف'),
            items: indexes.map((i) => DropdownMenuItem<int>(
              value: i,
              child: Text('${items[i]['productName'] ?? 'صنف'} • المتاح للإرجاع ${available[i]}'),
            )).toList(),
            onChanged: (value) { if (value != null) setDialogState(() { selected = value; quantity.text = '1'; }); },
          ),
          const SizedBox(height: 10),
          TextField(controller: quantity, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'الكمية (المتاح ${available[selected]})')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            final qty = int.tryParse(quantity.text.trim());
            if (qty == null || qty < 1 || qty > (available[selected] ?? 0)) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('اكتب كمية صحيحة لا تتجاوز المتاح')));
              return;
            }
            Navigator.pop(dialogContext, {'sourceItemIndex': selected, 'quantity': qty});
          }, child: const Text('متابعة')),
        ],
      ),
    ));
    quantity.dispose();
    if (choice == null || !context.mounted) return;
    final index = choice['sourceItemIndex']!;
    final qty = choice['quantity']!;
    final row = items[index];
    final lineQty = (row['quantity'] as num?)?.toInt() ?? 0;
    final lineTotal = (row['lineTotal'] as num?)?.toDouble() ??
        lineQty * ((row['unitPrice'] as num?)?.toDouble() ?? 0);
    final returnValue = lineQty > 0 ? ((lineTotal * 100).round() * qty / lineQty).round() / 100 : 0.0;
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('تأكيد إرجاع الصنف'),
      content: Text('الصنف: ${row['productName'] ?? ''}\nالكمية: $qty\nقيمة الصنف: ${returnValue.toStringAsFixed(2)} ج.م\nسيُحدّث المخزون والذمة والصندوق حسب تسوية الفاتورة.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رجوع')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد الإرجاع'))],
    )) ?? false;
    if (!yes || !context.mounted) return;
    await returnSalesInvoiceItem(id, index, qty);
    if (context.mounted) await showInvoiceSaveProblem(context,
      'تم إرجاع الصنف وتحديث المخزون والذمة والصندوق، مع حفظ الفاتورة الأصلية.',
      title: 'تم تسجيل مرتجع الصنف', button: 'تمام', success: true);
  } catch (e) {
    if (context.mounted) await showInvoiceSaveProblem(context, 'تعذر إرجاع الصنف: $e',
      title: 'لم يتم تسجيل المرتجع', button: 'رجوع');
  }
}

Future<void> returnSalesInvoiceItem(String id, int sourceItemIndex, int quantity) async {
  if (sourceItemIndex < 0 || quantity <= 0) throw StateError('بيانات الصنف غير صحيحة');
  final actor = FirebaseAuth.instance.currentUser!.uid;
  final invoiceRef = db.collection('sales').doc(id);
  await db.runTransaction((tx) async {
    final invoiceSnap = await tx.get(invoiceRef);
    final d = invoiceSnap.data();
    if (d == null || d['status'] == 'returned' || !visibleAfterReset(d)) throw StateError('الفاتورة غير متاحة للمرتجع');
    final profileSnap = await tx.get(db.collection('users').doc(actor));
    if (profileSnap.data()?['active'] != true || profileSnap.data()?['role'] != 'owner') throw StateError('المرتجعات للمدير فقط');
    if (((d['onlinePaid'] as num?) ?? 0) > 0) throw StateError('يجب تأكيد رد مبلغ الكارت أولًا');

    final returnedByLine = <int, int>{};
    final rawReturnedQuantities = d['partialReturnQuantities'];
    if (rawReturnedQuantities is Map) {
      for (final entry in rawReturnedQuantities.entries) {
        final lineIndex = int.tryParse('${entry.key}');
        final returnedQty = entry.value;
        if (lineIndex != null && returnedQty is num && returnedQty.isFinite && returnedQty >= 0) {
          returnedByLine[lineIndex] = returnedQty.toInt();
        }
      }
    }
    final items = _saleReturnInvoiceItems(d);
    if (sourceItemIndex >= items.length) throw StateError('الصنف غير موجود في الفاتورة');
    final item = items[sourceItemIndex];
    final sourceQty = (item['quantity'] as num?)?.toInt() ?? 0;
    final alreadyReturned = returnedByLine[sourceItemIndex] ?? 0;
    if (sourceQty <= 0 || quantity > sourceQty - alreadyReturned) throw StateError('الكمية المطلوبة أكبر من المتبقي في الفاتورة');
    final productId = '${item['productId'] ?? ''}';
    if (productId.isEmpty || productId == 'null') throw StateError('الصنف لا يحتوي على رمز مخزون');

    final branchId = '${d['stockBranchId'] ?? d['branchId'] ?? ''}';
    if (branchId.isEmpty || branchId == 'null') throw StateError('مخزون الفاتورة غير مسجل');
    final stockRef = db.collection('stock').doc('${branchId}_$productId');
    final stockSnap = await tx.get(stockRef);
    final customerId = '${d['customerId'] ?? ''}';
    final customerRef = customerId.isEmpty ? null : db.collection('customers').doc(customerId);
    final customerSnap = customerRef == null ? null : await tx.get(customerRef);
    final cashRef = db.collection('settings').doc('cash');
    final cashSnap = await tx.get(cashRef);

    final settlement = returnSettlement(d, sales: true);
    final priorCash = (((d['partialCashRefund'] as num?) ?? 0) * 100).round();
    final priorDebt = (((d['partialDebtReduction'] as num?) ?? 0) * 100).round();
    final cashAvailable = ((settlement.cash * 100).round() - priorCash).clamp(0, 1000000000000).toInt();
    final debtAvailable = ((settlement.debt * 100).round() - priorDebt).clamp(0, 1000000000000).toInt();
    final sourceLineCents = ((item['lineTotal'] as num?)?.toDouble() ??
        sourceQty * ((item['unitPrice'] as num?)?.toDouble() ?? 0)) * 100;
    final amountCents = (sourceLineCents.round() * quantity / sourceQty).round();
    final totalAvailable = cashAvailable + debtAvailable;
    final cashRefundCents = partialReturnCashCents(valueCents: amountCents,
      cashAvailableCents: cashAvailable, debtAvailableCents: debtAvailable);
    final debtReductionCents = amountCents - cashRefundCents;
    if (amountCents > totalAvailable) throw StateError('تسوية المرتجع تجاوزت المتبقي من الفاتورة');
    if (debtReductionCents > 0 && (customerRef == null || customerSnap?.exists != true)) {
      throw StateError('الفاتورة الآجلة تحتاج حساب عميل مسجل');
    }
    final cashBefore = (cashSnap.data()?['balance'] as num?)?.toDouble() ?? 0;
    if (cashBefore * 100 < cashRefundCents) throw StateError('رصيد الصندوق لا يكفي لرد المبلغ المحصل');
    final stockBefore = (stockSnap.data()?['quantity'] as num?)?.toInt() ?? 0;
    final now = FieldValue.serverTimestamp();
    final returnRef = db.collection('salesReturns').doc();

    tx.set(stockRef, {'branchId': branchId, 'productId': productId, 'quantity': stockBefore + quantity}, SetOptions(merge: true));
    tx.set(db.collection('stockMovements').doc(), {
      'productId': productId, 'productName': item['productName'], 'branchId': branchId,
      'kind': 'sales_return', 'quantity': quantity, 'balanceAfter': stockBefore + quantity,
      'referenceId': returnRef.id, 'actorId': actor, 'createdAt': now,
    });
    if (debtReductionCents > 0) {
      final customerBefore = (customerSnap!.data()?['balance'] as num?)?.toDouble() ?? 0;
      final customerAfter = (customerBefore * 100).round() / 100 - debtReductionCents / 100;
      tx.update(customerRef!, {'balance': customerAfter, 'updatedAt': now});
      tx.set(db.collection('accountMovements').doc(), {
        'accountType': 'customers', 'accountId': customerId, 'accountName': d['customerName'],
        'kind': 'sales_return', 'amount': debtReductionCents / 100,
        'balanceBefore': customerBefore, 'balanceAfter': customerAfter,
        'referenceId': returnRef.id, 'createdAt': now, 'actorId': actor,
      });
    }
    if (cashRefundCents > 0) {
      final cashAfter = (cashBefore * 100).round() / 100 - cashRefundCents / 100;
      tx.set(cashRef, {'balance': cashAfter, 'updatedAt': now}, SetOptions(merge: true));
      tx.set(db.collection('accountMovements').doc(), {
        'accountType': 'cash', 'kind': 'sales_return', 'amount': cashRefundCents / 100,
        'delta': -cashRefundCents / 100, 'balanceBefore': cashBefore, 'balanceAfter': cashAfter,
        'accountId': customerId, 'accountName': d['customerName'], 'referenceId': returnRef.id,
        'reason': 'رد قيمة صنف من فاتورة مبيعات', 'createdAt': now, 'actorId': actor,
      });
    }
    final newReturn = {
      'sourceInvoiceId': id, 'returnType': 'partial', 'sourceItemIndex': sourceItemIndex,
      'items': [{'sourceItemIndex': sourceItemIndex, 'productId': productId,
        'productName': item['productName'], 'quantity': quantity,
        'unitPrice': item['unitPrice'] ?? 0, 'lineTotal': amountCents / 100}],
      'total': amountCents / 100, 'cashRefund': cashRefundCents / 100,
      'debtReduction': debtReductionCents / 100, 'branchId': branchId,
      'customerId': customerId, 'customerName': d['customerName'],
      'invoiceNumber': d['invoiceNumber'], 'internalNumber': d['internalNumber'],
      'invoiceBarcode': d['invoiceBarcode'], 'createdAt': now, 'actorId': actor,
    };
    tx.set(returnRef, newReturn);
    final allReturned = items.asMap().entries.every((entry) {
      final lineQty = (entry.value['quantity'] as num?)?.toInt() ?? 0;
      final returnedQty = (returnedByLine[entry.key] ?? 0) + (entry.key == sourceItemIndex ? quantity : 0);
      return lineQty > 0 && returnedQty >= lineQty;
    });
    final quantityByLine = Map<String, dynamic>.from(d['partialReturnQuantities'] is Map ? d['partialReturnQuantities'] as Map : {});
    quantityByLine['$sourceItemIndex'] = alreadyReturned + quantity;
    final priorReturnTotal = (d['partialReturnTotal'] as num?)?.toDouble() ?? 0;
    final priorCashRefund = (d['partialCashRefund'] as num?)?.toDouble() ?? 0;
    final priorDebtReduction = (d['partialDebtReduction'] as num?)?.toDouble() ?? 0;
    tx.update(invoiceRef, {
      'partialReturnQuantities': quantityByLine,
      'partialReturnTotal': ((priorReturnTotal * 100).round() + amountCents) / 100,
      'partialCashRefund': ((priorCashRefund * 100).round() + cashRefundCents) / 100,
      'partialDebtReduction': ((priorDebtReduction * 100).round() + debtReductionCents) / 100,
      'lastPartialReturnId': returnRef.id,
      if (allReturned) 'status': 'returned',
      if (allReturned) 'returnedAt': now,
      if (allReturned) 'returnId': returnRef.id,
    });
  });
}

