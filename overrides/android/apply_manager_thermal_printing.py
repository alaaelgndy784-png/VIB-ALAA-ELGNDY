#!/usr/bin/env python3
"""Add direct 80 mm Bluetooth printing to manager customer vouchers/statements."""

from pathlib import Path
import sys


target = Path(sys.argv[1])
source = target.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"Expected one {label} target, found {count}")
    source = source.replace(old, new, 1)


replace_once(
    """                IconButton(visualDensity:VisualDensity.compact,tooltip:'طباعة / حفظ PDF',icon:const Icon(Icons.picture_as_pdf,size:21),
                  onPressed:()=>printReceiptVoucher(context,row.id,data)),
                if(owner) IconButton(visualDensity:VisualDensity.compact,tooltip:'إلغاء سند القبض وعكس أثره المحاسبي',icon:const Icon(Icons.undo,color:Colors.redAccent,size:21),
                  onPressed:()=>cancelReceiptVoucher(context,row.id,data)),""",
    """                IconButton(visualDensity:VisualDensity.compact,tooltip:'طباعة / حفظ PDF',icon:const Icon(Icons.picture_as_pdf,size:21),
                  onPressed:()=>printReceiptVoucher(context,row.id,data)),
                IconButton(visualDensity:VisualDensity.compact,tooltip:'طباعة سند القبض على طابعة 80 مم',icon:const Icon(Icons.print,size:21),
                  onPressed:()=>printReceiptVoucher(context,row.id,data,thermal:true)),
                if(owner) IconButton(visualDensity:VisualDensity.compact,tooltip:'إلغاء سند القبض وعكس أثره المحاسبي',icon:const Icon(Icons.undo,color:Colors.redAccent,size:21),
                  onPressed:()=>cancelReceiptVoucher(context,row.id,data)),""",
    "customer receipt voucher buttons",
)

replace_once(
    """Future<void> printReceiptVoucher(BuildContext context, String id, Map<String, dynamic> data) async {
  try {
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final bytes=await createReceiptVoucherPdf(id,data,font);
    await Printing.layoutPdf(name: 'VIB-RECEIPT-$id.pdf', onLayout: (_) async => bytes);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر طباعة سند القبض: $e')));
  }
}""",
    """Future<void> printReceiptVoucher(BuildContext context, String id, Map<String, dynamic> data, {bool thermal=false}) async {
  try {
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final bytes=await createReceiptVoucherPdf(id,data,font,thermal:thermal);
    if(thermal) {
      final prefs=await SharedPreferences.getInstance();
      await _printPdfOnBluetoothThermal(context,bytes,printerMac:prefs.getString(_thermalPrinterMacKey));
    } else {
      await Printing.layoutPdf(name: 'VIB-RECEIPT-$id.pdf', onLayout: (_) async => bytes);
    }
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر طباعة سند القبض: $e')));
  }
}""",
    "customer receipt print function",
)

replace_once(
    "Future<Uint8List> createReceiptVoucherPdf(String id,Map<String,dynamic> data,pw.Font font) async {",
    "Future<Uint8List> createReceiptVoucherPdf(String id,Map<String,dynamic> data,pw.Font font,{bool thermal=false}) async {",
    "customer receipt PDF signature",
)

replace_once(
    """  final number='${data['receiptNumber']??'VIB-RC-$date-${id.length>6?id.substring(0,6).toUpperCase():id.toUpperCase()}'}';
  pw.Widget detail(String label,String value,{bool strong=false})=>pw.Container(""",
    """  final number='${data['receiptNumber']??'VIB-RC-$date-${id.length>6?id.substring(0,6).toUpperCase():id.toUpperCase()}'}';
  if(thermal) {
    final valueLines=[name,'${data['customerName']??''}','${data['customerPhone']??'غير مسجل'}','${data['note']??''}']
      .where((value)=>value.trim().isNotEmpty).fold<int>(0,(sum,value)=>sum+((value.runes.length+29)~/30));
    final pageHeight=(138+valueLines*8).clamp(138,5000).toDouble();
    pw.Widget line(String label,String value,{bool strong=false})=>pw.Padding(
      padding:const pw.EdgeInsets.symmetric(vertical:2),
      child:pw.Text('$label$value',textAlign:pw.TextAlign.right,style:pw.TextStyle(
        fontSize:strong?10:8.5,fontWeight:strong?pw.FontWeight.bold:pw.FontWeight.normal)));
    pdf.addPage(pw.Page(pageFormat:PdfPageFormat(80*PdfPageFormat.mm,pageHeight*PdfPageFormat.mm,marginAll:4*PdfPageFormat.mm),
      theme:pw.ThemeData.withFont(base:font,bold:font),textDirection:pw.TextDirection.rtl,
      build:(_)=>pw.Column(mainAxisSize:pw.MainAxisSize.min,crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:[
        pw.Text(name,textAlign:pw.TextAlign.center,style:pw.TextStyle(fontSize:12,fontWeight:pw.FontWeight.bold)),
        pw.Text('سند قبض عميل',textAlign:pw.TextAlign.center,style:pw.TextStyle(fontSize:14,fontWeight:pw.FontWeight.bold)),
        pw.Divider(thickness:1),
        line('رقم السند: ',number,strong:true),line('التاريخ: ',date),
        line('العميل: ','${data['customerName']??''}',strong:true),
        line('الهاتف: ','${data['customerPhone']??'غير مسجل'}'),pw.Divider(),
        line('المبلغ المدفوع: ','${paid.toStringAsFixed(2)} ج.م',strong:true),
        line('الرصيد قبل السداد: ','${before.toStringAsFixed(2)} ج.م'),
        line('الرصيد بعد السداد: ','${after.toStringAsFixed(2)} ج.م',strong:true),
        line('طريقة الدفع: ','${data['paymentMethod']??'نقدي'}'),
        if('${data['note']??''}'.trim().isNotEmpty)line('البيان: ','${data['note']}'),
        line('المسؤول: ','${data['actorName']??''}'),pw.SizedBox(height:12),
        pw.Text('توقيع المستلم: __________________',textAlign:pw.TextAlign.right,style:const pw.TextStyle(fontSize:8)),
        pw.SizedBox(height:8),pw.Divider(),
        pw.Text('شكرًا لتعاملكم معنا',textAlign:pw.TextAlign.center,style:pw.TextStyle(fontSize:9,fontWeight:pw.FontWeight.bold)),
      ])));
    return pdf.save();
  }
  pw.Widget detail(String label,String value,{bool strong=false})=>pw.Container(""",
    "customer receipt thermal layout",
)

target.write_text(source, encoding="utf-8")
