part of 'main.dart';

// Printable invoice source-of-truth for a single product. Unlike stock
// movements, all rows below are taken from saved invoice line items.
Future<Uint8List> createVibProductInvoiceReportPdf({
  required String productName,
  required String type,
  required List<VibProductInvoiceHit> hits,
  required pw.Font font,
  DateTime? from,
  DateTime? to,
  bool allDates = true,
}) async {
  if (type != 'sales' && type != 'purchases') {
    throw ArgumentError('Unsupported invoice report type');
  }
  final sales = type == 'sales';
  final rows = hits.where((h) => h.type == type).toList()
    ..sort((a, b) => (a.date?.millisecondsSinceEpoch ?? 0)
        .compareTo(b.date?.millisecondsSinceEpoch ?? 0));
  final quantity = rows.fold<double>(0, (sum, row) => sum + row.quantity);
  final total = rows.fold<double>(0, (sum, row) => sum + row.total);
  final invoiceCount = rows.map((row) => row.id).toSet().length;
  final pdf = pw.Document();
  const darkBlue = PdfColor.fromInt(0xFF16263A);
  const goldColor = PdfColor.fromInt(0xFFB28B44);
  const lightGray = PdfColor.fromInt(0xFFF1F3F6);
  final title = sales ? 'تقرير مبيعات صنف' : 'تقرير مشتريات صنف';
  final period = allDates
      ? 'من أول الفواتير المسجلة'
      : 'من ${DateFormat('dd/MM/yyyy').format(from!)} إلى ${DateFormat('dd/MM/yyyy').format(to!)}';
  pw.Widget cell(String value, {bool header = false, int maxLines = 3}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 7),
        child: pw.Text(value,
          maxLines: maxLines,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            font: font,
            color: header ? PdfColors.white : PdfColors.black,
            fontSize: header ? 10 : 10.5,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          )),
      );
  pw.Widget statistic(String label, String value) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(8),
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          decoration: pw.BoxDecoration(
            color: lightGray,
            border: pw.Border.all(color: goldColor, width: .5),
            borderRadius: pw.BorderRadius.circular(5),
          ),
          child: pw.Column(children: [
            pw.Text(label, style: pw.TextStyle(font: font, fontSize: 9)),
            pw.SizedBox(height: 3),
            pw.Text(value, textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: font, fontSize: 13,
                fontWeight: pw.FontWeight.bold)),
          ]),
        ),
      );
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    maxPages: 1000,
    margin: const pw.EdgeInsets.fromLTRB(24, 25, 24, 26),
    theme: pw.ThemeData.withFont(base: font, bold: font),
    textDirection: pw.TextDirection.rtl,
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.center,
      child: pw.Text('صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
        style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700))),
    build: (_) => [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: goldColor, width: 2))),
        child: pw.Column(children: [
          pw.Text('VIB للتجارة والتوزيع',
            style: pw.TextStyle(font: font, fontSize: 19,
              fontWeight: pw.FontWeight.bold, color: darkBlue)),
          pw.SizedBox(height: 5),
          pw.Text(title,
            style: pw.TextStyle(font: font, fontSize: 17,
              fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          pw.Text('الصنف: $productName',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: font, fontSize: 15)),
          pw.SizedBox(height: 4),
          pw.Text(period, style: pw.TextStyle(font: font, fontSize: 11)),
        ]),
      ),
      pw.SizedBox(height: 14),
      pw.Row(children: [
        statistic('عدد الفواتير', '$invoiceCount'),
        statistic('إجمالي الكمية', quantity.toStringAsFixed(0)),
        statistic('إجمالي القيمة', total.toStringAsFixed(2)),
      ]),
      pw.SizedBox(height: 14),
      if (rows.isEmpty)
        pw.Padding(padding: const pw.EdgeInsets.all(16),
          child: pw.Text('لا توجد فواتير لهذا الصنف في الفترة المختارة',
            style: pw.TextStyle(font: font, fontSize: 13)))
      else pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: .55),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.45),
          1: const pw.FlexColumnWidth(1.05),
          2: const pw.FlexColumnWidth(1.0),
          3: const pw.FlexColumnWidth(1.05),
          4: const pw.FlexColumnWidth(2.0),
          5: const pw.FlexColumnWidth(1.2),
          6: const pw.FlexColumnWidth(.35),
        },
        children: [
          pw.TableRow(
            repeat: true,
            decoration: const pw.BoxDecoration(color: darkBlue),
            children: [
              cell('الإجمالي', header: true),
              cell('سعر الوحدة', header: true),
              cell('الكمية', header: true),
              cell('رقم الفاتورة', header: true),
              cell(sales ? 'العميل' : 'المورد', header: true),
              cell('التاريخ', header: true),
              cell('م', header: true),
            ],
          ),
          for (var i = 0; i < rows.length; i++)
            pw.TableRow(
              decoration: i.isOdd ? const pw.BoxDecoration(color: lightGray) : null,
              children: [
                cell(rows[i].total.toStringAsFixed(2)),
                cell(rows[i].price.toStringAsFixed(2)),
                cell(rows[i].quantity.toStringAsFixed(0)),
                cell(rows[i].number, maxLines: 2),
                cell(rows[i].party.isEmpty ? 'غير مسجل' : rows[i].party,
                  maxLines: 3),
                cell(rows[i].date == null ? 'غير مسجل' :
                  DateFormat('dd/MM/yyyy').format(rows[i].date!)),
                cell('${i + 1}'),
              ],
            ),
        ],
      ),
      pw.SizedBox(height: 14),
      pw.Text('القيم كما سُجلت في الفواتير الأصلية؛ لا تشمل خصم المرتجعات أو الفواتير الملغاة من الإجمالي.',
        style: pw.TextStyle(font: font, fontSize: 9.5, color: PdfColors.grey700)),
    ],
  ));
  return pdf.save();
}
