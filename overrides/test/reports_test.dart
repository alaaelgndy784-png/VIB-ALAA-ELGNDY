import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import '../lib/main.dart';
import '../lib/inventory_rows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async { initializeChequeTimeZones(); final loader=FontLoader('VIBQA')..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf'));await loader.load(); });
  final day=DateTime(2026,10,4);
  testWidgets('typed sales report dates are applied when the period button is pressed', (tester) async {
    DateTime? appliedFrom, appliedTo;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MovementPeriodControls(
      from: DateTime(2026, 10, 8), to: DateTime(2026, 10, 8), enabled: true,
      onConfirm: (from, to) { appliedFrom = from; appliedTo = to; },
    ))));
    await tester.enterText(find.byKey(const ValueKey('period-from-input')), '01/10/2026');
    await tester.enterText(find.byKey(const ValueKey('period-to-input')), '05/10/2026');
    await tester.pump();
    final apply = find.byKey(const ValueKey('period-apply-button'));
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
    await tester.tap(apply);
    expect(appliedFrom, DateTime(2026, 10, 1));
    expect(appliedTo, DateTime(2026, 10, 5));
    expect(tester.takeException(), isNull);
  });

  Map<String,dynamic> invoice(String id,num total,{num? paid,num? due,num receipts=0,String status='completed',DateTime? at}) => {
    'id':id,'displayNumber':id,'customerName':'عميل $id','supplierName':'مورد $id',
    'total':total,if(paid!=null)'paid':paid,if(due!=null)'due':due,'receiptPaid':receipts,
    'status':status,'createdAt':Timestamp.fromDate(at ?? movementReportBoundary(day)),
  };
  test('receipt period includes both Cairo date boundaries and groups actual customers',() {
    final from=DateTime(2026,10,1),to=DateTime(2026,10,3);
    final start=movementReportBoundary(from),end=movementReportBoundary(to,next:true);
    Map<String,dynamic> row(String id,String customer,num amount,DateTime at)=>{'id':id,'customerId':customer,
      'customerName':'عميل بنفس الاسم','amount':amount,'createdAt':Timestamp.fromDate(at)};
    final report=summarizeReceiptPeriod([
      row('before','a',999,start.subtract(const Duration(milliseconds:1))),
      row('first','a',.1,start),row('middle','a',.2,movementReportBoundary(DateTime(2026,10,2))),
      row('last','b',50.25,end.subtract(const Duration(milliseconds:1))),row('after','b',999,end),
    ],from,to);
    expect(report.totalCents,5055);expect(report.receiptCount,3);expect(report.customers.length,2);
    expect(report.customers.firstWhere((c)=>c.id=='a').amountCents,30);
    expect(()=>summarizeReceiptPeriod([],to,from),throwsStateError);
    expect(summarizeReceiptPeriod([],from,to).totalCents,0);
  });
  test('chosen receipt date drives reports and statements instead of audit timestamp',(){
    final chosen=Timestamp.fromDate(movementReportBoundary(DateTime(2026,10,2)));
    final audit=Timestamp.fromDate(movementReportBoundary(DateTime(2026,10,5)));
    final row={'id':'dated','customerId':'a','customerName':'عميل','amount':20,'receiptDate':chosen,'createdAt':audit,'balanceBefore':100,'balanceAfter':80,'kind':'collection'};
    expect(summarizeReceiptPeriod([row],DateTime(2026,10,1),DateTime(2026,10,3)).totalCents,2000);
    expect(summarizeReceiptPeriod([row],DateTime(2026,10,5),DateTime(2026,10,5)).receiptCount,0);
    final statement=summarizeAccountPeriod([row],{'name':'عميل','balance':80},DateTime(2026,10,1),DateTime(2026,10,3),supplier:false);
    expect(statement.opening,10000);expect(statement.closing,8000);expect(statement.rows.length,1);
  });
  test('append-only receipt cancellation reverses the customer ledger without deleting the receipt',(){
    final at=Timestamp.fromDate(movementReportBoundary(DateTime(2026,10,2)));
    final report=summarizeAccountPeriod([
      {'id':'receipt','kind':'collection','amount':20,'balanceBefore':100,'balanceAfter':80,'createdAt':at},
      {'id':'cancel','kind':'collectionCancellation','amount':20,'balanceBefore':80,'balanceAfter':100,'createdAt':Timestamp.fromDate(at.toDate().add(const Duration(minutes:5)))},
    ],{'name':'عميل','balance':100},DateTime(2026,10,1),DateTime(2026,10,3),supplier:false);
    expect(report.opening,10000);expect(report.closing,10000);expect(report.rows.length,2);
    expect(report.increase,2000);expect(report.decrease,2000);
  });
  testWidgets('staff percentage discount stays available with manual price locked',(tester)async{
    staffApp=true;addTearDown(()=>staffApp=false);
    final price=TextEditingController(text:'100'),qty=TextEditingController(text:'2');
    addTearDown(price.dispose);addTearDown(qty.dispose);late BuildContext page;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context){page=context;return const Scaffold();})));
    final draft=PurchaseDiscountDraft();
    final dialog=showInvoiceLineEditor(page,name:'صنف خصم',price:price,quantity:qty,discount:draft,priceEditable:false,saleScreen:true);
    await tester.pumpAndSettle();
    Finder field(String label)=>find.byWidgetPredicate((w)=>w is TextField && w.decoration?.labelText==label);
    expect(tester.widget<TextField>(field('السعر')).enabled,false);
    expect(tester.widget<TextField>(field('خصم %')).enabled,true);
    await tester.enterText(field('خصم %'),'10');await tester.pump();
    await tester.tap(find.text('متابعة'));await tester.pumpAndSettle();await dialog;
    expect(double.parse(price.text),90);expect(draft.percent,10);expect(tester.takeException(),isNull);
  });
  test('receipt period spans Cairo daylight saving boundary',() {
    final from=DateTime(2026,10,29),to=DateTime(2026,10,30);
    final start=movementReportBoundary(from),end=movementReportBoundary(to,next:true);
    expect(end.difference(start).inHours,49);
    final report=summarizeReceiptPeriod([{'id':'end','customerId':'a','customerName':'عميل','amount':1,
      'createdAt':Timestamp.fromDate(end.subtract(const Duration(milliseconds:1)))}],from,to);
    expect(report.totalCents,100);
  });
  test('customer correction removes this invoice debt and applies it once to the correct account',() {
    expect(saleCorrectionAccountDeltas('old','new',6000,6000),{'old':-6000,'new':6000});
    expect(saleCorrectionAccountDeltas('old','new',6000,3000),{'old':-6000,'new':3000});
    expect(saleCorrectionAccountDeltas('same','same',6000,3000),{'same':-3000});
    expect(saleCorrectionAccountDeltas('same','same',0,10000),{'same':10000});
    expect(saleCorrectionAccountDeltas('same','same',10000,0),{'same':-10000});
    expect(saleCorrectionAccountDeltas('old','new',0,0),{'old':0,'new':0});
    expect(saleCorrectionAccountDeltas('','new',0,10000),{'new':10000});
    expect(()=>saleCorrectionAccountDeltas('old','',100,100),throwsStateError);
  });
  test('generate dated customer repayment reports on A4 and 80mm',() async {
    final from=DateTime(2026,10,1),to=DateTime(2026,10,3);
    final font=pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final report=summarizeReceiptPeriod(List.generate(9,(i)=>{'id':'RC-${10001+i}','customerId':'${i%3}',
      'customerName':'عميل الاختبار رقم ${i%3+1}','actorName':i%2==0 ? 'المدير' : 'موظف التحصيل',
      'amount':100.25+i,'createdAt':Timestamp.fromDate(movementReportBoundary(DateTime(2026,10,i%3+1)).add(Duration(hours:10+i)))}),from,to);
    Directory('dist').createSync(recursive:true);
    for(final thermal in [false,true]) {
      final bytes=await createCustomerPaymentReportPdf(from,report,font,owner:true,thermal:thermal,to:to);
      expect(bytes.length,greaterThan(1000));
      File('dist/VIB-REPAYMENTS-PERIOD-${thermal ? '80MM' : 'A4'}.pdf').writeAsBytesSync(bytes);
    }
  });
  test('account statement includes final Cairo day and derives opening excluding later activity',(){
    Map<String,dynamic> row(String id,int day,int before,int after)=>{'id':id,'createdAt':Timestamp.fromDate(movementReportBoundary(DateTime(2026,10,day))),'balanceBefore':before,'balanceAfter':after,'kind':'sale'};
    final rows=[row('a',1,100,300),row('b',3,300,220),row('c',4,220,250)];
    final r=summarizeAccountPeriod(rows,{'name':'عميل','balance':250},DateTime(2026,10,1),DateTime(2026,10,3),supplier:false);
    expect(r.opening,10000);expect(r.closing,22000);expect(r.current,25000);expect(r.increase,20000);expect(r.decrease,8000);
    expect(r.rows.length,2);expect(r.rows.last['periodBalance'],22000);
    final empty=summarizeAccountPeriod(rows,{'balance':250},DateTime(2026,10,2),DateTime(2026,10,2),supplier:true);
    expect(empty.rows,isEmpty);expect(empty.opening,30000);expect(empty.closing,30000);
    expect(()=>summarizeAccountPeriod([{'createdAt':Timestamp.now()}],{'balance':0},DateTime(2026,10,1),DateTime(2026,10,3),supplier:false),throwsStateError);
  });
  test('product trace separates period from future movement and highlights unexplained stock difference',(){
    Map<String,dynamic> row(int day,int qty,int balance)=>{'branchId':'main','createdAt':Timestamp.fromDate(movementReportBoundary(DateTime(2026,10,day))),'quantity':qty,'balanceAfter':balance};
    final rows=[row(1,-5,15),row(3,3,18),row(4,-10,8)];
    final range=DateTimeRange(start:DateTime(2026,10,1),end:DateTime(2026,10,3));
    final r=summarizeProductPeriod(rows,8,range);
    expect(r.opening,20);expect(r.closing,18);expect(r.incoming,3);expect(r.outgoing,5);expect(r.gap,0);
    expect(summarizeProductPeriod(rows,7,range).gap,-1);
  });
  testWidgets('employee product colours and compact fields render on narrow phone',(tester) async {
    staffApp=true;addTearDown(()=>staffApp=false);
    tester.view.physicalSize=const Size(360,740);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final price=TextEditingController(text:'224.40'),qty=TextEditingController(text:'12');addTearDown(price.dispose);addTearDown(qty.dispose);
    final boundary=GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key:boundary,child:MaterialApp(theme:ThemeData.dark().copyWith(textTheme:ThemeData.dark().textTheme.apply(fontFamily:'VIBQA')),
      builder:(c,child)=>Directionality(textDirection:TextDirection.rtl,child:child!),home:Scaffold(body:ListView(children:[
        const InventoryProductCard(employee:true,number:1,name:'محول مسطرة فيردي',quantity:12,unitPrice:224.4),
        InvoiceProductOptionRow(name:'محول البحث',unitCost:200,quantityStream:Stream.value(12)),
        InvoiceCompactTableLine(number:1,name:'محول الفاتورة',price:price,quantity:qty),
      ])))));
    await tester.pumpAndSettle();expect(tester.takeException(),isNull);
    expect(tester.widget<Text>(find.text('محول البحث')).style!.color,vibBlue);
    expect(tester.widget<Text>(find.text('المتاح: 12').last).style!.color,vibRed);
    expect(tester.widget<Text>(find.text('تكلفة الوحدة: 200.00 ج.م')).style!.color,vibNeon);
    await tester.runAsync(() async {final image=await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio:1);
      final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('dist').createSync(recursive:true);File('dist/VIB-EMPLOYEE-COLOURS.png').writeAsBytesSync(bytes!.buffer.asUint8List());image.dispose();});
  });
  testWidgets('manager cost visibility changes live in sale chooser and item dialog',(tester) async {
    saleCostVisible.value=false;addTearDown(()=>saleCostVisible.value=false);
    final price=TextEditingController(text:'250'),qty=TextEditingController(text:'1');addTearDown(price.dispose);addTearDown(qty.dispose);
    late BuildContext page;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context){page=context;return const Scaffold(body:InvoiceProductOptionRow(saleScreen:true,name:'صنف بيع',unitCost:200));})));
    expect(find.textContaining('تكلفة الوحدة'),findsNothing);
    saleCostVisible.value=true;await tester.pump();expect(find.textContaining('تكلفة الوحدة'),findsOneWidget);
    final dialog=showInvoiceLineEditor(page,name:'صنف بيع',price:price,quantity:qty,discount:PurchaseDiscountDraft(),unitCost:200,saleScreen:true);
    await tester.pumpAndSettle();expect(find.textContaining('سعر التكلفة'),findsOneWidget);
    saleCostVisible.value=false;await tester.pump();expect(find.textContaining('تكلفة الوحدة'),findsNothing);expect(find.textContaining('سعر التكلفة'),findsNothing);
    await tester.tap(find.text('تراجع'));await tester.pumpAndSettle();await dialog;expect(tester.takeException(),isNull);
  });
  test('generate account statements and trace PDFs',() async {
    final font=pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final from=DateTime(2026,10,1),to=DateTime(2026,10,3);
    Directory('dist').createSync(recursive:true);
    for(final supplier in [false,true]) {
      final r=summarizeAccountPeriod(List.generate(12,(i)=>{'id':'m$i','kind':i.isEven?'purchase':'payment','referenceLabel':'000${100+i}',
        'createdAt':Timestamp.fromDate(movementReportBoundary(DateTime(2026,10,i%3+1))),
        'balanceBefore':100+i*10,'balanceAfter':110+i*10}),{'name':supplier?'المورد الاختبار':'العميل الاختبار','balance':220},from,to,supplier:supplier);
      File('dist/VIB-STATEMENT-${supplier?'SUPPLIER':'CUSTOMER'}.pdf').writeAsBytesSync(await createAccountStatementPdf(r,font));
    }
    final rows=List.generate(8,(i)=><String,dynamic>{'id':'m$i','kind':i.isEven?'purchase':'sale','quantity':i.isEven?10:-3,'balanceAfter':20+i,'branchId':'main','createdAt':Timestamp.fromDate(movementReportBoundary(DateTime(2026,10,i%3+1)))});
    File('dist/VIB-PRODUCT-TRACE.pdf').writeAsBytesSync(await createProductTracePdf('محول مسطرة فيردي',rows,{for(var i=0;i<8;i++)'m$i':'${i.isEven?'المورد':'العميل'}: اسم الاختبار\nفاتورة: 000${100+i}\nالمستخدم: موظف التحصيل'},summarizeProductPeriod(rows,27,null),font));
  });
  for(final size in [const Size(320,700),const Size(360,740),const Size(564,900)]) {
    for(final keyboard in [0.0,280.0]) {
      testWidgets('compact invoice results at ${size.width} with keyboard $keyboard',(tester) async {
        tester.view.physicalSize=size;tester.view.devicePixelRatio=1;
        addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
        final search=TextEditingController();addTearDown(search.dispose);
        final boundary=GlobalKey();
        const party='محل الراشد البنفسج 10';
        await tester.pumpWidget(RepaintBoundary(key:boundary,child:MaterialApp(theme:ThemeData.dark().copyWith(textTheme:ThemeData.dark().textTheme.apply(fontFamily:'VIBQA')),
          builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(
            viewInsets:EdgeInsets.only(bottom:keyboard),textScaler:TextScaler.linear(1.5)),child:Directionality(textDirection:TextDirection.rtl,child:child!)),
          home:Scaffold(resizeToAvoidBottomInset:false,body:InvoiceEditSearchFrame(type:'purchases',search:search,onChanged:(_){},
            results:ListView(children:[
              InvoiceEditResultCard(party:party,number:'000004',date:'03/10/2026 15:23',amount:'83048.00',blocked:false,onOpen:(){}),
              InvoiceEditResultCard(party:'محل السعيد المبارك',number:'000016',date:'04/10/2026 12:30',amount:'13721.00',blocked:true,onOpen:(){}),
            ]))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(),isNull);
        expect(tester.getSize(find.text(party)).width,greaterThan(180));
        expect(tester.getSize(find.byType(InvoiceEditResultCard).first).height,lessThan(220));
        expect(find.text('رقم الفاتورة: 000004'),findsOneWidget);
        expect(find.text('83048.00 ج.م'),findsOneWidget);
        await tester.runAsync(() async {
          final image=await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio:1);
          final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
          Directory('dist').createSync(recursive:true);
          File('dist/VIB-COMPACT-${size.width.toInt()}-${keyboard.toInt()}.png').writeAsBytesSync(bytes!.buffer.asUint8List());image.dispose();
        });
      });
    }
  }
  testWidgets('invoice quantity and price select all on each tap for direct replacement',(tester) async {
    final cost=TextEditingController(text:'224.40'),qty=TextEditingController(text:'12');
    addTearDown(cost.dispose);addTearDown(qty.dispose);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Center(child:SizedBox(width:340,
      child:PurchaseInvoiceLine(number:1,name:'محول مسطرة فيردي',cost:cost,quantity:qty,
        enabled:true,totalEditable:true,showProductActions:false,onChoose:(){},onDelete:(){},onChanged:(){}))))));
    final quantity=find.byWidgetPredicate((w)=>w is TextField && identical(w.controller,qty));
    final price=find.byWidgetPredicate((w)=>w is TextField && identical(w.controller,cost));
    await tester.tap(quantity);await tester.pump();
    expect(qty.selection,TextSelection(baseOffset:0,extentOffset:2));
    await tester.enterText(quantity,'7');
    await tester.tap(quantity);await tester.pump();
    expect(qty.selection,TextSelection(baseOffset:0,extentOffset:1));
    await tester.tap(price);await tester.pump();
    expect(cost.selection,TextSelection(baseOffset:0,extentOffset:6));
    await tester.enterText(price,'199.50');
    await tester.tap(price);await tester.pump();
    expect(cost.selection,TextSelection(baseOffset:0,extentOffset:6));
    expect(cost.text,'199.50');expect(qty.text,'7');
    expect(tester.takeException(),isNull);
  });
  testWidgets('period waits for explicit approval and supports inclusive multi-day range',(tester) async {
    DateTime? selectedStart,selectedEnd;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:MovementPeriodControls(
      from:DateTime(2026,10,1),to:DateTime(2026,10,3),enabled:true,
      onConfirm:(a,b){selectedStart=a;selectedEnd=b;}))));
    expect(selectedStart,isNull);
    expect(find.text('من: 01/10/2026'),findsOneWidget);
    expect(find.text('إلى: 03/10/2026'),findsOneWidget);
    await tester.tap(find.text('موافق'));await tester.pump();
    expect(selectedStart,DateTime(2026,10,1));expect(selectedEnd,DateTime(2026,10,3));
    final report=summarizeInvoiceMovement([
      invoice('first',10,at:movementReportBoundary(selectedStart!)),
      invoice('middle',20,at:movementReportBoundary(DateTime(2026,10,2))),
      invoice('last',30,at:movementReportBoundary(selectedEnd!,next:true).subtract(const Duration(microseconds:1))),
      invoice('outside',40,at:movementReportBoundary(DateTime(2026,10,4))),
    ],selectedStart!,selectedEnd!);
    expect(report.rows.length,3);expect(report.totalCents,6000);
    expect(tester.takeException(),isNull);
  });
  test('invoice lookup matches party names and Arabic invoice digits with voucher guard',(){
    final data={'customerName':'أحمد علي','supplierName':'الجندي للنحاسات','internalNumber':12};
    expect(invoiceMatchesEditSearch('sales','a',data,'احمد'),isTrue);
    expect(invoiceMatchesEditSearch('purchases','a',data,'الجندي'),isTrue);
    expect(invoiceMatchesEditSearch('sales','a',data,'١٢'),isTrue);
    expect(invoiceMatchesEditSearch('sales','a',data,'2'),isFalse);
    expect(invoiceHasLinkedVoucher({...data,'receiptId':'receipt'}),isTrue);
    expect(invoiceHasLinkedVoucher({...data,'receiptPaid':1}),isTrue);
    expect(invoiceHasLinkedVoucher(data),isFalse);
    invoiceSerialCache[serialKey('sales','legacy')]={'internalNumber':12};
    expect(invoiceMatchesEditSearch('sales','legacy',{'customerName':'قديم'},'12'),isTrue);
    invoiceSerialCache.remove(serialKey('sales','legacy'));
  });
  test('purchase correction reverses stock and cash directions and blocks relevant vouchers',(){
    expect(purchaseEditTotalCents([{'lineTotal':3*(10/3)}]),1000);
    expect(purchaseEditTotalCents([{'lineTotal':10.005},{'lineTotal':10.005}]),2001);
    expect(()=>purchaseEditTotalCents([{'lineTotal':double.nan}]),throwsStateError);
    expect(purchaseEditStockDelta(10,7),-3);
    expect(purchaseEditStockDelta(10,15),5);
    expect(purchaseEditCashDelta({'paid':50,'cashPosted':true},7000),-2000);
    expect(purchaseEditCashDelta({'paid':50,'cashPosted':true},3000),2000);
    expect(purchaseEditCashDelta({'paid':50,'cashPaidPosted':20},3000),-1000);
    final data={'id':'purchase1','createdAt':Timestamp.fromDate(day)};
    final voucher={'accountType':'suppliers','kind':'payment','createdAt':Timestamp.fromDate(day)};
    expect(purchaseVoucherBlocksEdit(data,{...voucher,'invoiceId':'purchase1'}),isTrue);
    expect(purchaseVoucherBlocksEdit(data,{...voucher,'invoiceId':'purchase2'}),isFalse);
    expect(purchaseVoucherBlocksEdit(data,voucher),isTrue);
    expect(purchaseVoucherBlocksEdit(data,{...voucher,'createdAt':Timestamp.fromDate(day.subtract(const Duration(days:1)))}),isFalse);
  });
  test('Cairo period includes midnight and end day but excludes next day with DST calendar boundaries',() {
    final start=movementReportBoundary(day),end=movementReportBoundary(day,next:true);
    final report=summarizeInvoiceMovement([
      invoice('before',50,at:start.subtract(const Duration(microseconds:1))),
      invoice('first',.1,paid:0,due:.1,at:start),
      invoice('last',.2,paid:0,due:.2,at:end.subtract(const Duration(microseconds:1))),
      invoice('after',50,at:end),
      {'id':'pending','total':999,'createdAt':null},
    ],day,day);
    expect(report.rows.map((r)=>r.id),['last','first']);
    expect(report.totalCents,30);expect(report.dueCents,30);
    final autumn=DateTime(2026,10,29);
    expect(movementReportBoundary(autumn,next:true).difference(movementReportBoundary(autumn)).inHours,25);
    expect(()=>summarizeInvoiceMovement([],DateTime(2026,10,5),day),throwsStateError);
  });
  test('invoice totals retain returned original invoices and subtract only returns in the selected period',() {
    final report=summarizeInvoiceMovement([
      invoice('1',100,paid:25,due:75,receipts:20),
      invoice('2',60,paid:60,due:0,status:'returned'),
    ],day,day,returns:[
      invoice('ret',60),
      invoice('old-return',10,at:movementReportBoundary(day).subtract(const Duration(days:1))),
      invoice('old-invoice-return',30),
    ]);
    expect(report.totalCents,16000);expect(report.returnCents,9000);expect(report.netCents,7000);
    expect(report.rows.firstWhere((r)=>r.id=='1').paidCents,4500);
    expect(report.rows.firstWhere((r)=>r.id=='1').dueCents,5500);
    expect(report.rows.firstWhere((r)=>r.id=='2').dueCents,0);
    final onlyReturns=summarizeInvoiceMovement([],day,day,returns:[invoice('older-invoice',80)]);
    expect(onlyReturns.netCents,-8000);
  });
  test('purchase and legacy invoice fallback preserve supplier names and paid/due values',() {
    final report=summarizeInvoiceMovement([invoice('P1',100),invoice('P2',200,due:150)],day,day,type:'purchases');
    expect(report.rows.firstWhere((r)=>r.id=='P1').customer,'مورد P1');
    expect(report.rows.firstWhere((r)=>r.id=='P1').paidCents,0);
    expect(report.rows.firstWhere((r)=>r.id=='P1').dueCents,10000);
    expect(report.rows.firstWhere((r)=>r.id=='P2').paidCents,5000);
    expect(report.rows.firstWhere((r)=>r.id=='P2').dueCents,15000);
  });
  test('invalid financial amounts and inconsistent settlements block report totals',() {
    for(final value in [-1,double.nan,double.infinity]) {
      expect(()=>summarizeInvoiceMovement([invoice('bad',value)],day,day),throwsStateError);
    }
    expect(()=>summarizeInvoiceMovement([invoice('bad',100,paid:80,due:30)],day,day),throwsStateError);
    expect(()=>summarizeInvoiceMovement([invoice('bad',100,paid:20,due:80,receipts:90)],day,day),throwsStateError);
  });
  test('debt total sums positive balances without netting credits or hiding inactive unpaid accounts',() {
    final report=summarizeDebts([
      {'id':'a','name':'تاجر واحد','balance':100.10},
      {'id':'b','name':'تاجر اثنان','balance':50.20,'active':false},
      {'id':'c','name':'رصيد دائن','balance':-120},
      {'id':'d','name':'صفر','balance':0},
    ]);
    expect(report.debtCents,15030);expect(report.creditCents,12000);
    expect(report.debtors.length,2);expect(report.debtors.any((r)=>r.inactive),true);
    expect(report.rows.length,3);
    for(final balance in [double.nan,double.infinity,'bad']) {
      expect(()=>summarizeDebts([{'name':'bad','balance':balance}]),throwsStateError);
    }
    expect(summarizeDebts([]).debtCents,0);
  });

  testWidgets('read only invoice overview shows numbered products and account on a narrow phone', (tester) async {
    tester.view.physicalSize=const Size(360,700);tester.view.devicePixelRatio=1;
    addTearDown(() {tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();});
    await tester.pumpWidget(MaterialApp(builder:(context,child)=>Directionality(textDirection:TextDirection.rtl,child:child!),
      home:Scaffold(body:InvoiceOverviewContent(type:'sales',id:'X1',data:{
        'internalNumber':42,'customerName':'عميل الاختبار','createdAt':Timestamp.fromDate(movementReportBoundary(day)),
        'total':150,'paid':50,'due':100,'items':[
          {'productName':'صنف الاختبار الأول ذو الاسم الطويل','quantity':2,'unitPrice':50,'lineTotal':100},
          {'productName':'صنف الاختبار الثاني','quantity':1,'unitPrice':50,'lineTotal':50},
        ]}))));
    await tester.pumpAndSettle();
    expect(find.text('عميل الاختبار'),findsOneWidget);
    expect(find.textContaining('1. صنف الاختبار الأول'),findsOneWidget);
    expect(find.textContaining('2. صنف الاختبار الثاني'),findsOneWidget);
    expect(find.text('باقي الفاتورة: 100.00 ج.م'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  test('generate actual short and multipage Arabic movement and debt PDFs',() async {
    final font=pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    Directory('dist').createSync(recursive:true);
    for(final type in ['sales','purchases']) {
      for(final length in [3,80]) {
        final report=summarizeInvoiceMovement(List.generate(length,(i)=>invoice('000${100+i}',120.30,paid:20.10,due:100.20)),day,day,
          type:type,returns:[invoice('000091',30)]);
        final bytes=await createInvoiceMovementReportPdf(report,font);
        expect(bytes.length,greaterThan(1000));
        File('dist/VIB-REPORT-${type.toUpperCase()}-${length==3 ? 'SHORT' : 'LONG'}.pdf').writeAsBytesSync(bytes);
      }
    }
    final debts=summarizeDebts(List.generate(65,(i)=><String,dynamic>{'id':'$i','name':'اسم تاجر عربي طويل لاختبار ظهور الاسم بالكامل رقم $i',
      'balance':i%10==0 ? -25.30 : 100.20,'active':i%8!=0}));
    for(final supplier in [false,true]) {
      final bytes=await createDebtReportPdf(debts,font,suppliers:supplier,asOf:movementReportBoundary(day));
      expect(bytes.length,greaterThan(1000));
      File('dist/VIB-REPORT-${supplier ? 'SUPPLIERS' : 'CUSTOMERS'}-DEBTS.pdf').writeAsBytesSync(bytes);
    }
  });
}




