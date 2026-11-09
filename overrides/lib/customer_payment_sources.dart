part of 'main.dart';

class VibSalesPaymentSnapshot {
  final List<Map<String,dynamic>> rows;
  final bool fromCache, hasPendingWrites;
  const VibSalesPaymentSnapshot(this.rows,{this.fromCache=false,this.hasPendingWrites=false});
}


// Invoice payments are genuine customer collections, but they are not
// receipt vouchers. Keep both document types in one read-only timeline.
// Never use accountMovements cash/customerCollection here: those
// movements mirror receipts and would count the same money twice.
List<Map<String,dynamic>> vibCustomerPaymentReportRows({
  required Iterable<Map<String,dynamic>> receipts,
  required Iterable<Map<String,dynamic>> sales,
  required Set<String> cancelledReceiptIds,
}) {
  final result=<Map<String,dynamic>>[];
  final seen=<String>{};
  for (final receipt in receipts) {
    final id='${receipt['id'] ?? ''}';
    if (id.isEmpty || cancelledReceiptIds.contains(id) || !visibleAfterReset(receipt)) continue;
    final amount=receipt['amount'];
    if (amount is! num || !amount.toDouble().isFinite || amount <= 0) continue;
    if (!seen.add('receipt:$id')) continue;
    result.add({...receipt,'paymentSource':'receipt','paymentSourceLabel':'سند قبض'});
  }
  for (final sale in sales) {
    if (!visibleAfterReset(sale)) continue;
    final status='${sale['status'] ?? ''}'.toLowerCase();
    if (status!='completed') continue;
    final paid=sale['paid'];
    if (paid is! num || !paid.toDouble().isFinite || paid<=0) continue;
    final id='${sale['id'] ?? ''}';
    final created=sale['createdAt'];
    if (id.isEmpty || created is! Timestamp || !seen.add('sale:$id')) continue;
    final customerId='${sale['customerId'] ?? ''}';
    final customerName='${sale['customerName'] ?? ''}';
    final number=sale['internalNumber'] ?? sale['invoiceNumber'];
    final displayNumber='${number ?? id}'.trim();
    result.add({
      'id':'invoice-payment:$id',
      'customerId':customerId,
      'customerName':customerName.isEmpty ? 'عميل غير مسمى' : customerName,
      'amount':paid,
      'receiptDate':created,
      'createdAt':created,
      'receiptNumber':displayNumber,
      'paymentSource':'invoice',
      'paymentSourceLabel':'مدفوع في فاتورة مبيعات',
      'paymentMethod':'سداد وقت فاتورة البيع',
      'note':'مدفوع داخل فاتورة رقم $displayNumber',
      'actorId':sale['employeeId'] ?? sale['actorId'] ?? '',
      'actorName':sale['employeeName'] ?? sale['actorName'] ?? '',
      'sourceInvoiceId':id,
    });
  }
  return result;
}
