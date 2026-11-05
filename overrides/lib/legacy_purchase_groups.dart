part of 'main.dart';

// Older camera purchases were persisted as one document per product with a
// shared scanGroupId. Group only on that explicit identifier, for display.
// Never consolidate or modify the real Firestore invoice documents.
class VibPurchaseRow {
  final String id;
  final Map<String, dynamic> data;
  const VibPurchaseRow(this.id, this.data);
}

class VibPurchaseGroup {
  final List<VibPurchaseRow> sources;
  const VibPurchaseGroup(this.sources);
  bool get grouped => sources.length > 1;
  String get id => sources.first.id;
  bool get completeSettlement => sources.every((r) =>
    r.data['total'] is num &&
    (r.data['paid'] is num || r.data['due'] is num));

  Map<String, dynamic> get data {
    if (!grouped) return sources.first.data;
    final d = Map<String, dynamic>.from(sources.first.data);
    final lines = <Map<String, dynamic>>[];
    int total = 0, paid = 0;
    for (final source in sources) {
      final original = source.data;
      lines.addAll(purchaseItems(original));
      final amount = original['total'] as num;
      total += (amount * 100).round();
      if (completeSettlement) {
        final amountPaid = (original['paid'] as num?)?.toDouble() ??
            amount.toDouble() - (original['due'] as num).toDouble();
        paid += (amountPaid * 100).round();
      }
    }
    d['items'] = lines;
    d['itemCount'] = lines.length;
    d['total'] = total / 100;
    if (completeSettlement) {
      d['paid'] = paid / 100;
      d['due'] = (total - paid) / 100;
    } else {
      d.remove('paid');
      d.remove('due');
    }
    // Line-level supplier balances are not the total historical balance of
    // the grouped invoice. Avoid printing them as if they were.
    for (final key in [
      'internalNumber','invoiceBarcode','supplierPreviousBalance',
      'supplierBalanceAfter','receiptPaid','cashBefore','cashAfter'
    ]) { d.remove(key); }
    final number = (d['invoiceNumber'] ?? '').toString().trim();
    d['invoiceNumber'] = number.isEmpty ? 'تصوير قديم بلا رقم' : number;
    return d;
  }
}

String? vibLegacyPurchaseKey(VibPurchaseRow row) {
  final d = row.data;
  final scanId = (d['scanGroupId'] ?? '').toString().trim();
  final supplier = (d['supplierId'] ?? '').toString().trim();
  final status = (d['status'] ?? '').toString().trim();
  if (scanId.isEmpty || scanId == 'null' ||
      supplier.isEmpty || supplier == 'null') return null;
  // Modern grouped invoices and independent purchases are always separate.
  if (d['items'] is List && (d['items'] as List).isNotEmpty) return null;
  return 'scan|' + supplier + '|' + status + '|' + scanId;
}

List<VibPurchaseGroup> vibGroupLegacyPurchases(List<VibPurchaseRow> rows) {
  final buckets = <String, List<VibPurchaseRow>>{};
  for (final row in rows) {
    final key = vibLegacyPurchaseKey(row);
    if (key != null) buckets.putIfAbsent(key, () => []).add(row);
  }
  final used = <String>{};
  final result = <VibPurchaseGroup>[];
  for (final row in rows) {
    final key = vibLegacyPurchaseKey(row);
    if (key == null) {
      result.add(VibPurchaseGroup([row]));
    } else if (used.add(key)) {
      result.add(VibPurchaseGroup(buckets[key]!));
    }
  }
  return result;
}

// Synthetic invoice groups are for display/PDF only. Do not open regular
// invoice edit/return/cancel actions or the write-audit print route.
Future<void> showVibGroupedPurchase(
    BuildContext context, VibPurchaseGroup group) async {
  if (!group.grouped) {
    return showInvoiceOverview(context, 'purchases', group.id,
        initialData: group.data);
  }
  final invoice = group.data;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (page) => Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('فاتورة مشتريات قديمة مجمّعة')),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(10), child: Text(
            'مجموعة للعرض فقط من ' + group.sources.length.toString() +
            ' سجلات أصلية. لا تعديل للمخزون أو رصيد المورد.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: gold, fontSize: 12),
          )),
          if (!group.completeSettlement)
            const Padding(padding: EdgeInsets.all(8), child: Text(
              'المدفوع والباقي ناقصان في بعض سجلات الفاتورة؛ '
              'لا يمكن إخراج PDF بتسوية غير موثوقة.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.orangeAccent),
            )),
          Expanded(child: group.completeSettlement
            ? PdfPreview(
                build: (_) => createInvoicePdf(
                    'purchases', group.id, invoice, paperChoice: 'a4'),
                initialPageFormat: PdfPageFormat.a4,
                canChangePageFormat: false,
                canChangeOrientation: false,
                allowPrinting: false,
                allowSharing: false,
                useActions: false,
                maxPageWidth: 1200,
              )
            : ListView(children: [
                for (final line in purchaseItems(invoice))
                  ListTile(title: Text((line['productName'] ?? 'صنف').toString()),
                    subtitle: Text('الكمية: ' + (line['quantity'] ?? 0).toString()),
                    trailing: Text((line['lineTotal'] ?? 0).toString() + ' ج.م')),
                ListTile(title: const Text('إجمالي الأصناف'),
                  trailing: Text((invoice['total'] ?? 0).toString() + ' ج.م')),
              ])),
        ]),
        bottomNavigationBar: SafeArea(child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(child: FilledButton.icon(
              onPressed: group.completeSettlement
                ? () => exportInvoicePdf(page, 'purchases', group.id, invoice)
                : null,
              icon: const Icon(Icons.share),
              label: const Text('إرسال PDF'),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(page),
              icon: const Icon(Icons.close),
              label: const Text('إغلاق'),
            )),
          ]),
        )),
      ),
    ),
  ));
}
