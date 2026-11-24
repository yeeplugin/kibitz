/// Lưu cài đặt, ván đang chơi và vị trí bàn cờ trong khung hình (Hive).
library;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/coach.dart';
import '../core/i18n.dart';
import '../core/vision/board.dart';

class Store extends ChangeNotifier {
  Store._(this._box);
  final Box<dynamic> _box;

  static Future<Store> open() async {
    await Hive.initFlutter('chess_coach');
    final s = Store._(await Hive.openBox<dynamic>('store'));
    I18n.lang = s.lang;
    return s;
  }

  /// Chỉ dùng trong test: lưu trong bộ nhớ.
  @visibleForTesting
  static Store memory(Box<dynamic> box) => Store._(box);

  String get lang => _box.get('lang') as String? ?? I18n.fromDevice();
  Future<void> setLang(String v) async {
    I18n.lang = v;
    await _box.put('lang', v);
    notifyListeners();
  }

  Side get side => Side.values[_box.get('side') as int? ?? Side.white.index];
  Future<void> setSide(Side v) async {
    await _box.put('side', v.index);
    notifyListeners();
  }

  Level get level => Level.values[_box.get('level') as int? ?? Level.normal.index];
  Future<void> setLevel(Level v) async {
    await _box.put('level', v.index);
    notifyListeners();
  }

  /// Bản lưu tạm của quyền Pro; cửa hàng là nơi quyết định (xem `Billing`).
  bool get pro => (_box.get('pro') as bool? ?? false) || debugPro;

  /// Công tắc thử Pro của bản debug; để riêng vì cửa hàng ghi đè [pro] mỗi lần mở app.
  bool get debugPro => kDebugMode && (_box.get('debugPro') as bool? ?? false);
  Future<void> setDebugPro(bool v) async {
    await _box.put('debugPro', v);
    notifyListeners();
  }

  Future<void> setPro(bool v) async {
    await _box.put('pro', v);
    notifyListeners();
  }

  /// Người dùng chọn Stockfish làm engine gợi ý (chỉ có tác dụng ở bản Pro).
  bool get wantStockfish => _box.get('stockfish') as bool? ?? true;
  Future<void> setWantStockfish(bool v) async {
    await _box.put('stockfish', v);
    notifyListeners();
  }

  bool get useStockfish => pro && wantStockfish;

  /// Hiện gợi ý ngay khi tới lượt (tắt thì phải bấm nút mới hiện).
  bool get autoHint => _box.get('autoHint') as bool? ?? true;
  Future<void> setAutoHint(bool v) async {
    await _box.put('autoHint', v);
    notifyListeners();
  }

  /// Khi đang theo dõi: màn hình chính hiện bàn cờ tự vẽ (true) hay hình camera (false).
  bool get drawnBoard => _box.get('drawnBoard') as bool? ?? true;
  Future<void> setDrawnBoard(bool v) async {
    await _box.put('drawnBoard', v);
    notifyListeners();
  }

  /// Chế độ mô phỏng thay camera (mặc định bật trên máy không có camera).
  bool get simulate => _box.get('simulate') as bool? ?? false;
  Future<void> setSimulate(bool v) async {
    await _box.put('simulate', v);
    notifyListeners();
  }

  Game? get game {
    final j = _box.get('game');
    return j is Map ? Game.fromJson(j) : null;
  }

  Future<void> saveGame(Game? g) async {
    if (g == null) {
      await _box.delete('game');
    } else {
      await _box.put('game', g.toJson());
    }
    notifyListeners();
  }

  /// Ván đang đánh với máy (không dùng camera), màu quân của người chơi và màn đang chơi.
  Game? get vsGame {
    final j = _box.get('vsGame');
    return j is Map ? Game.fromJson(j) : null;
  }

  int get vsColor => _box.get('vsColor') as int? ?? 0;

  /// Các màn đã thắng máy.
  Set<int> get vsBeaten => {...(_box.get('vsBeaten') as List? ?? const []).cast<int>()};
  Future<void> markBeaten(int stage) async {
    if (vsBeaten.contains(stage)) return;
    await _box.put('vsBeaten', [...vsBeaten, stage]);
    notifyListeners();
  }

  /// Màn đang chọn; chưa chọn lần nào thì là màn đầu tiên chưa thắng.
  int get vsStage {
    final v = _box.get('vsStage') as int?;
    if (v != null) return v;
    final beaten = vsBeaten;
    return Stage.all.map((s) => s.no).firstWhere((n) => !beaten.contains(n), orElse: () => Stage.all.length);
  }

  Future<void> saveVs(Game? g, {int? color, int? stage}) async {
    if (g == null) {
      await _box.delete('vsGame');
    } else {
      await _box.put('vsGame', g.toJson());
    }
    if (color != null) await _box.put('vsColor', color);
    if (stage != null) await _box.put('vsStage', stage);
    notifyListeners();
  }

  /// Các ván đã ghi xong (ván cũ được cất vào đây khi bắt đầu ván khác), mới nhất trước.
  List<Game> get history => [
        for (final j in _box.get('history') as List? ?? const [])
          if (j is Map) Game.fromJson(j),
      ];

  Future<void> saveHistory(List<Game> games) async {
    await _box.put('history', [for (final g in games) g.toJson()]);
    notifyListeners();
  }

  /// Cất [g] vào danh sách ván đã ghi (ghi đè nếu ván đó đã có).
  Future<void> archive(Game g) => saveHistory([g, ...history.where((o) => o.startedAt != g.startedAt)]);

  /// Góc bàn cờ lần căn trước (toạ độ ảnh phân tích) và hướng bàn, theo từng nguồn hình.
  (BoardGrid, int)? calibration(String source) {
    final v = _box.get('grid_$source');
    if (v is! List || v.length != 8) return null;
    return (BoardGrid.fromList(v), _box.get('rot_$source') as int? ?? 0);
  }

  Future<void> saveCalibration(String source, BoardGrid g, int rot) async {
    await _box.put('grid_$source', g.toList());
    await _box.put('rot_$source', rot);
  }
}
