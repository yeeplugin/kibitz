/// Luật cờ vua: thế cờ, sinh nước đi hợp lệ, đi/lùi nước, FEN, ký hiệu SAN.
/// Dart thuần (không phụ thuộc Flutter) để chạy trong isolate và unit test.
library;

import 'dart:math' as math;
import 'dart:typed_data';

// Quân: 3 bit thấp là loại quân, bit 3 là màu (0 trắng, 1 đen). 0 = ô trống.
const pawn = 1, knight = 2, bishop = 3, rook = 4, queen = 5, king = 6;
const white = 0, black = 1;

int piece(int color, int type) => color << 3 | type;
int typeOf(int p) => p & 7;
int colorOf(int p) => p >> 3;

// Ô: a1 = 0, b1 = 1, …, h8 = 63.
int sqOf(int file, int rank) => rank * 8 + file;
int fileOf(int s) => s & 7;
int rankOf(int s) => s >> 3;
String sqName(int s) => '${'abcdefgh'[s & 7]}${(s >> 3) + 1}';
int parseSq(String n) => sqOf(n.codeUnitAt(0) - 97, n.codeUnitAt(1) - 49);

// Nước đi là một số nguyên: from | to << 6 | phong cấp << 12 | cờ << 15.
const fCapture = 1, fEp = 2, fCastle = 4, fDouble = 8;
int mkMove(int from, int to, [int promo = 0, int flags = 0]) => from | to << 6 | promo << 12 | flags << 15;
int mFrom(int m) => m & 63;
int mTo(int m) => (m >> 6) & 63;
int mPromo(int m) => (m >> 12) & 7;
int mFlags(int m) => m >> 15;

/// Nước đi dạng UCI: e2e4, e7e8q.
String uci(int m) => '${sqName(mFrom(m))}${sqName(mTo(m))}${mPromo(m) == 0 ? '' : ' pnbrqk'[mPromo(m)]}';

const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

// Bảng ô đích của mã, vua và các tia đi thẳng/chéo, tính sẵn một lần.
final List<List<int>> _knightTo = List.generate(64, (s) => _steps(s, const [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]));
final List<List<int>> _kingTo = List.generate(64, (s) => _steps(s, const [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]));
const _dirs = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];
final List<List<List<int>>> _rays = List.generate(64, (s) => [
      for (final (df, dr) in _dirs)
        [
          for (var f = fileOf(s) + df, r = rankOf(s) + dr; f >= 0 && f < 8 && r >= 0 && r < 8; f += df, r += dr) sqOf(f, r),
        ],
    ]);

List<int> _steps(int s, List<(int, int)> d) => [
      for (final (df, dr) in d)
        if (fileOf(s) + df >= 0 && fileOf(s) + df < 8 && rankOf(s) + dr >= 0 && rankOf(s) + dr < 8) sqOf(fileOf(s) + df, rankOf(s) + dr),
    ];

// Quyền nhập thành: 1 = trắng cánh vua, 2 = trắng cánh hậu, 4 = đen cánh vua, 8 = đen cánh hậu.
final Uint8List _castleKeep = () {
  final k = Uint8List(64)..fillRange(0, 64, 15);
  k[0] = 15 & ~2;
  k[7] = 15 & ~1;
  k[4] = 15 & ~3;
  k[56] = 15 & ~8;
  k[63] = 15 & ~4;
  k[60] = 15 & ~12;
  return k;
}();

// Khoá Zobrist để nhận ra thế cờ lặp lại và cho bảng chuyển vị của engine.
final _zr = math.Random(20261123);
int _rnd64() => (_zr.nextInt(1 << 21) << 42) ^ (_zr.nextInt(1 << 21) << 21) ^ _zr.nextInt(1 << 21);
final List<int> _zPiece = List.generate(16 * 64, (_) => _rnd64());
final List<int> _zCastle = List.generate(16, (_) => _rnd64());
final List<int> _zEp = List.generate(8, (_) => _rnd64());
final int _zSide = _rnd64();

class _Undo {
  _Undo(this.move, this.captured, this.castle, this.ep, this.half, this.hash);
  final int move, captured, castle, ep, half, hash;
}

enum GameStatus { ongoing, checkmate, stalemate, fiftyMoves, repetition, material }

class Position {
  Position._();

  final Int8List board = Int8List(64);
  int side = white;
  int castle = 0;
  int ep = -1;
  int half = 0;
  int full = 1;
  int hash = 0;
  final List<int> kingSq = [4, 60];
  final List<_Undo> _stack = [];

  /// Khoá của các thế cờ đã qua (để phát hiện lặp ba lần).
  final List<int> history = [];

  factory Position.start() => Position.fromFen(startFen);

  factory Position.fromFen(String fen) {
    final p = Position._();
    final parts = fen.trim().split(RegExp(r'\s+'));
    var r = 7, f = 0;
    for (final ch in parts[0].split('')) {
      if (ch == '/') {
        r--;
        f = 0;
      } else if (RegExp(r'\d').hasMatch(ch)) {
        f += int.parse(ch);
      } else {
        final t = ' pnbrqk'.indexOf(ch.toLowerCase());
        if (t <= 0 || r < 0 || f > 7) throw FormatException('FEN', fen);
        p.board[sqOf(f, r)] = piece(ch == ch.toLowerCase() ? black : white, t);
        f++;
      }
    }
    p.side = parts.length > 1 && parts[1] == 'b' ? black : white;
    final c = parts.length > 2 ? parts[2] : '-';
    p.castle = (c.contains('K') ? 1 : 0) | (c.contains('Q') ? 2 : 0) | (c.contains('k') ? 4 : 0) | (c.contains('q') ? 8 : 0);
    p.ep = parts.length > 3 && parts[3] != '-' ? parseSq(parts[3]) : -1;
    p.half = parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0;
    p.full = parts.length > 5 ? int.tryParse(parts[5]) ?? 1 : 1;
    p._fixup();
    return p;
  }

  /// Thế cờ dựng từ bàn [board] (64 quân) và bên đi [side]; quyền nhập thành suy ra từ vị trí vua và xe.
  factory Position.fromBoard(List<int> board, int side) {
    final p = Position._();
    p.board.setAll(0, board);
    p.side = side;
    p.castle = (board[4] == piece(white, king) && board[7] == piece(white, rook) ? 1 : 0) |
        (board[4] == piece(white, king) && board[0] == piece(white, rook) ? 2 : 0) |
        (board[60] == piece(black, king) && board[63] == piece(black, rook) ? 4 : 0) |
        (board[60] == piece(black, king) && board[56] == piece(black, rook) ? 8 : 0);
    p._fixup();
    return p;
  }

  void _fixup() {
    for (var s = 0; s < 64; s++) {
      if (typeOf(board[s]) == king) kingSq[colorOf(board[s])] = s;
    }
    hash = computeHash();
  }

  Position copy() => Position.fromFen(fen)..history.addAll(history);

  int computeHash() {
    var h = 0;
    for (var s = 0; s < 64; s++) {
      if (board[s] != 0) h ^= _zPiece[board[s] * 64 + s];
    }
    h ^= _zCastle[castle];
    if (ep >= 0) h ^= _zEp[fileOf(ep)];
    if (side == black) h ^= _zSide;
    return h;
  }

  String get fen {
    final sb = StringBuffer();
    for (var r = 7; r >= 0; r--) {
      var gap = 0;
      for (var f = 0; f < 8; f++) {
        final p = board[sqOf(f, r)];
        if (p == 0) {
          gap++;
          continue;
        }
        if (gap > 0) sb.write(gap);
        gap = 0;
        final ch = ' pnbrqk'[typeOf(p)];
        sb.write(colorOf(p) == white ? ch.toUpperCase() : ch);
      }
      if (gap > 0) sb.write(gap);
      if (r > 0) sb.write('/');
    }
    final c = '${castle & 1 != 0 ? 'K' : ''}${castle & 2 != 0 ? 'Q' : ''}${castle & 4 != 0 ? 'k' : ''}${castle & 8 != 0 ? 'q' : ''}';
    return '$sb ${side == white ? 'w' : 'b'} ${c.isEmpty ? '-' : c} ${ep >= 0 ? sqName(ep) : '-'} $half $full';
  }

  bool isAttacked(int s, int by) {
    // Tốt: ô s bị tốt bên [by] đứng chéo phía dưới (trắng) hoặc phía trên (đen) tấn công.
    final pr = rankOf(s) + (by == white ? -1 : 1), f = fileOf(s);
    if (pr >= 0 && pr < 8) {
      if (f > 0 && board[sqOf(f - 1, pr)] == piece(by, pawn)) return true;
      if (f < 7 && board[sqOf(f + 1, pr)] == piece(by, pawn)) return true;
    }
    for (final t in _knightTo[s]) {
      if (board[t] == piece(by, knight)) return true;
    }
    for (final t in _kingTo[s]) {
      if (board[t] == piece(by, king)) return true;
    }
    final rq = piece(by, rook), bq = piece(by, bishop), qq = piece(by, queen);
    final rays = _rays[s];
    for (var d = 0; d < 8; d++) {
      for (final t in rays[d]) {
        final p = board[t];
        if (p == 0) continue;
        if (p == qq || p == (d < 4 ? rq : bq)) return true;
        break;
      }
    }
    return false;
  }

  bool get inCheck => isAttacked(kingSq[side], side ^ 1);

  /// Nước đi giả hợp lệ (chưa xét vua bị chiếu sau khi đi). [capturesOnly] cho tìm kiếm tĩnh của engine.
  List<int> pseudoMoves({bool capturesOnly = false}) {
    final out = <int>[];
    final us = side, them = side ^ 1;
    for (var s = 0; s < 64; s++) {
      final p = board[s];
      if (p == 0 || colorOf(p) != us) continue;
      switch (typeOf(p)) {
        case pawn:
          final dir = us == white ? 8 : -8;
          final lastRank = us == white ? 7 : 0;
          final t = s + dir;
          void add(int to, int flags) {
            if (rankOf(to) == lastRank) {
              for (final pr in const [queen, rook, bishop, knight]) {
                out.add(mkMove(s, to, pr, flags));
              }
            } else {
              out.add(mkMove(s, to, 0, flags));
            }
          }

          if (t >= 0 && t < 64 && board[t] == 0 && (!capturesOnly || rankOf(t) == lastRank)) {
            add(t, 0);
            final startRank = us == white ? 1 : 6;
            if (!capturesOnly && rankOf(s) == startRank && board[t + dir] == 0) out.add(mkMove(s, t + dir, 0, fDouble));
          }
          for (final df in const [-1, 1]) {
            final f = fileOf(s) + df;
            if (f < 0 || f > 7 || t < 0 || t > 63) continue;
            final c = sqOf(f, rankOf(t));
            if (board[c] != 0 && colorOf(board[c]) == them) add(c, fCapture);
            if (c == ep) out.add(mkMove(s, c, 0, fCapture | fEp));
          }
        case knight:
          for (final t in _knightTo[s]) {
            final q = board[t];
            if (q == 0 ? !capturesOnly : colorOf(q) == them) out.add(mkMove(s, t, 0, q == 0 ? 0 : fCapture));
          }
        case king:
          for (final t in _kingTo[s]) {
            final q = board[t];
            if (q == 0 ? !capturesOnly : colorOf(q) == them) out.add(mkMove(s, t, 0, q == 0 ? 0 : fCapture));
          }
          if (!capturesOnly) {
            final home = us == white ? 4 : 60;
            final ks = us == white ? 1 : 4, qs = us == white ? 2 : 8;
            if (s == home && castle & (ks | qs) != 0 && !isAttacked(s, them)) {
              if (castle & ks != 0 && board[s + 1] == 0 && board[s + 2] == 0 && board[s + 3] == piece(us, rook) &&
                  !isAttacked(s + 1, them) && !isAttacked(s + 2, them)) {
                out.add(mkMove(s, s + 2, 0, fCastle));
              }
              if (castle & qs != 0 && board[s - 1] == 0 && board[s - 2] == 0 && board[s - 3] == 0 && board[s - 4] == piece(us, rook) &&
                  !isAttacked(s - 1, them) && !isAttacked(s - 2, them)) {
                out.add(mkMove(s, s - 2, 0, fCastle));
              }
            }
          }
        default:
          final t0 = typeOf(p);
          final from = t0 == bishop ? 4 : 0, to = t0 == rook ? 4 : 8;
          final rays = _rays[s];
          for (var d = from; d < to; d++) {
            for (final t in rays[d]) {
              final q = board[t];
              if (q == 0) {
                if (!capturesOnly) out.add(mkMove(s, t));
                continue;
              }
              if (colorOf(q) == them) out.add(mkMove(s, t, 0, fCapture));
              break;
            }
          }
      }
    }
    return out;
  }

  /// Các nước đi hợp lệ.
  List<int> legalMoves() {
    final out = <int>[];
    for (final m in pseudoMoves()) {
      if (make(m)) {
        out.add(m);
        unmake();
      }
    }
    return out;
  }

  /// Đi nước [m]; trả về false (và tự lùi lại) nếu nước đó để vua bị chiếu.
  bool make(int m) {
    final from = mFrom(m), to = mTo(m), promo = mPromo(m), flags = mFlags(m);
    final us = side;
    final p = board[from];
    var capSq = to;
    if (flags & fEp != 0) capSq = to + (us == white ? -8 : 8);
    final captured = board[capSq];
    _stack.add(_Undo(m, captured, castle, ep, half, hash));
    history.add(hash);
    var h = hash ^ _zCastle[castle] ^ _zSide;
    if (ep >= 0) h ^= _zEp[fileOf(ep)];
    if (captured != 0) {
      h ^= _zPiece[captured * 64 + capSq];
      board[capSq] = 0;
    }
    final moved = promo != 0 ? piece(us, promo) : p;
    h ^= _zPiece[p * 64 + from] ^ _zPiece[moved * 64 + to];
    board[from] = 0;
    board[to] = moved;
    if (flags & fCastle != 0) {
      final (rf, rt) = to > from ? (from + 3, from + 1) : (from - 4, from - 1);
      final r = board[rf];
      board[rf] = 0;
      board[rt] = r;
      h ^= _zPiece[r * 64 + rf] ^ _zPiece[r * 64 + rt];
    }
    if (typeOf(p) == king) kingSq[us] = to;
    castle &= _castleKeep[from] & _castleKeep[to];
    ep = flags & fDouble != 0 ? (from + to) >> 1 : -1;
    half = typeOf(p) == pawn || captured != 0 ? 0 : half + 1;
    if (us == black) full++;
    side ^= 1;
    h ^= _zCastle[castle];
    if (ep >= 0) h ^= _zEp[fileOf(ep)];
    hash = h;
    if (isAttacked(kingSq[us], side)) {
      unmake();
      return false;
    }
    return true;
  }

  void unmake() {
    final u = _stack.removeLast();
    history.removeLast();
    final m = u.move;
    final from = mFrom(m), to = mTo(m), flags = mFlags(m);
    side ^= 1;
    final us = side;
    if (us == black) full--;
    var p = board[to];
    if (mPromo(m) != 0) p = piece(us, pawn);
    board[from] = p;
    board[to] = 0;
    if (u.captured != 0) board[flags & fEp != 0 ? to + (us == white ? -8 : 8) : to] = u.captured;
    if (flags & fCastle != 0) {
      final (rf, rt) = to > from ? (from + 3, from + 1) : (from - 4, from - 1);
      board[rf] = board[rt];
      board[rt] = 0;
    }
    if (typeOf(p) == king) kingSq[us] = from;
    castle = u.castle;
    ep = u.ep;
    half = u.half;
    hash = u.hash;
  }

  /// Nước đi cuối (null nếu chưa đi nước nào trên đối tượng này).
  int? get lastMove => _stack.isEmpty ? null : _stack.last.move;

  int repetitions() {
    var n = 0;
    for (var i = history.length - 2, k = 0; i >= 0 && k < half; i -= 2, k += 2) {
      if (history[i] == hash) n++;
    }
    return n;
  }

  bool get insufficientMaterial {
    var minors = 0;
    for (final p in board) {
      final t = typeOf(p);
      if (t == pawn || t == rook || t == queen) return false;
      if (t == knight || t == bishop) minors++;
    }
    return minors <= 1;
  }

  GameStatus status() {
    if (legalMoves().isEmpty) return inCheck ? GameStatus.checkmate : GameStatus.stalemate;
    if (half >= 100) return GameStatus.fiftyMoves;
    if (repetitions() >= 2) return GameStatus.repetition;
    if (insufficientMaterial) return GameStatus.material;
    return GameStatus.ongoing;
  }

  /// Tìm nước hợp lệ theo ô đi/ô đến (phong cấp mặc định là hậu).
  int? findMove(int from, int to, [int promo = queen]) {
    int? any;
    for (final m in legalMoves()) {
      if (mFrom(m) != from || mTo(m) != to) continue;
      if (mPromo(m) == 0 || mPromo(m) == promo) return m;
      any = m;
    }
    return any;
  }

  int? parseUci(String s) {
    if (s.length < 4) return null;
    final promo = s.length > 4 ? ' pnbrqk'.indexOf(s[4]) : queen;
    return findMove(parseSq(s.substring(0, 2)), parseSq(s.substring(2, 4)), promo);
  }

  /// Ký hiệu SAN của nước hợp lệ [m] trong thế hiện tại: Nf3, exd5, O-O, e8=Q+.
  String san(int m) {
    final from = mFrom(m), to = mTo(m);
    final t = typeOf(board[from]);
    final sb = StringBuffer();
    if (mFlags(m) & fCastle != 0) {
      sb.write(to > from ? 'O-O' : 'O-O-O');
    } else {
      final cap = mFlags(m) & fCapture != 0;
      if (t == pawn) {
        if (cap) sb.write('${'abcdefgh'[fileOf(from)]}x');
        sb.write(sqName(to));
        if (mPromo(m) != 0) sb.write('=${' PNBRQK'[mPromo(m)]}');
      } else {
        sb.write(' PNBRQK'[t]);
        final rivals = [
          for (final o in legalMoves())
            if (o != m && mTo(o) == to && typeOf(board[mFrom(o)]) == t) mFrom(o),
        ];
        if (rivals.isNotEmpty) {
          if (rivals.every((s) => fileOf(s) != fileOf(from))) {
            sb.write('abcdefgh'[fileOf(from)]);
          } else if (rivals.every((s) => rankOf(s) != rankOf(from))) {
            sb.write(rankOf(from) + 1);
          } else {
            sb.write(sqName(from));
          }
        }
        if (cap) sb.write('x');
        sb.write(sqName(to));
      }
    }
    make(m);
    if (inCheck) sb.write(legalMoves().isEmpty ? '#' : '+');
    unmake();
    return sb.toString();
  }

  int? parseSan(String s) {
    final clean = s.replaceAll(RegExp(r'[+#!?]'), '');
    for (final m in legalMoves()) {
      if (san(m).replaceAll(RegExp(r'[+#]'), '') == clean) return m;
    }
    return null;
  }
}

/// Đếm số nút ở độ sâu [depth] — để kiểm tra bộ sinh nước đi.
int perft(Position p, int depth) {
  if (depth == 0) return 1;
  var n = 0;
  for (final m in p.pseudoMoves()) {
    if (!p.make(m)) continue;
    n += depth == 1 ? 1 : perft(p, depth - 1);
    p.unmake();
  }
  return n;
}
