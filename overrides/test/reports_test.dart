import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeChequeTimeZones);
  final day=DateTime(2026,10,4);
  Map<String,dynamic> invoice(String id,num total,{num? paid,num? due,num receipts=0,String status='completed',DateTime? at}) => {
    'id':id,'displayNumber':id,'customerName':'عميل $id','supplierName':'مورد $id',
    'total':total,if(paid!=null)'paid':paid,if(due!=null)'due':due,'receiptPaid':receipts,
    'status':status,'createdAt':Timestamp.fromDate(at ?? movementReportBoundary(day)),
  };
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

