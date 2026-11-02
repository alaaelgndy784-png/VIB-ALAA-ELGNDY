part of 'main.dart';

// Shared compact product picker for stock movement and invoice item reports.
// This UI is read-only and does not modify products, invoices or inventory.
typedef VibMovementProductChoice = ({String id, String name, String code});

List<VibMovementProductChoice> vibFilterMovementProductChoices(
    List<VibMovementProductChoice> products, String query) {
  final search = invoiceSearchText(query);
  final matches = products.where((product) {
    if (search.isEmpty) return true;
    return invoiceSearchText(product.name).contains(search) ||
        invoiceSearchText(product.code).contains(search) ||
        invoiceSearchText(product.id).contains(search);
  }).toList();
  matches.sort((a, b) {
    final aName = invoiceSearchText(a.name), bName = invoiceSearchText(b.name);
    if (search.isNotEmpty) {
      final aPrefix = aName.startsWith(search);
      final bPrefix = bName.startsWith(search);
      if (aPrefix != bPrefix) return aPrefix ? -1 : 1;
    }
    return aName.compareTo(bName);
  });
  return matches;
}

Future<String?> showVibMovementProductPicker(
    BuildContext context, List<VibMovementProductChoice> products) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF191C24),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheet) {
      final screen = MediaQuery.sizeOf(sheet).height;
      final keyboard = MediaQuery.viewInsetsOf(sheet).bottom;
      final available = screen - keyboard - MediaQuery.paddingOf(sheet).top - 22;
      final sheetHeight = available > 550 ? 550.0 : (available < 190 ? 190.0 : available);
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          height: sheetHeight,
          child: _VibMovementProductPickerList(products: products),
        ),
      );
    },
  );
}

class _VibMovementProductPickerList extends StatefulWidget {
  final List<VibMovementProductChoice> products;
  const _VibMovementProductPickerList({required this.products});

  @override
  State<_VibMovementProductPickerList> createState() =>
      _VibMovementProductPickerListState();
}

class _VibMovementProductPickerListState
    extends State<_VibMovementProductPickerList> {
  final searchController = TextEditingController();
  String query = '';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = vibFilterMovementProductChoices(widget.products, query);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: Row(children: [
            const Icon(Icons.inventory_2_outlined, size: 20, color: gold),
            const SizedBox(width: 8),
            const Expanded(child: Text('اختيار الصنف',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(
              tooltip: 'إغلاق القائمة',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 20)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: TextField(
            controller: searchController,
            autofocus: false,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'ابحث باسم الصنف أو الكود',
              prefixIcon: const Icon(Icons.search, size: 20, color: gold),
              suffixIcon: query.isEmpty ? null : IconButton(
                tooltip: 'مسح البحث',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  searchController.clear();
                  setState(() => query = '');
                },
              ),
              filled: true,
              fillColor: const Color(0xFF282D39),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: Colors.white24)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: Colors.white24)),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 7),
          child: Text('النتائج: ${matches.length} صنف',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        const Divider(height: 1, color: Colors.white24),
        Expanded(child: matches.isEmpty
          ? const Center(child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('مفيش صنف بالاسم أو الكود ده',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70)),
            ))
          : ListView.separated(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: matches.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1, indent: 54, endIndent: 16, color: Colors.white12),
              itemBuilder: (context, index) {
                final product = matches[index];
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 1),
                  leading: const Icon(Icons.inventory_2_outlined,
                    size: 19, color: gold),
                  title: Text(product.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 14,
                      fontWeight: FontWeight.w500, height: 1.25)),
                  subtitle: Text('كود: ${product.code.isEmpty ? product.id : product.code}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  trailing: const Icon(Icons.chevron_left,
                    size: 19, color: gold),
                  onTap: () => Navigator.pop(context, product.id),
                );
              },
            )),
      ]),
    );
  }
}
