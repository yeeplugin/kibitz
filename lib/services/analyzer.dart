/// Một chỗ gọi engine cho cả màn camera và màn đánh với máy: Stockfish ở bản Pro, không thì engine có sẵn.
library;

import 'dart:isolate';
import 'dart:math' as math;

import '../core/chess/engine.dart';
import '../core/chess/position.dart';
import '../core/coach.dart';
import '../data/store.dart';
import 'stockfish_service.dart';

// Hàm top-level để gửi được sang isolate (closure trong State sẽ kéo theo cả State).
Future<Analysis> _builtin(String fen, List<String> moves, int ms, int depth) => Isolate.run(() => analyzeSync(fen, moves, ms: ms, maxDepth: depth));

/// Phân tích thế cờ theo mức nghĩ đang chọn trong Cài đặt. Trả về kết quả và `true` nếu do Stockfish tính.
/// Stockfish trục trặc thì dùng engine có sẵn để ván cờ không bị đứng.
Future<(Analysis, bool)> analyzePosition(Store store, String fen, List<String> moves) async {
  final level = store.level;
  if (store.useStockfish) {
    try {
      return (await StockfishService.instance.analyze(fen, moves, ms: level.ms, maxDepth: level.depth), true);
    } catch (_) {}
  }
  return (await _builtin(fen, moves, level.ms, level.depth), false);
}

/// Nước đi của máy (UCI) ở màn [stage]. Màn thấp: engine có sẵn tính rất nông, có lúc đi bừa để người mới có cơ hội
/// thắng. Màn cuối đánh hết sức: Stockfish ở bản Pro, không thì engine có sẵn nghĩ lâu.
Future<String> stageMove(Store store, String fen, List<String> moves, Stage stage) async {
  if (stage.full) {
    // Màn Stockfish luôn dùng Stockfish, kể cả khi Cài đặt đang chọn engine có sẵn cho phần gợi ý.
    if (stage.stockfish ? store.pro : store.useStockfish) {
      try {
        return (await StockfishService.instance.analyze(fen, moves, ms: stage.ms, maxDepth: 64)).best;
      } catch (_) {}
    }
    return (await _builtin(fen, moves, stage.ms, 64)).best;
  }
  final random = stage.random, depth = stage.depth, ms = stage.ms;
  return Isolate.run(() {
    final p = Position.fromFen(fen);
    for (final u in moves) {
      final m = p.parseUci(u);
      if (m == null) break;
      p.make(m);
    }
    final legal = p.legalMoves();
    if (legal.isEmpty) return '';
    final rnd = math.Random();
    if (rnd.nextDouble() < random) return uci(legal[rnd.nextInt(legal.length)]);
    final r = Engine().search(p, ms: ms, maxDepth: depth);
    return r.move == 0 ? uci(legal.first) : uci(r.move);
  });
}
