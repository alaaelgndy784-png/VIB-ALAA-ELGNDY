part of 'main.dart';

final invoiceSerialCache = <String, Map<String,dynamic>>{};
final _serialPreparations = <String, Future<void>>{};
String serialKey(String type, String id) => '${type}_$id';
String invoiceDisplayNumber(String type, String id, Map<String,dynamic> data) {
  final n = data['internalNumber'] ?? invoiceSerialCache[serialKey(type,id)]?['internalNumber'];
  if(n is int && n > 0) return n.toString().padLeft(6,'0');
  return '${data['invoiceNumber']??''}'.trim().isNotEmpty ? '${data['invoiceNumber']}' : id;
}
class InvoiceSerialReservation {
  final Map<String,dynamic> data;
  final DocumentReference<Map<String,dynamic>> counter, marker, claim;
  final bool existing;
  InvoiceSerialReservation(this.data,this.counter,this.marker,this.claim,this.existing);
}
Future<InvoiceSerialReservation> readInvoiceSerial(Transaction tx, String type, String id) async {
  final plan=await reserveInvoiceSerial(type,id,(path)async=>(await tx.get(db.doc(path))).data());
  return InvoiceSerialReservation({...plan.data,if(!plan.existing)'createdAt':FieldValue.serverTimestamp()},
    db.doc(plan.counter),db.doc(plan.marker),db.doc(plan.claim),plan.existing);
}
void writeInvoiceSerial(Transaction tx, InvoiceSerialReservation serial) {
  if(serial.existing)return;
  tx.set(serial.marker,serial.data);
  tx.set(serial.claim,{'invoiceId':serial.data['invoiceId'],'invoiceType':serial.data['invoiceType'],'createdAt':FieldValue.serverTimestamp()});
  tx.set(serial.counter,{'lastNumber':serial.data['internalNumber'],'updatedAt':FieldValue.serverTimestamp()});
}
Future<Map<String,dynamic>> ensureInvoiceSerial(String type, String id) async {
  final value=await db.runTransaction<Map<String,dynamic>>((tx) async {
    final uid=FirebaseAuth.instance.currentUser!.uid;
    final profile=(await tx.get(db.collection('users').doc(uid))).data();
    if(profile?['active']!=true || profile?['role']!='owner')throw StateError('تخصيص الرقم المتسلسل متاح للمدير');
    if(!(await tx.get(db.collection(type).doc(id))).exists)throw StateError('الفاتورة غير موجودة');
    final serial=await readInvoiceSerial(tx,type,id);
    writeInvoiceSerial(tx,serial);return serial.data;
  });
  invoiceSerialCache[serialKey(type,id)]=value;return value;
}
Future<void> prepareInvoiceSerials(String type) {
  final key='${FirebaseAuth.instance.currentUser!.uid}:$type';
  return _serialPreparations.putIfAbsent(key,() async {
    try {
      final markers=await db.collection('settings').where('kind',isEqualTo:'invoiceSerial_$type').get(const GetOptions(source:Source.server));
      for(final marker in markers.docs)invoiceSerialCache[serialKey(type,'${marker.data()['invoiceId']}')]=marker.data();
      final invoices=await db.collection(type).get(const GetOptions(source:Source.server));
      final rows=invoices.docs.toList()..sort((a,b){
        final left=(a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch??0,right=(b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch??0;
        final cmp=left.compareTo(right);return cmp==0?a.id.compareTo(b.id):cmp;
      });
      for(final row in rows){if(!invoiceSerialCache.containsKey(serialKey(type,row.id)))await ensureInvoiceSerial(type,row.id);}
    }finally{_serialPreparations.remove(key);}
  });
}
Future<Map<String,dynamic>> numberedInvoiceData(String type,String id,Map<String,dynamic> data) async {
  if(data['internalNumber'] is int)return data;
  final profile=(await db.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).get()).data();
  if(profile?['role']!='owner')return data;
  final serial=await ensureInvoiceSerial(type,id);
  return {...data,'internalNumber':serial['internalNumber'],'invoiceBarcode':serial['invoiceBarcode']};
}

Future<String> resolveInvoiceNumber(String type,String input) async {
  final value=input.trim(),match=RegExp(r'^VIB-([PS])-(\d+)$').firstMatch(input.trim());
  if(match!=null && match.group(1)!=(type=='purchases'?'P':'S'))throw StateError('الباركود يخص نوع فاتورة آخر');
  final n=int.tryParse(match?.group(2)??value);
  if(n==null || n<=0)return value;
  try {
    final claim=(await db.collection('settings').doc('invoiceSerialClaim_${type}_$n').get(const GetOptions(source:Source.server))).data();
    if(claim!=null && claim['invoiceType']==type && claim['invoiceId'] is String)return claim['invoiceId'] as String;
  } on FirebaseException catch(e){if(e.code!='permission-denied')rethrow;}
  return value;
}
Future<void> printInvoiceBarcode(BuildContext context,String type,String id,Map<String,dynamic> data) async {
  try {
    data=await numberedInvoiceData(type,id,data);
    final barcode='${data['invoiceBarcode']??''}';
    if(barcode.isEmpty)throw StateError('راجع الفاتورة من حساب المدير لتخصيص رقمها أولًا');
    final font=pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final pdf=pw.Document();
    pdf.addPage(pw.Page(pageFormat:PdfPageFormat(58*PdfPageFormat.mm,35*PdfPageFormat.mm,marginAll:3*PdfPageFormat.mm),
      build:(_)=>pw.Column(children:[
        pw.Directionality(textDirection:pw.TextDirection.rtl,child:pw.Text('${type=='purchases'?'مشتريات':'مبيعات'} • ${invoiceDisplayNumber(type,id,data)}',style:pw.TextStyle(font:font,fontSize:10))),
        pw.SizedBox(height:6),pw.BarcodeWidget(barcode:pw.Barcode.code128(),data:barcode,width:135,height:42,drawText:true,textStyle:const pw.TextStyle(fontSize:8)),
      ])));
    final bytes=await pdf.save();
    await Printing.layoutPdf(name:'$barcode.pdf',onLayout:(_)async=>bytes);
  }catch(e){if(context.mounted)await showInvoiceSaveProblem(context,'تعذر طباعة الباركود: $e',title:'طباعة الباركود',button:'تمام');}
}


final _requestedSeriesInit=<String,Future<void>>{};
Future<void> initializeRequestedInvoiceSeries() {
  final uid=FirebaseAuth.instance.currentUser!.uid;
  return _requestedSeriesInit.putIfAbsent(uid,() async {
    try {
    final done=db.collection('settings').doc('vipSeries20261005');
    if((await done.get(const GetOptions(source:Source.server))).exists)return;
    // Number earlier invoices first, then seed only the next new invoice number.
    await prepareInvoiceSerials('sales');await prepareInvoiceSerials('purchases');
    await db.runTransaction((tx) async {
      if((await tx.get(done)).exists)return;
      final profile=(await tx.get(db.collection('users').doc(uid))).data();
      if(profile?['role']!='owner' || profile?['active']!=true)throw StateError('تجهيز التسلسل متاح للمدير');
      final sales=db.collection('settings').doc('invoiceCounter_sales'),purchases=db.collection('settings').doc('invoiceCounter_purchases');
      final s=(await tx.get(sales)).data(),p=(await tx.get(purchases)).data();
      final sn=requestedSeriesLast((s?['lastNumber'] as int?)??0,1223),pn=requestedSeriesLast((p?['lastNumber'] as int?)??0,431);
      final sc=await tx.get(db.collection('settings').doc('invoiceSerialClaim_sales_${sn+1}'));
      final pc=await tx.get(db.collection('settings').doc('invoiceSerialClaim_purchases_${pn+1}'));
      if(sc.exists || pc.exists)throw StateError('الرقم المطلوب محجوز؛ راجع التسلسل');
      final at=FieldValue.serverTimestamp();
      tx.set(sales,{'lastNumber':sn,'updatedAt':at});tx.set(purchases,{'lastNumber':pn,'updatedAt':at});
      tx.set(done,{'salesNext':sn+1,'purchasesNext':pn+1,'requestedSales':1223,'requestedPurchases':431,'actorId':uid,'createdAt':at});
    });
    } catch(e) {_requestedSeriesInit.remove(uid);if(ManagerOfflineOutbox.isOfflineError(e))return;rethrow;}
  });
}
