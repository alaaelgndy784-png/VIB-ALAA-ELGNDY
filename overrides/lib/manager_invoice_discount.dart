/// Manager invoice-wide discount, allocated in integer piastres.
double managerInvoiceDiscount(double gross, String input, bool percent) {
  if (!gross.isFinite || gross < 0) return double.nan;
  if (input.trim().isEmpty) return 0;
  final value = double.tryParse(input.trim().replaceAll(',', '.'));
  if (value == null || !value.isFinite || value < 0 ||
      (percent && value > 100)) return double.nan;
  final raw = percent ? gross * (value / 100) : value;
  if (!raw.isFinite || raw > gross + 0.000001) return double.nan;
  final cents = (raw * 100).round();
  return cents <= (gross * 100).round() ? cents / 100 : double.nan;
}

List<int> managerNetLineCents(List<double> grossLines, double discount) {
  final gross = grossLines.fold<double>(0, (sum, v) => sum + v);
  if (grossLines.isEmpty || grossLines.any((v) => !v.isFinite || v < 0) ||
      !gross.isFinite || !discount.isFinite || discount < 0 ||
      discount > gross + 0.000001) {
    throw const FormatException('راجع إجمالي الفاتورة والخصم');
  }
  final target = (gross * 100).round() - (discount * 100).round();
  if (target < 0) throw const FormatException('راجع قيمة الخصم');
  if (gross == 0) return List<int>.filled(grossLines.length, 0);
  var cumulative = 0.0;
  var allocated = 0;
  return List<int>.generate(grossLines.length, (i) {
    cumulative += grossLines[i];
    final next = i == grossLines.length - 1 ? target :
        (target * (cumulative / gross)).round().clamp(allocated, target).toInt();
    final cents = next - allocated;
    allocated = next;
    return cents;
  });
}

/// Returns NaN for an invalid or overpaid credit invoice.
/// A payment within floating-point noise of the full total uses the total
/// itself so no microscopic debt is posted, including on offline replay.
double managerInvoicePayment(double total, bool credit, String input) {
  if (!total.isFinite || total < 0) return double.nan;
  if (!credit) return total;
  final parsed = double.tryParse(input.trim().replaceAll(',', '.'));
  if (parsed == null || !parsed.isFinite || parsed < 0) return double.nan;
  final rounded = (parsed * 100).round() / 100;
  if ((rounded - parsed).abs() > 0.000001 ||
      rounded - total > 0.000001) return double.nan;
  return (rounded - total).abs() <= 0.000001 ? total : rounded;
}
