/// Stockfish (bản Pro): nói chuyện với engine qua giao thức UCI và trả kết quả cùng dạng với engine tự viết.
///
/// Gói `stockfish` chỉ cho chạy một engine trong cả app, và engine chỉ tính một thế cờ mỗi lúc: các yêu cầu xếp
/// hàng, yêu cầu cũ đang tính thì bị dừng.
library;

import 'dart:async';

import 'package:stockfish/stockfish.dart';

import '../core/chess/engine.dart';
import '../core/chess/position.dart';

class StockfishService {
  StockfishService._();
  static final instance = StockfishService._();

  Stockfish? _sf;
  StreamSubscription<String>? _sub;
  Future<void>? _ready;
  Future<void> _queue = Future.value();

  /// Việc đang chờ dòng trả lời của engine.
  void Function(String line)? _onLine;

  Future<void> _start() async {
    final sf = await stockfishAsync();
    _sf = sf;
    _sub = sf.stdout.listen((chunk) {
      for (final line in chunk.split('\n')) {
        final l = line.trim();
        if (l.isNotEmpty) _onLine?.call(l);
      }
    });
    if (sf.state.value != StockfishState.ready) {
      final c = Completer<void>();
      void check() {
        final s = sf.state.value;
        if (c.isCompleted) return;
        if (s == StockfishState.ready) c.complete();
        if (s == StockfishState.error || s == StockfishState.disposed) c.completeError(StateError('Stockfish không khởi động được'));
      }

      sf.state.addListener(check);
      check();
      try {
        await c.future.timeout(const Duration(seconds: 15));
      } finally {
        sf.state.removeListener(check);
      }
    }
    final ok = Completer<void>();
    _onLine = (l) {
      if (l == 'readyok' && !ok.isCompleted) ok.complete();
    };
    sf.stdin = 'setoption name Threads value 2';
    sf.stdin = 'setoption name Hash value 64';
    sf.stdin = 'isready';
    await ok.future.timeout(const Duration(seconds: 15));
    _onLine = null;
  }

  Future<void> _ensure() {
    return _ready ??= _start().catchError((Object e) {
      dispose();
      throw e;
    });
  }

  /// Phân tích thế cờ sau chuỗi nước [moves] (UCI) từ [fen] trong [ms] mili giây (và không sâu quá [maxDepth]).
  Future<Analysis> analyze(String fen, List<String> moves, {int ms = 1000, int maxDepth = 64}) {
    // Yêu cầu mới tới: bảo engine dừng việc đang tính để khỏi chờ hết thời gian của nó.
    if (_onLine != null) _sf?.stdin = 'stop';
    final done = Completer<Analysis>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await _run(fen, moves, ms, maxDepth));
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  Future<Analysis> _run(String fen, List<String> moves, int ms, int maxDepth) async {
    await _ensure();
    final sf = _sf!;
    final p = Position.fromFen(fen);
    for (final u in moves) {
      final m = p.parseUci(u);
      if (m == null) break;
      p.make(m);
    }
    final sign = p.side == white ? 1 : -1;
    var score = 0, depth = 0;
    int? mate;
    var pv = const <String>[];
    final done = Completer<Analysis>();
    _onLine = (l) {
      if (l.startsWith('info ') && l.contains(' score ') && !l.contains('bound')) {
        final t = l.split(' ');
        int? after(String k) {
          final i = t.indexOf(k);
          return i >= 0 && i + 1 < t.length ? int.tryParse(t[i + 1]) : null;
        }

        // Chỉ lấy biến chính (multipv 1).
        if ((after('multipv') ?? 1) != 1) return;
        final cp = after('cp'), mt = after('mate');
        if (cp == null && mt == null) return;
        depth = after('depth') ?? depth;
        mate = mt == null ? null : mt * sign;
        score = mt != null ? (mt > 0 ? 30000 : -30000) * sign : cp! * sign;
        final i = t.indexOf('pv');
        if (i >= 0) pv = t.sublist(i + 1);
      } else if (l.startsWith('bestmove')) {
        final t = l.split(' ');
        final best = t.length > 1 && t[1] != '(none)' ? t[1] : '';
        if (!done.isCompleted) done.complete(Analysis(best, score, mate, depth, pv));
      }
    };
    sf.stdin = 'position fen $fen${moves.isEmpty ? '' : ' moves ${moves.join(' ')}'}';
    sf.stdin = 'go movetime $ms${maxDepth < 64 ? ' depth $maxDepth' : ''}';
    try {
      return await done.future.timeout(Duration(milliseconds: ms + 8000));
    } on TimeoutException {
      // Engine treo: bỏ đi, lần sau khởi động lại.
      dispose();
      rethrow;
    } finally {
      _onLine = null;
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    try {
      _sf?.dispose();
    } catch (_) {}
    _sf = null;
    _ready = null;
    _onLine = null;
  }
}
