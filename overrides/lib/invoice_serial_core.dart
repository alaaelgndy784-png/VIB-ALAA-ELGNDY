String invoiceBarcodeValue(String type,int number) => 'VIB-${type=='purchases'?'P':'S'}-${number.toString().padLeft(6,'0')}';
class InvoiceSerialPlan {
  final Map<String,dynamic> data;
  final String counter,marker,claim;
  final bool existing;
  InvoiceSerialPlan(this.data,this.counter,this.marker,this.claim,this.existing);
}
Future<InvoiceSerialPlan> reserveInvoiceSerial(String type,String id,Future<Map<String,dynamic>?> Function(String) read) async {
  if(!['sales','purchases'].contains(type) || id.isEmpty || id.contains('/'))throw StateError('نوع أو رمز الفاتورة غير صحيح');
  final counter='settings/invoiceCounter_$type',marker='settings/invoiceSerial_${type}_$id';
  final saved=await read(marker);
  if(saved!=null){
    final n=saved['internalNumber'];
    if(n is! int || n<=0 || n>999999999 || saved['invoiceId']!=id || saved['invoiceType']!=type || saved['invoiceBarcode']!=invoiceBarcodeValue(type,n))throw StateError('رقم الفاتورة يحتاج مراجعة');
    final claim='settings/invoiceSerialClaim_${type}_$n',reservation=await read('settings/invoiceSerialClaim_${type}_$n');
    if(reservation?['invoiceId']!=id || reservation?['invoiceType']!=type)throw StateError('حجز رقم الفاتورة يحتاج مراجعة');
    return InvoiceSerialPlan(saved,counter,marker,claim,true);
  }
  final state=await read(counter),last=state?['lastNumber']??0;
  if(last is! int || last<0 || last>=999999999)throw StateError('عداد الفواتير يحتاج مراجعة');
  final n=last+1,claim='settings/invoiceSerialClaim_${type}_${last+1}';
  if(await read(claim)!=null)throw StateError('العداد تغيّر؛ الرقم محجوز بالفعل ولا يمكن تكراره');
  return InvoiceSerialPlan({'kind':'invoiceSerial_$type','invoiceType':type,'invoiceId':id,
    'internalNumber':n,'invoiceBarcode':invoiceBarcodeValue(type,n)},counter,marker,claim,false);
}


int requestedSeriesLast(int current,int first) {
  if(current<0 || first<=0 || first>999999999)throw StateError('بداية التسلسل غير صحيحة');
  return current>=first ? current : first-1;
}
