import 'package:flutter/material.dart';

class InventoryProductCard extends StatelessWidget {
  final bool employee;
  final bool compactPriceBoxes;
  final int number;
  final String name, priceLabel;
  final num? quantity, unitPrice;
  final String? quantityMessage, detail;
  final List<Widget> actions;
  final VoidCallback? onTap;
  const InventoryProductCard({super.key, required this.number, required this.name,
    required this.quantity, required this.unitPrice, this.priceLabel = 'سعر البيع', this.employee=false, this.compactPriceBoxes=false,
    this.quantityMessage, this.detail, this.actions = const [], this.onTap});

  static const quantityColor = Color(0xFF66DE91);
  static const priceColor = Color(0xFF80BEFF);
  static const totalColor = Color(0xFFFFD166);

  Widget box(String label, String value, Color color) => Container(
    padding: EdgeInsets.symmetric(horizontal: compactPriceBoxes ? 3 : 5,
      vertical: compactPriceBoxes ? 3 : 5),
    decoration: BoxDecoration(color: color.withValues(alpha: .10),
      border: Border.all(color: color.withValues(alpha: .65)),
      borderRadius: BorderRadius.circular(compactPriceBoxes ? 5 : 6)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: compactPriceBoxes ? 10 : 11))),
      SizedBox(height: compactPriceBoxes ? 1 : 2),
      FittedBox(fit: BoxFit.scaleDown, child: Text(value, maxLines: 1,
        textDirection: num.tryParse(value) != null ? TextDirection.ltr : null,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: compactPriceBoxes ? 12 : 14,
          fontWeight: FontWeight.bold))),
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
            Expanded(child: Text(name, style: TextStyle(color:employee ? Colors.lightBlueAccent : null,fontSize:15,fontWeight:FontWeight.w600))),
          ]),
          if(employee) Padding(padding:const EdgeInsets.only(top:4),child:Text('المتاح: $qty',style:const TextStyle(color:Colors.redAccent,fontSize:12))),
          if(detail != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(detail!, style: const TextStyle(fontSize: 12))),
          SizedBox(height: compactPriceBoxes ? 3 : 6),
          Align(alignment: AlignmentDirectional.centerStart, child: ConstrainedBox(
            key: const ValueKey('inventory-price-boxes'),
            constraints: BoxConstraints(maxWidth: compactPriceBoxes ? 205 : 270),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: box('العدد', qty, employee ? totalColor : quantityColor)),
              SizedBox(width: compactPriceBoxes ? 3 : 4),
              Expanded(child: box(priceLabel, price, employee ? quantityColor : priceColor)),
              SizedBox(width: compactPriceBoxes ? 3 : 4),
              Expanded(child: box('الإجمالي', total != null && total.isFinite ? total.toStringAsFixed(2) : 'غير متاح', totalColor)),
            ]),
          )),
          if(actions.isNotEmpty) IconButtonTheme(data: IconButtonThemeData(style: IconButton.styleFrom(
            iconSize: 16, minimumSize: const Size(30, 30),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.all(2), visualDensity: VisualDensity.compact)),
            child: Align(alignment: AlignmentDirectional.centerEnd,
              child: Wrap(spacing: 1, runSpacing: 0, children: actions))),
        ],
      ))));
  }
}

