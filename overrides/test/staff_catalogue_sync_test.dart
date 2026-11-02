import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('newly active product is detected by ID even if the stock quantity is zero', () {
    const cached = {'p-old':'خلاط'};
    const fromServer = {
      'p-old':'خلاط',
      'p-spring-1':'سوستة استيل 1.1/4',
      'p-spring-2':'سوستة استيل 1.5',
    };
    final change=compareActiveVibCatalogues(cached,fromServer);
    expect(change.newlyAvailable,['سوستة استيل 1.1/4','سوستة استيل 1.5']);
    expect(change.noLongerActive,isEmpty);
  });

  test('removed or deactivated catalogue IDs are reported without modifying records', () {
    const cached={'a':'منتج قديم','b':'منتج آخر'};
    const latest={'b':'منتج آخر'};
    final change=compareActiveVibCatalogues(cached,latest);
    expect(change.newlyAvailable,isEmpty);
    expect(change.noLongerActive,['منتج قديم']);
    expect(cached.length,2);
    expect(latest.length,1);
  });

  test('distinct product IDs with the same name are not silently merged', () {
    const before={'id-1':'سوستة'};
    const after={'id-1':'سوستة','id-2':'سوستة'};
    final change=compareActiveVibCatalogues(before,after);
    expect(change.newlyAvailable,['سوستة']);
  });

  test('up to date staff catalogue needs no sync differences', () {
    const products={'p1':'مسمار','p2':'خرطوم'};
    final change=compareActiveVibCatalogues(products,products);
    expect(change.newlyAvailable,isEmpty);
    expect(change.noLongerActive,isEmpty);
  });
}
