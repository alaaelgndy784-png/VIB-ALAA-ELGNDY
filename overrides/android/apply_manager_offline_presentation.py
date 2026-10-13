#!/usr/bin/env python3
"""Keep cached manager invoice views visible and apply the requested colors."""
from pathlib import Path
import sys


def replace_once(text: str, old: str, new: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected one source block, found {count}: {old[:90]!r}")
    return text.replace(old, new, 1)


path = Path(sys.argv[1] if len(sys.argv) > 1 else "lib/main.dart")
source = path.read_text()
source = replace_once(source,
    "if (snap.hasError) return const Center(child: Text('تعذر عرض المبيعات'));",
    "if (snap.hasError && !snap.hasData) return const Center(child: Text('لا توجد مبيعات محفوظة على الجهاز. اتصل بالإنترنت لتحميلها أول مرة.'));")
summary = """      Padding(padding: const EdgeInsets.all(8), child: Text('فواتير المبيعات • من ${DateFormat('dd/MM/yyyy').format(selectedFrom)} إلى ${DateFormat('dd/MM/yyyy').format(selectedTo)} • العدد: ${rows.length} • الإجمالي: ${movementReportMoney(rows.fold<int>(0,(sum,row){final value=row.data()['total'];return value is num && value.isFinite ? sum+(value*100).round() : sum;}))}',textAlign:TextAlign.center,style:const TextStyle(color:gold,fontWeight:FontWeight.bold))),
      Expanded(child: rows.isEmpty ? const Center(child: Text('لا توجد فواتير في هذا التاريخ'))"""
source = replace_once(source, summary,
    summary.split("\n")[0] + "\n" + """      if(snap.data!.metadata.isFromCache || snap.data!.metadata.hasPendingWrites)
        const Padding(padding:EdgeInsets.only(bottom:4),child:Text('عرض من البيانات المحفوظة على الجهاز؛ تتحدث عند رجوع الإنترنت',style:TextStyle(color:Colors.orangeAccent),textAlign:TextAlign.center)),
      Expanded(child: rows.isEmpty ? const Center(child: Text('لا توجد فواتير في هذا التاريخ'))""")
source = replace_once(source,
    "Text('فرع: ${sale['branchId']} • ${formatDate(sale['createdAt'])}$paymentText${sale['status'] == 'returned' ? ' • مرتجعة بالكامل' : ((sale['partialReturnTotal'] as num?) ?? 0) > 0 ? ' • مرتجع جزئي ${sale['partialReturnTotal']} ج.م' : ''}'),",
    "Text('فرع: ${sale['branchId']} • ${formatDate(sale['createdAt'])}$paymentText${sale['status'] == 'returned' ? ' • مرتجعة بالكامل' : ((sale['partialReturnTotal'] as num?) ?? 0) > 0 ? ' • مرتجع جزئي ${sale['partialReturnTotal']} ج.م' : ''}',style:const TextStyle(color:Colors.redAccent)),")
source = replace_once(source,
    "trailing: Text('${sale['total'] ?? 0} ج.م', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),",
    "trailing: Text('${sale['total'] ?? 0} ج.م', style: const TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold)),")
source = replace_once(source,
    "if (snap.hasError) return const Center(child: Text('تعذر تحميل المشتريات'));",
    "if (snap.hasError && !snap.hasData) return const Center(child: Text('لا توجد مشتريات محفوظة على الجهاز. اتصل بالإنترنت لتحميلها أول مرة.'));")
source = replace_once(source,
    "subtitle: Text('${formatDate(p['createdAt'])}${p['status'] == 'returned' ? ' • مرتجع' : ''}'),",
    "subtitle: Text('${formatDate(p['createdAt'])}${p['status'] == 'returned' ? ' • مرتجع' : ''}',style:const TextStyle(color:Colors.redAccent)),")
source = replace_once(source,
    "trailing: Text('${p['total'] ?? 0} ج.م', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),",
    "trailing: Text('${p['total'] ?? 0} ج.م', style: const TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold)),")
path.write_text(source)
