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
