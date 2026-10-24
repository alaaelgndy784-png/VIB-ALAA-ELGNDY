num adjustedInventoryPrice(num value, num percent, {required bool increase}) {
  if (!value.isFinite || value < 0 || !percent.isFinite || percent <= 0 || (!increase && percent > 100)) {
    throw StateError('اكتب نسبة صحيحة؛ التخفيض من أكبر من صفر حتى 100٪');
  }
  final result = value * (1 + (increase ? percent : -percent) / 100);
  if (!result.isFinite || result < 0 || result > 1000000000) throw StateError('السعر الناتج غير صحيح');
  return (result * 100 + 0.00000001).round() / 100;
}

List<Map<String, dynamic>> groupedReturnItems(List<Map<String, dynamic>> items) {
  final groups = <String, Map<String, dynamic>>{};
  for (final item in items) {
    final id = '${item['productId'] ?? ''}';
    final quantity = item['quantity'];
    if (id.isEmpty || id == 'null' || quantity is! num || !quantity.isFinite || quantity <= 0 || quantity != quantity.round()) {
      throw StateError('بيانات صنف المرتجع أو كميته غير صحيحة');
    }
    final prior = groups[id];
    groups[id] = {...item, 'quantity': quantity.toInt() + ((prior?['quantity'] as int?) ?? 0)};
  }
  if (groups.isEmpty || groups.length > 50) throw StateError('عدد أصناف المرتجع غير صحيح');
  return groups.values.toList();
}

int partialReturnCashCents({required int valueCents, required int cashAvailableCents, required int debtAvailableCents}) {
  if (valueCents < 0 || cashAvailableCents < 0 || debtAvailableCents < 0) {
    throw StateError('قيمة المرتجع أو رصيد التسوية غير صحيح');
  }
  final available = cashAvailableCents + debtAvailableCents;
  if (valueCents > available) throw StateError('قيمة المرتجع أكبر من المتبقي من الفاتورة');
  if (available == 0) {
    if (valueCents == 0) return 0;
    throw StateError('لا يوجد مبلغ متاح لتسوية المرتجع');
  }
  if (valueCents == available) return cashAvailableCents;
  return (valueCents * cashAvailableCents / available).round();
}

Map<int, int> returnedQuantitiesBySourceLine(List<Map<String, dynamic>> returns) {
  final result = <int, int>{};
  for (final record in returns) {
    final items = record['items'];
    if (items is! List) continue;
    for (final raw in items) {
      if (raw is! Map) continue;
      final index = raw['sourceItemIndex'];
      final quantity = raw['quantity'];
      if (index is! num || index < 0 || index != index.round() || quantity is! num ||
          !quantity.isFinite || quantity <= 0 || quantity != quantity.round()) {
        throw StateError('بيانات المرتجع السابق غير صحيحة');
      }
      final key = index.toInt();
      result[key] = (result[key] ?? 0) + quantity.toInt();
    }
  }
  return result;
}

class LastPurchaseUnitCost {
  final String invoiceId;
  final double cost;
  final DateTime createdAt;
  const LastPurchaseUnitCost(this.invoiceId, this.cost, this.createdAt);
}

/// A snapshot of purchase records is reviewed by *original invoice date*, not
/// date of a later amendment. Do not overwrite a newer purchase's unit cost.
Map<String, LastPurchaseUnitCost> latestPurchaseUnitCosts(
    Iterable<Map<String, dynamic>> invoices) {
  final result = <String, LastPurchaseUnitCost>{};
  for (final invoice in invoices) {
    if (invoice['status'] != 'completed') continue;
    final invoiceId = '${invoice['id'] ?? ''}';
    final createdAt = invoice['createdAt'];
    if (invoiceId.isEmpty || createdAt is! DateTime) continue;
    final rawItems = invoice['items'];
    final items = rawItems is List && rawItems.isNotEmpty
        ? rawItems
        : <Map<String, dynamic>>[{
            'productId': invoice['productId'],
            'unitCost': invoice['unitCost'],
          }];
    for (final raw in items) {
      if (raw is! Map) continue;
      final productId = '${raw['productId'] ?? ''}';
      final price = raw['unitCost'];
      if (productId.isEmpty || productId == 'null' || price is! num ||
          !price.isFinite || price < 0) continue;
      final prior = result[productId];
      if (prior == null || createdAt.isAfter(prior.createdAt) ||
          (createdAt.isAtSameMomentAs(prior.createdAt) &&
              invoiceId.compareTo(prior.invoiceId) > 0)) {
        result[productId] =
            LastPurchaseUnitCost(invoiceId, price.toDouble(), createdAt);
      }
    }
  }
  return result;
}

bool inventoryPriceMismatch(num? recorded, num? expected) {
  if (recorded == null || expected == null ||
      !recorded.isFinite || !expected.isFinite ||
      recorded < 0 || expected < 0) return true;
  return (recorded * 100).round() != (expected * 100).round();
}

 
/// Editing an old purchase may update the product's *current* purchase cost
/// only if it is still the latest purchase, and no later correction supersedes
/// it. The current value must still match the original invoice cost, avoiding
/// accidental overwrites of an untracked manual change.
bool shouldSyncEditedPurchaseCost({
  required String invoiceId,
  required String? latestInvoiceId,
  required num? previousInvoiceCost,
  required num correctedInvoiceCost,
  required num? currentProductCost,
  String? productLastPurchaseId,
  DateTime? manualCorrectionAt,
  DateTime? lastPurchaseRecordedAt,
  DateTime? originalInvoiceAt,
}) {
  if (invoiceId.isEmpty || latestInvoiceId != invoiceId ||
      previousInvoiceCost == null ||
      !previousInvoiceCost.isFinite || previousInvoiceCost < 0 ||
      !correctedInvoiceCost.isFinite || correctedInvoiceCost < 0 ||
      currentProductCost == null || !currentProductCost.isFinite ||
      currentProductCost < 0 ||
      !inventoryPriceMismatch(previousInvoiceCost, correctedInvoiceCost) ||
      inventoryPriceMismatch(currentProductCost, previousInvoiceCost)) return false;
  if (productLastPurchaseId != null && productLastPurchaseId.isNotEmpty &&
      productLastPurchaseId != invoiceId) return false;
  final cutoff = lastPurchaseRecordedAt ?? originalInvoiceAt;
  if (manualCorrectionAt != null &&
      (cutoff == null || manualCorrectionAt.isAfter(cutoff))) return false;
  return true;
}
