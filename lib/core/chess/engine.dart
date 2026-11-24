/// Engine cờ vua nhỏ: alpha-beta lặp sâu dần, tìm kiếm tĩnh, bảng chuyển vị, nước sát thủ.
/// Đủ để gợi ý nước đi cho người chơi phổ thông; chạy trong isolate qua [analyze].
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'position.dart';

const mateScore = 100000;
const _inf = 1 << 30;
const _value = [0, 100, 320, 330, 500, 900, 0];

// Bảng điểm vị trí (Simplified Evaluation Function), viết từ hàng 8 xuống hàng 1 theo góc nhìn bên trắng.
const _pst = <List<int>>[
  [],
  [
    0, 0, 0, 0, 0, 0, 0, 0, 50, 50, 50, 50, 50, 50, 50, 50, 10, 10, 20, 30, 30, 20, 10, 10, 5, 5, 10, 25, 25, 10, 5, 5, //
    0, 0, 0, 20, 20, 0, 0, 0, 5, -5, -10, 0, 0, -10, -5, 5, 5, 10, 10, -20, -20, 10, 10, 5, 0, 0, 0, 0, 0, 0, 0, 0,
  ],
  [
    -50, -40, -30, -30, -30, -30, -40, -50, -40, -20, 0, 0, 0, 0, -20, -40, -30, 0, 10, 15, 15, 10, 0, -30, -30, 5, 15, 20, 20, 15, 5, -30, //
    -30, 0, 15, 20, 20, 15, 0, -30, -30, 5, 10, 15, 15, 10, 5, -30, -40, -20, 0, 5, 5, 0, -20, -40, -50, -40, -30, -30, -30, -30, -40, -50,
  ],
  [
    -20, -10, -10, -10, -10, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 10, 10, 5, 0, -10, -10, 5, 5, 10, 10, 5, 5, -10, //
    -10, 0, 10, 10, 10, 10, 0, -10, -10, 10, 10, 10, 10, 10, 10, -10, -10, 5, 0, 0, 0, 0, 5, -10, -20, -10, -10, -10, -10, -10, -10, -20,
  ],
  [
    0, 0, 0, 0, 0, 0, 0, 0, 5, 10, 10, 10, 10, 10, 10, 5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, //
    -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, 0, 0, 0, 5, 5, 0, 0, 0,
  ],
  [
    -20, -10, -10, -5, -5, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 5, 5, 5, 0, -10, -5, 0, 5, 5, 5, 5, 0, -5, //
    0, 0, 5, 5, 5, 5, 0, -5, -10, 5, 5, 5, 5, 5, 0, -10, -10, 0, 5, 0, 0, 0, 0, -10, -20, -10, -10, -5, -5, -10, -10, -20,
  ],
  [
    -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, //
    -20, -30, -30, -40, -40, -30, -30, -20, -10, -20, -20, -20, -20, -20, -20, -10, 20, 20, 0, 0, 0, 0, 20, 20, 20, 30, 10, 0, 0, 10, 30, 20,
  ],
];
const _kingEnd = [
  -50, -40, -30, -20, -20, -30, -40, -50, -30, -20, -10, 0, 0, -10, -20, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -10, 30, 40, 40, 30, -10, -30, //
  -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -30, 0, 0, 0, 0, -30, -30, -50, -30, -30, -30, -30, -30, -30, -50,
];

/// Điểm thế cờ theo góc nhìn bên đang đi (centipawn).
int evaluate(Position p) {
  var mg = 0, phase = 0;
  final b = p.board;
  var wk = 0, bk = 0;
  for (var s = 0; s < 64; s++) {
    final q = b[s];
    if (q == 0) continue;
    final t = typeOf(q), c = colorOf(q);
    final idx = c == white ? (7 - rankOf(s)) * 8 + fileOf(s) : s;
    if (t == king) {
      if (c == white) {
        wk = idx;
      } else {
        bk = idx;
      }
      continue;
    }
    if (t == knight || t == bishop) phase += 1;
    if (t == rook) phase += 2;
    if (t == queen) phase += 4;
    final v = _value[t] + _pst[t][idx];
    mg += c == white ? v : -v;
  }
  // Trộn bảng vua giữa ván và tàn cuộc theo lượng quân còn lại.
  final ph = phase > 24 ? 24 : phase;
  final kw = (_pst[king][wk] * ph + _kingEnd[wk] * (24 - ph)) ~/ 24;
  final kb = (_pst[king][bk] * ph + _kingEnd[bk] * (24 - ph)) ~/ 24;
  final score = mg + kw - kb;
  return p.side == white ? score : -score;
}

class SearchResult {
  SearchResult(this.move, this.score, this.depth, this.pv, this.nodes);
  final int move;

  /// Điểm theo góc nhìn bên đang đi; |score| > mateScore - 1000 là chiếu hết.
  final int score;
  final int depth;
  final List<int> pv;
  final int nodes;

  int? get mateIn => score.abs() > mateScore - 1000 ? ((mateScore - score.abs() + 1) ~/ 2) * score.sign : null;
}

class _Timeout implements Exception {}

class Engine {
  Engine({int ttBits = 18})
      : _ttSize = 1 << ttBits,
        _ttKey = List<int>.filled(1 << ttBits, 0),
        _ttMove = Int32List(1 << ttBits),
        _ttScore = Int32List(1 << ttBits),
        _ttDepth = Int8List(1 << ttBits),
        _ttFlag = Int8List(1 << ttBits);

  final int _ttSize;
  final List<int> _ttKey;
  final Int32List _ttMove, _ttScore;
  final Int8List _ttDepth, _ttFlag;
  final _killers = List.generate(128, (_) => [0, 0]);
  final _hist = Int32List(64 * 64);
  int _nodes = 0;
  late Stopwatch _clock;
  late int _limitMs;

  /// Tìm nước tốt nhất trong [ms] mili giây hoặc tới độ sâu [maxDepth].
  SearchResult search(Position p, {int ms = 1000, int maxDepth = 64}) {
    _clock = Stopwatch()..start();
    _limitMs = ms;
    _nodes = 0;
    final moves = p.legalMoves();
    if (moves.isEmpty) return SearchResult(0, p.inCheck ? -mateScore : 0, 0, const [], 0);
    var best = SearchResult(moves.first, 0, 0, [moves.first], 0);
    for (var d = 1; d <= maxDepth; d++) {
      try {
        final s = _negamax(p, d, -_inf, _inf, 0, true);
        final pv = _pv(p, d);
        if (pv.isNotEmpty) best = SearchResult(pv.first, s, d, pv, _nodes);
        if (s.abs() > mateScore - 1000 && d > 2) break;
      } on _Timeout {
        break;
      }
      if (_clock.elapsedMilliseconds * 3 > _limitMs) break;
    }
    return best;
  }

  List<int> _pv(Position p, int d) {
    final pv = <int>[];
    var made = 0;
    for (var i = 0; i < d; i++) {
      final k = p.hash & (_ttSize - 1);
      if (_ttKey[k] != p.hash) break;
      final m = _ttMove[k];
      if (m == 0 || !p.legalMoves().contains(m)) break;
      pv.add(m);
      p.make(m);
      made++;
    }
    for (var i = 0; i < made; i++) {
      p.unmake();
    }
    return pv;
  }

  int _negamax(Position p, int depth, int alpha, int beta, int ply, bool root) {
    if ((++_nodes & 2047) == 0 && _clock.elapsedMilliseconds > _limitMs) throw _Timeout();
    if (!root && (p.half >= 100 || p.repetitions() >= 1)) return 0;
    final check = p.inCheck;
    if (check) depth++;
    if (depth <= 0) return _quiesce(p, alpha, beta, ply);
    final k = p.hash & (_ttSize - 1);
    var ttMove = 0;
    if (_ttKey[k] == p.hash) {
      ttMove = _ttMove[k];
      if (!root && _ttDepth[k] >= depth) {
        final s = _ttScore[k], f = _ttFlag[k];
        if (f == 0 || (f == 1 && s >= beta) || (f == 2 && s <= alpha)) return s;
      }
    }
    final moves = p.pseudoMoves();
    _order(p, moves, ttMove, ply);
    final a0 = alpha;
    var best = -_inf, bestMove = 0, legal = 0;
    for (final m in moves) {
      if (!p.make(m)) continue;
      legal++;
      int s;
      if (legal == 1) {
        s = -_negamax(p, depth - 1, -beta, -alpha, ply + 1, false);
      } else {
        // Tìm kiếm cửa sổ hẹp cho các nước sau nước đầu.
        s = -_negamax(p, depth - 1, -alpha - 1, -alpha, ply + 1, false);
        if (s > alpha && s < beta) s = -_negamax(p, depth - 1, -beta, -alpha, ply + 1, false);
      }
      p.unmake();
      if (s > best) {
        best = s;
        bestMove = m;
      }
      if (s > alpha) alpha = s;
      if (alpha >= beta) {
        if (mFlags(m) & fCapture == 0) {
          final kl = _killers[ply.clamp(0, 127)];
          if (kl[0] != m) {
            kl[1] = kl[0];
            kl[0] = m;
          }
          _hist[mFrom(m) * 64 + mTo(m)] += depth * depth;
        }
        break;
      }
    }
    if (legal == 0) return check ? -mateScore + ply : 0;
    _ttKey[k] = p.hash;
    _ttMove[k] = bestMove;
    _ttScore[k] = best;
    _ttDepth[k] = depth.clamp(0, 127);
    _ttFlag[k] = best <= a0 ? 2 : (best >= beta ? 1 : 0);
    return best;
  }

  int _quiesce(Position p, int alpha, int beta, int ply) {
    if ((++_nodes & 2047) == 0 && _clock.elapsedMilliseconds > _limitMs) throw _Timeout();
    final stand = evaluate(p);
    if (stand >= beta) return stand;
    if (stand > alpha) alpha = stand;
    final moves = p.pseudoMoves(capturesOnly: true);
    _order(p, moves, 0, 127);
    for (final m in moves) {
      if (!p.make(m)) continue;
      final s = -_quiesce(p, -beta, -alpha, ply + 1);
      p.unmake();
      if (s >= beta) return s;
      if (s > alpha) alpha = s;
    }
    return alpha;
  }

  void _order(Position p, List<int> moves, int ttMove, int ply) {
    final kl = _killers[ply.clamp(0, 127)];
    final keys = <int, int>{};
    for (final m in moves) {
      int key;
      if (m == ttMove) {
        key = 1 << 28;
      } else if (mFlags(m) & fCapture != 0 || mPromo(m) != 0) {
        final victim = mFlags(m) & fEp != 0 ? pawn : typeOf(p.board[mTo(m)]);
        key = (1 << 26) + _value[victim] * 10 - _value[typeOf(p.board[mFrom(m)])] ~/ 10 + _value[mPromo(m)] * 10;
      } else if (m == kl[0]) {
        key = 1 << 25;
      } else if (m == kl[1]) {
        key = (1 << 25) - 1;
      } else {
        key = _hist[mFrom(m) * 64 + mTo(m)].clamp(0, (1 << 24));
      }
      keys[m] = key;
    }
    moves.sort((a, b) => keys[b]!.compareTo(keys[a]!));
  }
}

/// Thông tin trả về từ isolate: nước tốt nhất (UCI), điểm theo góc nhìn bên trắng, chuỗi nước dự kiến.
class Analysis {
  Analysis(this.best, this.whiteScore, this.mateIn, this.depth, this.pv);
  final String best;
  final int whiteScore;

  /// Chiếu hết sau bao nhiêu nước, theo góc nhìn bên trắng (âm = đen chiếu hết).
  final int? mateIn;
  final int depth;
  final List<String> pv;
}

/// Phân tích thế cờ sau chuỗi nước [moves] (UCI) từ [fen], trong isolate riêng.
Future<Analysis> analyze(String fen, List<String> moves, {int ms = 1000}) => Isolate.run(() => analyzeSync(fen, moves, ms: ms));

Analysis analyzeSync(String fen, List<String> moves, {int ms = 1000, int maxDepth = 64}) {
  final p = Position.fromFen(fen);
  for (final u in moves) {
    final m = p.parseUci(u);
    if (m == null) break;
    p.make(m);
  }
  final r = Engine().search(p, ms: ms, maxDepth: maxDepth);
  final sign = p.side == white ? 1 : -1;
  final mate = r.mateIn;
  return Analysis(r.move == 0 ? '' : uci(r.move), r.score * sign, mate == null ? null : mate * sign, r.depth, r.pv.map(uci).toList());
}
