part of 'main.dart';

class AccountPeriodReport {
  final DateTime from,to;
  final String name;
  final bool supplier;
  final bool fromCache,pendingWrites;
  final int opening,closing,current,increase,decrease;
  final List<Map<String,dynamic>> rows;
  AccountPeriodReport(this.from,this.to,this.name,this.supplier,this.opening,this.closing,this.current,this.increase,this.decrease,this.rows,{this.fromCache=false,this.pendingWrites=false});
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
    // Firestore can serve this from its persistent local cache when the manager
    // is offline. Metadata is carried through so stale reports are clearly marked.
    final snapshot=await db.collection('accountMovements').where('accountId',isEqualTo:widget.id).get();
    final account=await db.collection(widget.collection).doc(widget.id).get();
    if(account.data()==null)throw StateError('الحساب غير موجود');
    final rows=snapshot.docs.where((d)=>d.data()['accountType']==widget.collection && visibleAfterReset(d.data())).map((d)=>{...d.data(),'id':d.id}).toList();
    for(final row in rows) {
      final ref='${row['referenceId'] ?? ''}',kind='${row['kind'] ?? ''}';
      final type=kind=='sale' || kind=='saleCorrection' ? 'sales' : kind=='purchase' || kind=='purchaseCorrection' ? 'purchases' : null;
      if(type!=null && ref.isNotEmpty) {
        final invoice=(await db.collection(type).doc(ref).get()).data();
        row['referenceLabel']=invoice==null?ref:invoiceDisplayNumber(type,ref,invoice);
      } else row['referenceLabel']=ref;
    }
    final report=summarizeAccountPeriod(rows,account.data()!,from,to,supplier:widget.collection=='suppliers');
    return AccountPeriodReport(report.from,report.to,report.name,report.supplier,report.opening,report.closing,report.current,
      report.increase,report.decrease,report.rows,fromCache:snapshot.metadata.isFromCache||account.metadata.isFromCache,
      pendingWrites:snapshot.metadata.hasPendingWrites||account.metadata.hasPendingWrites);
  }
  Future<void> printReport(AccountPeriodReport data) async {
    try {
      final confirmed=await loadReport();
      if(confirmed.fromCache||confirmed.pendingWrites)throw StateError('يتطلب حفظ كشف الحساب تأكيد مزامنة البيانات أولًا');
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
          if(r.fromCache||r.pendingWrites)Text(r.pendingWrites?'بيانات محلية بها تغييرات تنتظر المزامنة':'كشف من النسخة المحلية؛ اتصل بالإنترنت لتأكيد الأرقام والطباعة',
            style:const TextStyle(color:Colors.orangeAccent,fontWeight:FontWeight.bold),textAlign:TextAlign.center),
          Text('رصيد أول المدة: ${receiptReportMoney(r.opening)}'),
          Text('زيادة الدين: ${receiptReportMoney(r.increase)} • تخفيض الدين: ${receiptReportMoney(r.decrease)}'),
          Text('رصيد آخر المدة: ${receiptReportMoney(r.closing)}',style:const TextStyle(color:Colors.redAccent,fontWeight:FontWeight.bold)),
          Text('الرصيد الحالي: ${receiptReportMoney(r.current)}'),
          OutlinedButton.icon(onPressed:r.fromCache||r.pendingWrites?null:()=>printReport(r),icon:const Icon(Icons.picture_as_pdf),label:const Text('طباعة / حفظ كشف الحساب PDF')),
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

// One chronological, read-only stock ledger for the on-screen report and A4.
class VibProductLedgerLine {
  final DateTime date;
  final int incoming, outgoing, balance;
  final String description, movementId;
  const VibProductLedgerLine({required this.date,required this.incoming,
    required this.outgoing,required this.balance,required this.description,
    required this.movementId});
}

List<VibProductLedgerLine> buildVibProductLedger(
    List<Map<String,dynamic>> movements, Map<String,String> parties, int opening) {
  final sorted=List<Map<String,dynamic>>.from(movements);
  DateTime dateOf(Map<String,dynamic> row) {
    final timestamp=receiptEffectiveTimestamp(row);
    if(timestamp is! Timestamp) throw StateError('تاريخ حركة المخزون غير معروف');
    return timestamp.toDate();
  }
  int quantityOf(Map<String,dynamic> row) {
    final q=row['quantity'];
    if(q is! num || !q.isFinite || q!=q.round()) {
      throw StateError('كمية غير صحيحة في حركة المخزون');
    }
    return q.toInt();
  }
  sorted.sort((a,b) {
    final byDate=dateOf(a).compareTo(dateOf(b));
    return byDate!=0?byDate:'${a['id'] ?? ''}'.compareTo('${b['id'] ?? ''}');
  });
  var balance=opening;
  final result=<VibProductLedgerLine>[];
  for(final row in sorted) {
    final q=quantityOf(row);
    balance+=q;
    final kind='${row['kind'] ?? ''}';
    final party=(parties['${row['id'] ?? ''}'] ?? '').trim();
    final description=party.isEmpty?movementName(kind):'${movementName(kind)} - $party';
    result.add(VibProductLedgerLine(
      date:dateOf(row),incoming:q>0?q:0,outgoing:q<0?-q:0,
      balance:balance,description:description,movementId:'${row['id'] ?? ''}'));
  }
  return List.unmodifiable(result);
}

Future<Uint8List> createProductTracePdf(
    String name,List<Map<String,dynamic>> rows,
    Map<String,String> parties,ProductPeriodTotals total,pw.Font font,
    {DateTimeRange? range,String productCode=''}) async {
  final lines=buildVibProductLedger(rows,parties,total.opening);
  final pdf=pw.Document();
  const header=PdfColor.fromInt(0xFF283B46);
  const border=PdfColor.fromInt(0xFF687985);
  const greenBg=PdfColor.fromInt(0xFFD8F9D9);
  const pinkBg=PdfColor.fromInt(0xFFFFE2D5);
  const stripe=PdfColor.fromInt(0xFFF3F5F7);
  pw.Widget cell(String value,{bool head=false,PdfColor? bg,bool bold=false})=>
    pw.Container(color:bg,padding:const pw.EdgeInsets.symmetric(horizontal:5,vertical:6),
      child:pw.Text(value,textAlign:pw.TextAlign.center,
        style:pw.TextStyle(font:font,fontSize:head?10.5:9.4,
          color:head?PdfColors.white:PdfColors.black,
          fontWeight:head||bold?pw.FontWeight.bold:pw.FontWeight.normal)));
  final fromLabel=range==null?'كل الفترات':DateFormat('dd/MM/yyyy').format(range.start);
  final toLabel=range==null?'حتى الآن':DateFormat('dd/MM/yyyy').format(range.end);
  pdf.addPage(pw.MultiPage(
    pageFormat:PdfPageFormat.a4,maxPages:1000,
    margin:const pw.EdgeInsets.fromLTRB(22,24,22,24),
    theme:pw.ThemeData.withFont(base:font,bold:font),
    textDirection:pw.TextDirection.rtl,
    footer:(ctx)=>pw.Align(alignment:pw.Alignment.center,child:pw.Text(
      'صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
      style:pw.TextStyle(font:font,fontSize:9,color:PdfColors.grey700))),
    build:(_)=>[
      pw.Center(child:pw.Text('VIB للتجارة والتوزيع',
        style:pw.TextStyle(font:font,fontSize:18,
          fontWeight:pw.FontWeight.bold,color:header))),
      pw.SizedBox(height:6),
      pw.Center(child:pw.Text('تقرير حركة منتج',
        style:pw.TextStyle(font:font,fontSize:15,fontWeight:pw.FontWeight.bold))),
      pw.SizedBox(height:5),
      pw.Center(child:pw.Text('للفترة من $fromLabel إلى $toLabel',
        style:pw.TextStyle(font:font,fontSize:11))),
      pw.SizedBox(height:4),
      pw.Center(child:pw.Text('المنتج: $name'+
        (productCode.isEmpty?'':'    رقم المنتج: $productCode'),
        style:pw.TextStyle(font:font,fontSize:11))),
      pw.SizedBox(height:12),
      pw.Table(
        border:pw.TableBorder.all(color:border,width:.6),
        columnWidths:{
          0:const pw.FlexColumnWidth(2.65),
          1:const pw.FlexColumnWidth(.86),
          2:const pw.FlexColumnWidth(.72),
          3:const pw.FlexColumnWidth(.72),
          4:const pw.FlexColumnWidth(1.35),
        },
        children:[
          pw.TableRow(repeat:true,decoration:const pw.BoxDecoration(color:header),
            children:[
              cell('البيان',head:true),cell('الرصيد',head:true),
              cell('صادر',head:true),cell('وارد',head:true),
              cell('التاريخ',head:true),
            ]),
          pw.TableRow(decoration:const pw.BoxDecoration(color:stripe),
            children:[
              cell('رصيد أول المدة'),cell('${total.opening}',bold:true),
              cell(''),cell(''),
              cell(range==null?'بداية السجل':DateFormat('yyyy/MM/dd').format(range.start)),
            ]),
          for(var i=0;i<lines.length;i++)
            pw.TableRow(
              decoration:i.isOdd?const pw.BoxDecoration(color:stripe):null,
              children:[
                cell(lines[i].description),
                cell('${lines[i].balance}',bold:true),
                cell(lines[i].outgoing==0?'':'${lines[i].outgoing}',
                  bg:lines[i].outgoing==0?null:pinkBg),
                cell(lines[i].incoming==0?'':'${lines[i].incoming}',
                  bg:lines[i].incoming==0?null:greenBg),
                cell(DateFormat('yyyy/MM/dd').format(lines[i].date)),
              ]),
        ],
      ),
      pw.SizedBox(height:12),
      pw.Text('الوارد: ${total.incoming}    الصادر: ${total.outgoing}    أول المدة: ${total.opening}    آخر المدة: ${total.closing}',
        style:pw.TextStyle(font:font,fontSize:10,fontWeight:pw.FontWeight.bold)),
      if(total.gap!=0) pw.Text(
        'تنبيه: فرق جرد ${total.gap} بين الرصيد الحالي وآخر الحركات. لم تُعدل البيانات.',
        style:pw.TextStyle(font:font,fontSize:9,color:PdfColors.red)),
      pw.SizedBox(height:6),
      pw.Text('التقرير للعرض فقط من سجل حركة المخزون. لا يغير الفواتير أو الكميات أو الحسابات.',
        style:pw.TextStyle(font:font,fontSize:8.5,color:PdfColors.grey700)),
    ],
  ));
  return pdf.save();
}
