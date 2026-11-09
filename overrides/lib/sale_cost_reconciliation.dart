part of 'main.dart';

// Match a purchase to a historical sale by BOTH product id and normalized
// product name. A reused product id must never silently rewrite the cost
// of a different product (e.g. one-shelf versus three-shelf corner units).
String normalizeSaleCostProductName(String name) => name
    .trim().toLowerCase()
    .replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا')
    .replaceAll('ى', 'ي').replaceAll('ة', 'ه')
    .replaceAll(RegExp(r'[\u064b-\u065f\u0640]'), '')
    .replaceAll(RegExp(r'[^a-z0-9\u0621-\u064a]'), '');

int? _purchaseCostTimestamp(Object? value) {
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  return null;
}

/// Last verifiable purchase cost ON OR BEFORE the sale date, for the same
/// product id and the same normalized name. Never substitute today's
/// product card cost for an unverified historical purchase.
Map<String,double> verifiedPurchaseCostsAtSale({
  required DateTime saleDate,
  required Map<String,String> productNames,
  required Iterable<Map<String,dynamic>> purchases,
}) {
  final bestTime = <String,int>{};
  final prices = <String,double>{};
  final saleTime = saleDate.millisecondsSinceEpoch;
  final normalized = {
    for (final item in productNames.entries)
      item.key: normalizeSaleCostProductName(item.value),
  };
  for (final purchase in purchases) {
    if (const ['cancelled','canceled','void','deleted','returned','pending']
        .contains(purchase['status'])) continue;
    final at = _purchaseCostTimestamp(purchase['createdAt']);
    if (at == null || at > saleTime) continue;
    final raw = purchase['items'];
    final rows = raw is List && raw.isNotEmpty ? raw : [purchase];
    for (final entry in rows) {
      if (entry is! Map) continue;
      final productId = (entry['productId'] ?? '').toString();
      final expectedName = normalized[productId];
      if (expectedName == null || expectedName.isEmpty ||
          normalizeSaleCostProductName((entry['productName'] ?? '').toString()) != expectedName) {
        continue;
      }
      final cost = (entry['unitCost'] as num?)?.toDouble();
      if (cost == null || !cost.isFinite || cost < 0) continue;
      if (at >= (bestTime[productId] ?? -1)) {
        prices[productId] = cost;
        bestTime[productId] = at;
      }
    }
  }
  return prices;
}

/// A best-effort verification before editing one existing invoice.
/// If the server is offline or the purchase record cannot be verified,
/// the stored snapshot is preserved instead of guessing another cost.
Future<Map<String,double>> verifiedCostsForEditedSale(
  Map<String,dynamic> sale,
) async {
  final timestamp = sale['createdAt'];
  if (timestamp is! Timestamp) return {};
  final names = <String,String>{};
  for (final row in saleItems(sale)) {
    final id = (row['productId'] ?? '').toString();
    if (id.isNotEmpty) names[id] = (row['productName'] ?? '').toString();
  }
  if (names.isEmpty) return {};
  try {
    final purchases = await db.collection('purchases')
      .where('createdAt', isLessThanOrEqualTo:timestamp)
      .orderBy('createdAt', descending:true)
      .limit(500)
      .get(const GetOptions(source:Source.server));
    return verifiedPurchaseCostsAtSale(
      saleDate:timestamp.toDate(),
      productNames:names,
      purchases:purchases.docs.map((doc)=>doc.data()),
    );
  } catch (error) {
    debugPrint('VIB sale cost verification unavailable: $error');
    return {};
  }
}
