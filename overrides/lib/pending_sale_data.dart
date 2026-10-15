import 'dart:convert';

const salePaymentMethodLabels = <String, String>{
  'cash': 'نقدي',
  'instapay': 'إنستا باي',
  'vodafoneCash': 'فودافون كاش',
};

/// Normalize the tender split stored on an invoice. Older invoices have no
/// split and are treated as cash for backwards compatibility.
Map<String, double> normalizeSalePaymentBreakdown(Object? raw, double paid) {
  if (!paid.isFinite || paid < 0) throw const FormatException('المدفوع غير صحيح');
  final Map<String, dynamic> values;
  if (raw == null) {
    values = {'cash': paid};
  } else if (raw is Map) {
    values = Map<String, dynamic>.from(raw);
  } else {
    throw const FormatException('توزيع طرق التحصيل غير صحيح');
  }
  if (values.keys.any((key) => !salePaymentMethodLabels.containsKey(key))) {
    throw const FormatException('طريقة تحصيل غير معروفة');
  }
  int cents(Object? value) {
    if (value is! num || !value.toDouble().isFinite || value < 0 || value > 1e10) {
      throw const FormatException('اكتب مبلغًا صحيحًا لكل طريقة تحصيل');
    }
    return (value * 100).round();
  }
  final result = <String, double>{};
  for (final method in salePaymentMethodLabels.keys) {
    result[method] = cents(values[method] ?? 0) / 100;
  }
  final sum = result.values.fold<int>(0, (total, amount) => total + (amount * 100).round());
  if (sum != cents(paid)) throw const FormatException('مجموع طرق التحصيل لازم يساوي المدفوع بالضبط');
  return result;
}

Map<String,double> adjustSalePaymentBreakdown(Object? raw,double previousPaid,double nextPaid) {
  final split=normalizeSalePaymentBreakdown(raw,previousPaid);
  if(!nextPaid.isFinite||nextPaid<0)throw const FormatException('المدفوع الجديد غير صحيح');
  var remaining=((previousPaid-nextPaid)*100).round();
  if(remaining<0) {
    split['cash']=(split['cash']??0)+(-remaining)/100;
  } else {
    for(final method in ['cash','instapay','vodafoneCash']) {
      final available=((split[method]??0)*100).round();
      final take=available<remaining?available:remaining;
      split[method]=(available-take)/100;
      remaining-=take;
    }
    if(remaining>0)throw const FormatException('تعذر تسوية توزيع طرق التحصيل');
  }
  return normalizeSalePaymentBreakdown(split,nextPaid);
}

// Pending invoices are untrusted proposals. Revalidate before posting accounts.
class PendingSaleLine {
  final String id;
  final int quantity;
  final double price, basePrice, discount;
  PendingSaleLine(this.id, this.quantity, this.price, this.basePrice, this.discount);
}

class OfflineEmployeeSaleData {
  final String id,branchId,customerId,createdAt,lastError;
  final bool credit;
  final double total,paid;
  final Map<String,double> paymentBreakdown;
  final List<Map<String,dynamic>> items;
  const OfflineEmployeeSaleData({required this.id,required this.branchId,required this.customerId,
    required this.createdAt,required this.credit,required this.total,required this.paid,
    required this.items,required this.paymentBreakdown,this.lastError=''});

  factory OfflineEmployeeSaleData.parse(Map<String,dynamic> data) {
    String requiredText(Object? value,String label) {
      if(value is! String||value.trim().isEmpty||value.contains('/'))throw FormatException('$label غير صحيح');
      return value.trim();
    }
    double amount(Object? value,String label) {
      if(value is! num||!value.toDouble().isFinite||value<0)throw FormatException('$label غير صحيح');
      return value.toDouble();
    }
    final id=requiredText(data['id'],'رقم الفاتورة');
    final branchId=requiredText(data['branchId'],'الفرع');
    final rawCustomerId=data['customerId'];
    final credit=data['credit'];
    if(credit is! bool || rawCustomerId is! String || rawCustomerId.contains('/'))
      throw const FormatException('العميل أو طريقة الدفع غير صحيحة');
    final customerId=rawCustomerId.trim();
    if(credit && customerId.isEmpty)throw const FormatException('اختر عميلًا لفاتورة الآجل');
    final raw=data['items'];
    if(raw is! List||raw.isEmpty||raw.length>50)throw const FormatException('عدد البنود غير صحيح');
    final ids=<String>{};
    final items=<Map<String,dynamic>>[];
    double calculated=0;
    for(final row in raw) {
      if(row is! Map)throw const FormatException('بيانات الصنف غير صحيحة');
      final productId=requiredText(row['productId'],'الصنف');
      final name=row['productName'];
      final quantity=row['quantity'];
      if(name is! String||name.trim().isEmpty||quantity is! int||quantity<=0||quantity>1000000||!ids.add(productId))
        throw const FormatException('راجع اسم الصنف والكمية ولا تكرر المنتج');
      final unitPrice=amount(row['unitPrice'],'السعر');
      final basePrice=amount(row['basePrice'],'السعر الأصلي');
      final discount=amount(row['discountPercent'],'الخصم');
      if(discount>100)throw const FormatException('نسبة الخصم غير صحيحة');
      calculated+=unitPrice*quantity;
      items.add({'productId':productId,'productName':name.trim(),'quantity':quantity,
        'unitPrice':unitPrice,'basePrice':basePrice,'discountPercent':discount});
    }
    final total=amount(data['total'],'الإجمالي');
    final paid=amount(data['paid'],'المدفوع');
    final paymentBreakdown=normalizeSalePaymentBreakdown(data['paymentBreakdown'],paid);
    if(!calculated.isFinite||(calculated-total).abs()>0.005||paid>total||(!credit&&(paid-total).abs()>0.005))
      throw const FormatException('راجع إجمالي الفاتورة وطريقة الدفع');
    final createdAt=requiredText(data['createdAt'],'تاريخ الحفظ');
    final lastError=data['lastError'];
    if(lastError!=null&&lastError is! String)throw const FormatException('حالة المزامنة غير صحيحة');
    return OfflineEmployeeSaleData(id:id,branchId:branchId,customerId:customerId,createdAt:createdAt,
      credit:credit,total:calculated,paid:paid,paymentBreakdown:paymentBreakdown,items:items,lastError:(lastError as String?)??'');
  }

  Map<String,dynamic> toJson()=>{'id':id,'branchId':branchId,'customerId':customerId,'createdAt':createdAt,
    'credit':credit,'total':total,'paid':paid,'paymentBreakdown':paymentBreakdown,'items':items,'lastError':lastError};
  Map<String,dynamic> identityJson()=>{'id':id,'branchId':branchId,'customerId':customerId,
    'credit':credit,'total':total,'paid':paid,'paymentBreakdown':paymentBreakdown,'items':items};
  OfflineEmployeeSaleData copyWith({String? lastError})=>OfflineEmployeeSaleData(id:id,branchId:branchId,
    customerId:customerId,createdAt:createdAt,credit:credit,total:total,paid:paid,paymentBreakdown:paymentBreakdown,items:items,lastError:lastError??this.lastError);
}

class PendingSaleData {
  final List<PendingSaleLine> lines;
  final String customerId;
  final bool credit;
  final double total, paid;
  final Map<String,double> paymentBreakdown;
  PendingSaleData(this.lines, this.customerId, this.credit, this.total, this.paid, this.paymentBreakdown);

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
    final paymentBreakdown=normalizeSalePaymentBreakdown(data['paymentBreakdown'],paid);
    if(customer is! String || (customer.isNotEmpty && customer.contains('/')) || credit is! bool || !total.isFinite ||
      (customer.isEmpty && (credit || (paid-total).abs()>0.000001))) throw const FormatException('اختر عميلًا مسجلًا للآجل وراجع طريقة الدفع');
    if(paid>total || (!credit && (paid-total).abs()>0.000001)) throw const FormatException('المدفوع غير صحيح');
    return PendingSaleData(lines,customer,credit,total,paid,paymentBreakdown);
  }
}

Map<String,dynamic> repricePendingSale(Map<String,dynamic> data,List<double> prices) {
  final parsed=PendingSaleData.parse(data);
  if(prices.length!=parsed.lines.length || prices.any((p)=>!p.isFinite || p<0)) {
    throw const FormatException('راجع أسعار الأصناف');
  }
  final items=(data['items'] as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();
  var total=0.0;
  for(var i=0;i<items.length;i++) {
    items[i]['unitPrice']=prices[i];
    total+=prices[i]*parsed.lines[i].quantity;
  }
  final paid=parsed.credit ? parsed.paid : total;
  if(paid>total+0.005) throw const FormatException('المدفوع أكبر من الإجمالي الجديد؛ راجع المبلغ المدفوع');
  final nonCash=(parsed.paymentBreakdown['instapay']??0)+(parsed.paymentBreakdown['vodafoneCash']??0);
  if(nonCash-paid>0.005) throw const FormatException('الإجمالي الجديد أقل من المبالغ المحصلة إلكترونيًا؛ راجع طرق التحصيل');
  final paymentBreakdown=normalizeSalePaymentBreakdown({...parsed.paymentBreakdown,'cash':paid-nonCash},paid);
  final requestKey=jsonEncode({'customerId':parsed.customerId,'credit':parsed.credit,'paid':paid,'items':items});
  return {'items':items,'total':total,'paid':paid,'paymentBreakdown':paymentBreakdown,'requestKey':requestKey,
    'managerPriceAdjusted':true,'managerOriginalItems':data['managerOriginalItems'] ?? data['items'],
    'managerOriginalTotal':data['managerOriginalTotal'] ?? parsed.total};
}
