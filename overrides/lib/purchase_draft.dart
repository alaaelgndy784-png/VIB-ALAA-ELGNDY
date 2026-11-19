import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only draft. Server-side stock, supplier, and cash updates stay atomic.
class PurchaseDraftStore {
  PurchaseDraftStore(this._prefs, {required String userId, required bool owner})
    : key = 'vib.purchase.draft.v1.' + (owner ? 'manager.' : 'staff.') + userId;

  final SharedPreferences _prefs;
  final String key;

  Map<String, dynamic>? read() {
    final saved = _prefs.getString(key);
    if (saved == null) return null;
    try {
      final data = jsonDecode(saved);
      if (data is! Map<String, dynamic> ||
          data['version'] != 1 || data['kind'] != 'purchase' ||
          data['id'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(data['id'] as String) ||
          data['items'] is! List || (data['items'] as List).length > 50) return null;
      return data;
    } catch (_) { return null; }
  }

  static bool hasInput(Map<String, dynamic> data) {
    final items = data['items'];
    if (items is List && items.isNotEmpty) return true;
    for (final key in ['supplierId', 'invoice', 'note', 'markup']) {
      if ((data[key] ?? '').toString().trim().isNotEmpty) return true;
    }
    return false;
  }

  Future<void> persist(String value) async {
    if (!await _prefs.setString(key, value)) throw StateError('Local draft write failed');
  }

  Future<void> clear() async {
    if (!await _prefs.remove(key)) throw StateError('Local draft clear failed');
  }
}

/// Serializes writes so an in-flight autosave cannot recreate a cleared draft.
class PurchaseDraftAutosave {
  PurchaseDraftAutosave(this.store);
  final PurchaseDraftStore store;
  Timer? _timer;
  Future<void> _pending = Future<void>.value();
  String? _lastValue;
  bool _stopped = false;

  void start(Map<String, dynamic> Function() snapshot) {
    _timer ??= Timer.periodic(const Duration(milliseconds: 750), (_) {
      if (_stopped) return;
      final data = snapshot();
      if (PurchaseDraftStore.hasInput(data)) {
        unawaited(save(data).catchError((Object _) {}));
      }
    });
  }

  Future<void> save(Map<String, dynamic> data) {
    if (_stopped) return Future<void>.value();
    final encoded = jsonEncode(data);
    if (encoded == _lastValue) return _pending;
    _lastValue = encoded;
    _pending = _pending.catchError((Object _) {}).then((_) async {
      try { await store.persist(encoded); }
      catch (_) { if (_lastValue == encoded) _lastValue = null; rethrow; }
    });
    return _pending;
  }

  Future<void> stop({required bool clear}) async {
    _timer?.cancel();
    _stopped = true;
    await _pending.catchError((Object _) {});
    if (clear) await store.clear();
  }
}
