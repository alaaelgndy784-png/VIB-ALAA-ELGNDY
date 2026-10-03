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
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
    decoration: BoxDecoration(color: color.withValues(alpha: .10),
      border: Border.all(color: color.withValues(alpha: .65)), borderRadius: BorderRadius.circular(9)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 12)),
      const SizedBox(height: 5),
      Text(value, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
    ]),
  );
  @override Widget build(BuildContext context) {
    final q = quantity, p = unitPrice;
    final total = q != null && q.isFinite && p != null && p.isFinite ? q * p : null;
    final qty = q == null ? quantityMessage ?? 'غير متاح' : q.toString();
    final price = p != null && p.isFinite ? p.toStringAsFixed(2) : 'غير مسجل';
    return Card(margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: totalColor.withValues(alpha: .15), borderRadius: BorderRadius.circular(8)),
              child: Text('$number', style: const TextStyle(color: totalColor, fontWeight: FontWeight.bold))),
            const SizedBox(width: 9),
            Expanded(child: Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          ]),
          if(detail != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(detail!, style: const TextStyle(fontSize: 12))),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, size) {
            // Keep the three fields adjacent at phone widths; narrow windows
            // and large accessibility fonts wrap into individually sized boxes.
            final wrap = size.maxWidth < 290 || MediaQuery.textScalerOf(context).scale(1) > 1.5;
            final fields = [box('العدد', qty, quantityColor), box(priceLabel, price, priceColor),
              box('الإجمالي', total != null && total.isFinite ? total.toStringAsFixed(2) : 'غير متاح', totalColor)];
            if(wrap) return Wrap(spacing: 8, runSpacing: 8, children: fields.map((w) => SizedBox(width: (size.maxWidth - 8) / 2, child: w)).toList());
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: fields[0]), const SizedBox(width: 7), Expanded(child: fields[1]), const SizedBox(width: 7), Expanded(child: fields[2]),
            ]);
          }),
          if(actions.isNotEmpty) Align(alignment: AlignmentDirectional.centerEnd, child: Wrap(spacing: 4, children: actions)),
        ],
      ))));
  }
}
