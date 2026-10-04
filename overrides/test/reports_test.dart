import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
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
