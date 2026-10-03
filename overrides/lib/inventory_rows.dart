import 'package:flutter/material.dart';

class InventoryProductCard extends StatelessWidget {
  final int number;
  final String name, priceLabel;
  final num? quantity, unitPrice;
  final String? quantityMessage, detail;
  final List<Widget> actions;
  final VoidCallback? onTap;
  const InventoryProductCard({super.key, required this.number, required this.name,
    required this.quantity, required this.unitPrice, this.priceLabel = 'سعر البيع',
    this.quantityMessage, this.detail, this.actions = const [], this.onTap});

  static const quantityColor = Color(0xFF66DE91);
  static const priceColor = Color(0xFF80BEFF);
  static const totalColor = Color(0xFFFFD166);

  Widget box(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
    decoration: BoxDecoration(color: color.withValues(alpha: .10),
      border: Border.all(color: color.withValues(alpha: .65)), borderRadius: BorderRadius.circular(6)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 11))),
      const SizedBox(height: 2),
      FittedBox(fit: BoxFit.scaleDown, child: Text(value, maxLines: 1, textDirection: num.tryParse(value) != null ? TextDirection.ltr : null,
        textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold))),
    ]),
  );
  @override Widget build(BuildContext context) {
    final q = quantity, p = unitPrice;
    final total = q != null && q.isFinite && p != null && p.isFinite ? q * p : null;
    final qty = q == null ? quantityMessage ?? 'غير متاح' : q.toString();
    final price = p != null && p.isFinite ? p.toStringAsFixed(2) : 'غير مسجل';
    return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(8), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(color: totalColor.withValues(alpha: .15), borderRadius: BorderRadius.circular(8)),
              child: Text('$number', style: const TextStyle(color: totalColor, fontSize: 12, fontWeight: FontWeight.bold))),
            const SizedBox(width: 6),
            Expanded(child: Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          ]),
          if(detail != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(detail!, style: const TextStyle(fontSize: 12))),
          const SizedBox(height: 6),
          Align(alignment: AlignmentDirectional.centerStart, child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 270),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: box('العدد', qty, quantityColor)), const SizedBox(width: 4),
              Expanded(child: box(priceLabel, price, priceColor)), const SizedBox(width: 4),
              Expanded(child: box('الإجمالي', total != null && total.isFinite ? total.toStringAsFixed(2) : 'غير متاح', totalColor)),
            ]),
          )),
          if(actions.isNotEmpty) IconButtonTheme(data: IconButtonThemeData(style: IconButton.styleFrom(
            iconSize: 18, visualDensity: VisualDensity.compact)),
            child: Align(alignment: AlignmentDirectional.centerEnd, child: Wrap(spacing: 0, children: actions))),
        ],
      ))));
  }
}
