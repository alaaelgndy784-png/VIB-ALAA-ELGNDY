part of 'main.dart';

// Read-only FIFO valuation from recorded purchase lots. We never change an
// invoice, payment, supplier balance, inventory quantity or stock movement.
// A sale receives a FIFO unit cost only if its complete quantity can be
// matched to recorded, earlier purchase lots of the SAME id AND product name.
// With incomplete historical stock, reports use the original cost snapshot.
class _FifoPurchaseLot {
  int remaining;
  final int unitCostPiastres;
  _FifoPurchaseLot(this.remaining, this.unitCostPiastres);
}

class _FifoCostEvent {
  final int time, sequence;
  final String documentId, productKey, productId;
  final int quantity;
  final int? unitCostPiastres;
  const _FifoCostEvent({
    required this.time, required this.sequence, required this.documentId,
    required this.productKey, required this.productId,
    required this.quantity, this.unitCostPiastres,
  });
}

String _saleBatchProductKey(Map row) {
  final id = '${row['productId'] ?? ''}'.trim();
  final name = normalizeSaleCostProductName('${row['productName'] ?? ''}');
  if (id.isEmpty || name.isEmpty) return '';
  return '$id|$name';
}

int? _fifoWholeQuantity(Object? value) {
  if (value is! num || !value.isFinite || value <= 0 ||
      value != value.roundToDouble()) return null;
  return value.toInt();
}

int? _fifoMoneyPiastres(Object? value) {
  if (value is! num || !value.isFinite || value < 0) return null;
  return (value.toDouble() * 100).round();
}

/// saleDocumentId -> productId -> weighted unit purchase cost allocated by
/// FIFO. This uses every prior sale, not just sales inside the report window.
/// Missing lots intentionally produce no override, rather than an invented
/// profit based on today's price.
Map<String, Map<String, double>> fifoSaleCostsFromPurchaseLots({
  required Iterable<Map<String, dynamic>> purchases,
  required Iterable<Map<String, dynamic>> sales,
}) {
  final events = <_FifoCostEvent>[];
  void addDocument(Map<String, dynamic> doc, int sequence, bool purchase) {
    if (const ['cancelled','canceled','void','deleted','pending']
        .contains(doc['status'])) return;
    final at = _purchaseCostTimestamp(doc['createdAt']);
    if (at == null) return;
    final documentId = '${doc['id'] ?? ''}'.trim();
    if (documentId.isEmpty) return;
    final raw = doc['items'];
    final rows = raw is List && raw.isNotEmpty ? raw : [doc];
    for (final entry in rows) {
      if (entry is! Map) continue;
      final productKey = _saleBatchProductKey(entry);
      final quantity = _fifoWholeQuantity(entry['quantity']);
      if (productKey.isEmpty || quantity == null) continue;
      final cost = purchase ? _fifoMoneyPiastres(entry['unitCost']) : null;
      if (purchase && cost == null) continue;
      events.add(_FifoCostEvent(
        time: at, sequence: sequence, documentId: documentId,
        productKey: productKey, productId: '${entry['productId']}',
        quantity: quantity, unitCostPiastres: cost,
      ));
    }
  }
  for (final doc in purchases) { addDocument(doc, 0, true); }
  for (final doc in sales) { addDocument(doc, 1, false); }
  events.sort((a, b) {
    final date = a.time.compareTo(b.time);
    if (date != 0) return date;
    final kind = a.sequence.compareTo(b.sequence);
    return kind != 0 ? kind : a.documentId.compareTo(b.documentId);
  });

  final lots = <String, List<_FifoPurchaseLot>>{};
  final resolved = <String, Map<String, double>>{};
  for (final event in events) {
    final stockLots = lots.putIfAbsent(event.productKey, () => []);
    if (event.sequence == 0) {
      stockLots.add(_FifoPurchaseLot(
        event.quantity, event.unitCostPiastres!));
      continue;
    }
    final available = stockLots.fold<int>(0, (sum, lot) => sum + lot.remaining);
    if (available < event.quantity) {
      // Opening inventory, purchases not recorded, backdated documents, etc.
      // Do not pretend that the last purchase priced the entire sale.
      continue;
    }
    var remaining = event.quantity;
    var costPiastres = 0;
    while (remaining > 0 && stockLots.isNotEmpty) {
      final lot = stockLots.first;
      final used = remaining < lot.remaining ? remaining : lot.remaining;
      costPiastres += used * lot.unitCostPiastres;
      lot.remaining -= used;
      remaining -= used;
      if (lot.remaining == 0) stockLots.removeAt(0);
    }
    resolved.putIfAbsent(event.documentId, () => {})[event.productId] =
      costPiastres / (event.quantity * 100);
  }
  return resolved;
}
