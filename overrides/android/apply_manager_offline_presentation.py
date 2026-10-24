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
# Keep an accurate but minimal offline indicator. The sales heading itself
# may be shortened by UI updates; do not depend on that heading's literal text.
sales_list_anchor = "      Expanded(child: rows.isEmpty ? const Center(child: Text('لا توجد فواتير في هذا التاريخ'))"
source = replace_once(source, sales_list_anchor,
    """      if(snap.data!.metadata.isFromCache || snap.data!.metadata.hasPendingWrites)
        const Padding(padding:EdgeInsets.only(bottom:2),
          child:Text('بيانات محلية • المزامنة عند الاتصال',
            style:TextStyle(color:Colors.orangeAccent,fontSize:11),textAlign:TextAlign.center)),
""" + sales_list_anchor)
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
