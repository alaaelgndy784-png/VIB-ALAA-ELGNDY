part of 'main.dart';

class AccountPeriodReport {
  final DateTime from,to;
  final String name;
  final bool supplier;
  final int opening,closing,current,increase,decrease;
  final List<Map<String,dynamic>> rows;
  AccountPeriodReport(this.from,this.to,this.name,this.supplier,this.opening,this.closing,this.current,this.increase,this.decrease,this.rows);
}
int ledgerCents(Object? value) {
  if(value is! num || !value.toDouble().isFinite) throw StateError('يوجد رصيد غير صحيح؛ راجع الحساب');
  return (value*100).round();
}
AccountPeriodReport summarizeAccountPeriod(List<Map<String,dynamic>> movements,Map<String,dynamic> account,
    DateTime from,DateTime to,{required bool supplier}) {
  final start=movementReportBoundary(from),end=movementReportBoundary(to,next:true);
  if(to.isBefore(from))throw StateError('تاريخ البداية بعد النهاية');
  final current=ledgerCents(account['balance'] ?? 0);
  var closing=current,increase=0,decrease=0;
  final rows=<Map<String,dynamic>>[];
  for(final row in movements) {
    final stamp=receiptEffectiveTimestamp(row);
    if(stamp is! Timestamp) throw StateError('يوجد تاريخ حركة غير مؤكد؛ انتظر المزامنة');
    final delta=ledgerCents(row['balanceAfter'])-ledgerCents(row['balanceBefore']);
    if(stamp.toDate().isBefore(start)) continue;
    if(!stamp.toDate().isBefore(end)) {closing-=delta;continue;}
    if(delta>=0)increase+=delta;else decrease-=delta;
    rows.add({...row,'deltaCents':delta});
  }
  rows.sort((a,b){final cmp=receiptEffectiveTimestamp(a)!.compareTo(receiptEffectiveTimestamp(b)!);return cmp==0?'${a['id']}'.compareTo('${b['id']}'):cmp;});
  final opening=closing-increase+decrease;
  var balance=opening;
  for(final row in rows) {balance+=row['deltaCents'] as int;row['periodBalance']=balance;}
  return AccountPeriodReport(from,to,'${account['name'] ?? ''}',supplier,opening,closing,current,increase,decrease,rows);
}

class AccountStatementPage extends StatefulWidget {
  final String collection,id;
  const AccountStatementPage({super.key,required this.collection,required this.id});
  @override State<AccountStatementPage> createState()=>_AccountStatementPageState();
}
class _AccountStatementPageState extends State<AccountStatementPage> {
  late DateTime from,to;
  Future<AccountPeriodReport>? report;
  @override void initState() {
    super.initState();final now=tz.TZDateTime.now(tz.getLocation('Africa/Cairo'));
    from=DateTime(now.year,now.month,1);to=DateTime(now.year,now.month,now.day);report=loadReport();
  }
  Future<AccountPeriodReport> loadReport() async {
    final snapshot=await db.collection('accountMovements').where('accountId',isEqualTo:widget.id).get(const GetOptions(source:Source.server));
    final account=await db.collection(widget.collection).doc(widget.id).get(const GetOptions(source:Source.server));
    if(snapshot.metadata.hasPendingWrites || account.metadata.hasPendingWrites)throw StateError('انتظر تأكيد الحركات من السيرفر');
    if(account.data()==null)throw StateError('الحساب غير موجود');
    final rows=snapshot.docs.where((d)=>d.data()['accountType']==widget.collection && visibleAfterReset(d.data())).map((d)=>{...d.data(),'id':d.id}).toList();
    for(final row in rows) {
      final ref='${row['referenceId'] ?? ''}',kind='${row['kind'] ?? ''}';
      final type=kind=='sale' || kind=='saleCorrection' ? 'sales' : kind=='purchase' || kind=='purchaseCorrection' ? 'purchases' : null;
      if(type!=null && ref.isNotEmpty) {
        final invoice=(await db.collection(type).doc(ref).get(const GetOptions(source:Source.server))).data();
        row['referenceLabel']=invoice==null?ref:invoiceDisplayNumber(type,ref,invoice);
      } else row['referenceLabel']=ref;
    }
    return summarizeAccountPeriod(rows,account.data()!,from,to,supplier:widget.collection=='suppliers');
  }
  Future<void> printReport(AccountPeriodReport data) async {
    try {
      final confirmed=await loadReport();
      final font=pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final bytes=await createAccountStatementPdf(confirmed,font);
      await Printing.layoutPdf(name:'VIB-ACCOUNT-${widget.id}.pdf',onLayout:(_)async=>bytes);
    } catch(e) {if(mounted)await showInvoiceSaveProblem(context,'تعذر طباعة كشف الحساب: $e');}
  }
  @override Widget build(BuildContext context)=>Column(children:[
    MovementPeriodControls(from:from,to:to,enabled:true,onConfirm:(a,b)=>setState((){from=a;to=b;report=loadReport();})),
    Expanded(child:FutureBuilder<AccountPeriodReport>(future:report,builder:(context,snapshot){
      if(snapshot.hasError)return Center(child:Text('تعذر تحميل كشف الحساب: ${snapshot.error}',textAlign:TextAlign.center));
      if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
      final r=snapshot.data!;
      return Column(children:[
        Card(child:Padding(padding:const EdgeInsets.all(10),child:Column(children:[
          Text(r.name,style:const TextStyle(color:Colors.lightBlueAccent,fontWeight:FontWeight.bold)),
          Text('رصيد أول المدة: ${receiptReportMoney(r.opening)}'),
          Text('زيادة الدين: ${receiptReportMoney(r.increase)} • تخفيض الدين: ${receiptReportMoney(r.decrease)}'),
          Text('رصيد آخر المدة: ${receiptReportMoney(r.closing)}',style:const TextStyle(color:Colors.redAccent,fontWeight:FontWeight.bold)),
          Text('الرصيد الحالي: ${receiptReportMoney(r.current)}'),
          OutlinedButton.icon(onPressed:()=>printReport(r),icon:const Icon(Icons.picture_as_pdf),label:const Text('طباعة / حفظ كشف الحساب PDF')),
        ]))),
        Expanded(child:r.rows.isEmpty?const Center(child:Text('لا توجد حركات خلال الفترة؛ رصيد أول وآخر المدة ظاهر بالأعلى')):
          ListView.builder(itemCount:r.rows.length,itemBuilder:(context,i){final row=r.rows[i];final delta=row['deltaCents'] as int;
            return ListTile(leading:Text('${i+1}'),title:Text('${movementName('${row['kind']}')} • ${row['referenceLabel'] ?? ''}'),
              subtitle:Text('${receiptReportStamp(row,r.to)}\nالرصيد: ${receiptReportMoney(row['periodBalance'] as int)}${'${row['reason'] ?? ''}'.isEmpty?'':'\n${row['reason']}'}'),
              trailing:Text('${delta>=0?'+':'-'}${receiptReportMoney(delta.abs())}',style:TextStyle(color:delta>=0?Colors.redAccent:Colors.greenAccent)));})),
      ]);
    })),
  ]);
}
Future<Uint8List> createAccountStatementPdf(AccountPeriodReport r,pw.Font font) async {
  final pdf=pw.Document();
  pw.Widget cell(String text,{bool head=false})=>pw.Padding(padding:const pw.EdgeInsets.all(5),child:pw.Text(text,textAlign:pw.TextAlign.right,style:pw.TextStyle(fontSize:9,color:head?PdfColors.white:PdfColors.black)));
  pdf.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,maxPages:1000,theme:pw.ThemeData.withFont(base:font,bold:font),textDirection:pw.TextDirection.rtl,
    footer:(c)=>pw.Text('${c.pageNumber} / ${c.pagesCount}',textAlign:pw.TextAlign.center),build:(_)=>[
      pw.Text('VIB للتجارة والتوزيع',style:pw.TextStyle(fontSize:22)),
      pw.Text('كشف حساب ${r.supplier?'مورد':'عميل'}: ${r.name}',style:pw.TextStyle(fontSize:17)),
      pw.Text('من ${DateFormat('dd/MM/yyyy').format(r.from)} إلى ${DateFormat('dd/MM/yyyy').format(r.to)} - شامل اليوم الأخير'),
      pw.SizedBox(height:10),pw.Text('رصيد أول المدة: ${receiptReportMoney(r.opening)}'),
      pw.Text('زيادة الدين: ${receiptReportMoney(r.increase)} - تخفيض الدين: ${receiptReportMoney(r.decrease)}'),
      pw.Text('رصيد آخر المدة: ${receiptReportMoney(r.closing)}',style:pw.TextStyle(fontSize:14,fontWeight:pw.FontWeight.bold)),
      pw.Text('الرصيد الحالي: ${receiptReportMoney(r.current)}'),pw.SizedBox(height:12),
      if(r.rows.isEmpty)pw.Text('لا توجد حركات في الفترة المختارة'),
      pw.Table(border:pw.TableBorder.all(width:.4),columnWidths:{0:const pw.FlexColumnWidth(1.4),1:const pw.FlexColumnWidth(1.2),2:const pw.FlexColumnWidth(1.2),3:const pw.FlexColumnWidth(2.4),4:const pw.FlexColumnWidth(1.4),5:const pw.FlexColumnWidth(.4)},children:[
        pw.TableRow(repeat:true,decoration:const pw.BoxDecoration(color:PdfColor.fromInt(0xFF14263D)),children:['الرصيد','تخفيض الدين','زيادة الدين','الحركة / المرجع','التاريخ','م'].map((v)=>cell(v,head:true)).toList()),
        for(var i=0;i<r.rows.length;i++)pw.TableRow(children:[
          cell(receiptReportMoney(r.rows[i]['periodBalance'] as int)),
          cell(receiptReportMoney((r.rows[i]['deltaCents'] as int)<0?-(r.rows[i]['deltaCents'] as int):0)),
          cell(receiptReportMoney((r.rows[i]['deltaCents'] as int)>0?r.rows[i]['deltaCents'] as int:0)),
          cell('${movementName('${r.rows[i]['kind']}')}\n${r.rows[i]['referenceLabel'] ?? ''}'),
          cell(receiptReportStamp(r.rows[i],r.to)),cell('${i+1}')]),
      ]),
    ]));
  return pdf.save();
}

class ProductPeriodTotals {
  final int opening,closing,current,incoming,outgoing,gap;
  ProductPeriodTotals(this.opening,this.closing,this.current,this.incoming,this.outgoing,this.gap);
}
ProductPeriodTotals summarizeProductPeriod(List<Map<String,dynamic>> rows,int current,DateTimeRange? range) {
  var after=0,incoming=0,outgoing=0;
  final latest=<String,Map<String,dynamic>>{};
  for(final row in rows) {
    final at=receiptEffectiveTimestamp(row);final q=row['quantity'];
    if(at is! Timestamp || q is! num || !q.isFinite || q!=q.round())throw StateError('يوجد تاريخ أو عدد غير مؤكد في حركات المنتج');
    final branch='${row['branchId']}';
    if(latest[branch]==null || at.compareTo(latest[branch]!['createdAt'] as Timestamp)>=0)latest[branch]=row;
    if(range!=null && !at.toDate().isBefore(movementReportBoundary(range.end,next:true))) {after+=q.toInt();continue;}
    if(range!=null && at.toDate().isBefore(movementReportBoundary(range.start)))continue;
    if(q>=0)incoming+=q.toInt();else outgoing-=q.toInt();
  }
  final closing=current-after,opening=closing-incoming+outgoing;
  final recorded=latest.values.fold<int>(0,(sum,row)=>sum+((row['balanceAfter'] as num?)?.toInt() ?? 0));
  return ProductPeriodTotals(opening,closing,current,incoming,outgoing,current-recorded);
}
Future<Uint8List> createProductTracePdf(String name,List<Map<String,dynamic>> rows,Map<String,String> parties,ProductPeriodTotals total,pw.Font font,{DateTimeRange? range}) async {
  final pdf=pw.Document();
  pw.Widget cell(String value,{bool head=false})=>pw.Padding(padding:const pw.EdgeInsets.all(5),child:pw.Text(value,textAlign:pw.TextAlign.right,style:pw.TextStyle(fontSize:9,color:head?PdfColors.white:PdfColors.black)));
  pdf.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,maxPages:1000,theme:pw.ThemeData.withFont(base:font,bold:font),textDirection:pw.TextDirection.rtl,
    footer:(c)=>pw.Text('${c.pageNumber} / ${c.pagesCount}',textAlign:pw.TextAlign.center),build:(_)=>[
      pw.Text('VIB للتجارة والتوزيع',style:pw.TextStyle(fontSize:22)),pw.Text('تقرير حركة المنتج: $name',style:pw.TextStyle(fontSize:17)),
      pw.Text(range==null?'كل الحركات المسجلة':'من ${DateFormat('dd/MM/yyyy').format(range.start)} إلى ${DateFormat('dd/MM/yyyy').format(range.end)} - شامل اليوم الأخير'),
      pw.Text('أول المدة: ${total.opening} - الداخل: ${total.incoming} - الخارج: ${total.outgoing} - آخر المدة: ${total.closing}'),
      pw.Text('الموجود الآن: ${total.current}'),if(total.gap!=0)pw.Text('فرق بين المخزون وآخر حركة مسجلة: ${total.gap} - يحتاج مراجعة'),pw.SizedBox(height:12),
      pw.Table(border:pw.TableBorder.all(width:.4),columnWidths:{0:const pw.FlexColumnWidth(1),1:const pw.FlexColumnWidth(1),2:const pw.FlexColumnWidth(3.5),3:const pw.FlexColumnWidth(1.6),4:const pw.FlexColumnWidth(1.7),5:const pw.FlexColumnWidth(.4)},children:[
        pw.TableRow(repeat:true,decoration:const pw.BoxDecoration(color:PdfColor.fromInt(0xFF14263D)),children:['الرصيد','العدد','الطرف / الفاتورة / المستخدم','التاريخ','الحركة','م'].map((v)=>cell(v,head:true)).toList()),
        for(var i=0;i<rows.length;i++)pw.TableRow(children:[cell('${rows[i]['balanceAfter'] ?? '-'}'),cell('${rows[i]['quantity']}'),cell(parties['${rows[i]['id']}'] ?? ''),
          cell(receiptReportStamp(rows[i],DateTime.now())),cell(movementName('${rows[i]['kind']}')),cell('${i+1}')]),
      ]),
    ]));return pdf.save();
}
