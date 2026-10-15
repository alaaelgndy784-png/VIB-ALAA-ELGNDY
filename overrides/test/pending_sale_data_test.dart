import 'package:flutter_test/flutter_test.dart';
import '../lib/pending_sale_data.dart';

Map<String,dynamic> request(int n)=>{'customerId':'customer','credit':true,'paid':10.0,'total':n*22.23,
  'items':[for(var i=0;i<n;i++){'productId':'p$i','quantity':2,'unitPrice':11.115,'basePrice':12.35,'discountPercent':10}]};
void main() {
  test('employee offline draft round-trips without changing invoice lines or totals',() {
    final draft=OfflineEmployeeSaleData.parse({
      'id':'sale123','branchId':'branchA','customerId':'customerA','createdAt':'2026-10-14T08:00:00Z',
      'credit':true,'total':30.0,'paid':10.0,'items':[
        {'productId':'p1','productName':'حنفية','quantity':2,'unitPrice':15.0,'basePrice':18.0,'discountPercent':0}
      ],
    });
    final restored=OfflineEmployeeSaleData.parse(draft.toJson());
    expect(restored.id,'sale123');expect(restored.branchId,'branchA');
    expect(restored.total,30);expect(restored.paid,10);expect(restored.items.single['productId'],'p1');
    expect(restored.lastError,'');
  });
  test('cash employee offline draft can be saved without a registered customer',() {
    final draft=OfflineEmployeeSaleData.parse({
      'id':'sale124','branchId':'branchA','customerId':'','createdAt':'2026-10-14T08:00:00Z',
      'credit':false,'total':30.0,'paid':30.0,'items':[
        {'productId':'p1','productName':'حنفية','quantity':2,'unitPrice':15.0,'basePrice':18.0,'discountPercent':0}
      ],
    });
    expect(draft.customerId,'');expect(draft.credit,false);
  });
  test('credit employee offline draft requires a registered customer',() {
    final draft={
      'id':'sale124','branchId':'branchA','customerId':'','createdAt':'2026-10-14T08:00:00Z',
      'credit':true,'total':30.0,'paid':10.0,'items':[
        {'productId':'p1','productName':'حنفية','quantity':2,'unitPrice':15.0,'basePrice':18.0,'discountPercent':0}
      ],
    };
    expect(()=>OfflineEmployeeSaleData.parse(draft),throwsFormatException);
  });
  test('invalid employee offline draft cannot be queued',() {
    final draft={
      'id':'sale123','branchId':'branchA','customerId':'customerA','createdAt':'2026-10-14T08:00:00Z',
      'credit':false,'total':30.0,'paid':30.0,'items':[
        {'productId':'p1','productName':'حنفية','quantity':2,'unitPrice':15.0,'basePrice':18.0,'discountPercent':0},
        {'productId':'p1','productName':'حنفية ثانية','quantity':1,'unitPrice':0.0,'basePrice':0.0,'discountPercent':0},
      ],
    };
    expect(()=>OfflineEmployeeSaleData.parse(draft),throwsFormatException);
  });
  test('five and fifty item proposals recalculate totals instead of trusting supplied totals',() {
    for(final n in [5,50]) {
      final parsed=PendingSaleData.parse(request(n));
      expect(parsed.lines.length,n);expect(parsed.total,closeTo(n*22.23,0.000001));expect(parsed.paid,10);
      expect(parsed.lines.first.discount,10);expect(parsed.lines.first.basePrice,12.35);
    }
  });
  test('malformed or nonfinite proposal cannot be approved',() {
    for(final change in <void Function(Map<String,dynamic>)>[
      (d)=>d['items']=[],(d)=>d['items']=request(51)['items'],(d)=>d['customerId']='',
      (d)=>d['paid']=double.nan,(d)=>d['paid']=double.infinity,(d)=>d['paid']=-1,(d)=>d['paid']=100000,
      (d)=>d['credit']=false,(d)=>(d['items'] as List)[0]['quantity']=0,
      (d)=>(d['items'] as List)[0]['quantity']=1.5,(d)=>(d['items'] as List)[0]['quantity']=1000001,
      (d)=>(d['items'] as List)[0]['unitPrice']=double.nan,
      (d)=>(d['items'] as List)[0]['basePrice']=double.infinity,
      (d)=>(d['items'] as List)[0]['discountPercent']=101,
      (d)=>(d['items'] as List)[1]['productId']='p0',
      (d)=>(d['items'] as List)[0]['productId']='bad/path',
    ]) {final draft=request(5);change(draft);expect(()=>PendingSaleData.parse(draft),throwsFormatException);}
  });
  test('cash proposal must pay the complete calculated amount',() {
    final draft=request(5);draft['credit']=false;draft['paid']=5*22.23;
    expect(PendingSaleData.parse(draft).paid,closeTo(111.15,0.000001));
  });
  test('sale tender split adds exactly to paid and old invoices default to cash',() {
    final split=request(5)..['paymentBreakdown']={'cash':4.25,'instapay':3.50,'vodafoneCash':2.25};
    final parsed=PendingSaleData.parse(split);
    expect(parsed.paymentBreakdown['cash'],4.25);
    expect(parsed.paymentBreakdown['instapay'],3.50);
    expect(parsed.paymentBreakdown['vodafoneCash'],2.25);
    final legacy=request(5);
    expect(PendingSaleData.parse(legacy).paymentBreakdown['cash'],10);
    for(final bad in [
      {'cash':4.0,'instapay':3.5,'vodafoneCash':2.0},
      {'cash':-1.0,'instapay':6.0,'vodafoneCash':5.0},
      {'cash':4.0,'instapay':3.0,'vodafoneCash':2.0,'unknown':1.0},
    ]) {
      final invalid=request(5)..['paymentBreakdown']=bad;
      expect(()=>PendingSaleData.parse(invalid),throwsFormatException);
    }
  });
  test('invoice correction preserves tender history and treats payment changes as cash',() {
    final increased=adjustSalePaymentBreakdown({'cash':4,'instapay':3,'vodafoneCash':3},10,12);
    expect(increased,{'cash':6.0,'instapay':3.0,'vodafoneCash':3.0});
    final reduced=adjustSalePaymentBreakdown({'cash':4,'instapay':3,'vodafoneCash':3},10,5);
    expect(reduced,{'cash':0.0,'instapay':2.0,'vodafoneCash':3.0});
  });
  test('manager repricing recalculates totals and preserves the original quote',() {
    final draft=request(5);
    final edited=repricePendingSale(draft,List<double>.filled(5,20));
    expect(edited['total'],closeTo(200,0.000001));expect(edited['paid'],10);
    expect(edited['managerPriceAdjusted'],true);expect(edited['managerOriginalTotal'],closeTo(111.15,0.000001));
    expect((edited['managerOriginalItems'] as List).first['unitPrice'],11.115);
    final cash=request(5)..['credit']=false..['paid']=111.15;
    final cashEdited=repricePendingSale(cash,List<double>.filled(5,20));
    expect(cashEdited['total'],closeTo(200,0.000001));expect(cashEdited['paid'],closeTo(200,0.000001));
    expect(()=>repricePendingSale(request(5),[1]),throwsFormatException);
    final mismatch=request(5)..['total']=999;
    expect(PendingSaleData.parse(mismatch).total,closeTo(111.15,0.000001));
  });
  test('cash offline sale can be queued without a customer; credit sale still requires one',() {
    final draft=request(1);draft['customerId']='';draft['credit']=false;draft['paid']=22.23;
    expect(PendingSaleData.parse(draft).customerId,'');
    draft['credit']=true;
    expect(()=>PendingSaleData.parse(draft),throwsFormatException);
  });
}
