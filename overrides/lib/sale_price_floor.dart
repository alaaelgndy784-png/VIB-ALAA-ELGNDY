/// Protects invoice persistence from below-cost sales. The unit price must be
/// the *final* per-unit amount after discounts, not the catalog/base price.
/// A missing cost cannot prove that a sale is safe, so it blocks the sale.
String? belowCostSaleMessage({
  required String productName,
  required double unitPrice,
  required num? unitCost,
}) {
  final name = productName.trim().isEmpty ? 'غير معروف' : productName.trim();
  if (!unitPrice.isFinite || unitPrice < 0) {
    return 'سعر بيع الصنف "$name" غير صحيح';
  }
  if (unitCost == null || !unitCost.isFinite || unitCost < 0) {
    return 'لا يمكن بيع "$name": سعر التكلفة غير مسجل أو غير صحيح. سجل التكلفة أولاً.';
  }
  final cost = unitCost.toDouble();
  if (unitPrice + 0.0000001 < cost) {
    return 'ممنوع بيع "$name" بسعر ${unitPrice.toStringAsFixed(2)} ج.م؛ سعر التكلفة ${cost.toStringAsFixed(2)} ج.م.';
  }
  return null;
}
