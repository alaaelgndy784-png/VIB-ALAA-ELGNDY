#!/usr/bin/env python3
"""Apply the manager-only store movement entry point to the assembled app."""

from pathlib import Path
import sys


target = Path(sys.argv[1])
source = target.read_text(encoding="utf-8")
part_marker = "part 'business_reports.dart';"
menu_marker = "    option(context, 'تقرير الأرباح', Icons.bar_chart_outlined, const ProfitReport()),"
menu_insert = "    option(context, 'عرض حركة المتجر', Icons.storefront_outlined, const StoreMovementReportPage(), highlight: true),\n"

if source.count(part_marker) != 1:
    raise SystemExit("Could not find the expected business report part declaration exactly once")
if source.count(menu_marker) != 1:
    raise SystemExit("Could not find the expected manager report menu entry exactly once")
if "part 'store_movement.dart';" in source or "عرض حركة المتجر" in source:
    raise SystemExit("Store movement report is already applied")

source = source.replace(part_marker, part_marker + "\npart 'store_movement.dart';", 1)
source = source.replace(menu_marker, menu_insert + menu_marker, 1)
target.write_text(source, encoding="utf-8")
