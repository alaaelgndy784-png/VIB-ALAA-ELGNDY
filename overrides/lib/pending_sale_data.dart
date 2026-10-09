// Pending invoices are untrusted proposals. Revalidate before posting accounts.
class PendingSaleLine {
  final String id;
  final int quantity;
  final double price, basePrice, discount;
  PendingSaleLine(this.id, this.quantity, this.price, this.basePrice, this.discount);
}

class PendingSaleData {
  final List<PendingSaleLine> lines;
  final String customerId;
  final bool credit;
  final double total, paid;
  PendingSaleData(this.lines, this.customerId, this.credit, this.total, this.paid);

  factory PendingSaleData.parse(Map<String,dynamic> data) {
    final raw=data['items'];
    if(raw is! List || raw.isEmpty || raw.length>50) throw const FormatException('عدد البنود غير صحيح');
    final ids=<String>{};
    final lines=<PendingSaleLine>[];
    double total=0;
    double amount(Object? value) {
      if(value is! num || !value.toDouble().isFinite || value<0) throw const FormatException('السعر أو المبلغ غير صحيح');
      return value.toDouble();
    }
    for(final row in raw) {
      if(row is! Map) throw const FormatException('بيانات الصنف غير صحيحة');
      final id=row['productId'],qty=row['quantity'];
      if(id is! String || id.isEmpty || id.contains('/') || !ids.add(id) || qty is! int || qty<=0 || qty>1000000) {
        throw const FormatException('راجع الصنف والكمية ولا تكرر المنتج');
      }
      final price=amount(row['unitPrice']),base=amount(row['basePrice']),discount=amount(row['discountPercent']);
      if(discount>100) throw const FormatException('نسبة الخصم غير صحيحة');
      lines.add(PendingSaleLine(id,qty,price,base,discount));
      total+=qty*price;
    }
    final customer=data['customerId'],credit=data['credit'];
    final paid=amount(data['paid']);
    if(customer is! String || (customer.isNotEmpty && customer.contains('/')) || credit is! bool || !total.isFinite ||
      (customer.isEmpty && (credit || (paid-total).abs()>0.000001))) throw const FormatException('اختر عميلًا مسجلًا للآجل وراجع طريقة الدفع');
    if(paid>total || (!credit && (paid-total).abs()>0.000001)) throw const FormatException('المدفوع غير صحيح');
    return PendingSaleData(lines,customer,credit,total,paid);
  }
}
