/// Ván cờ đang chơi và các phần "huấn luyện": tên nước đi dễ hiểu, chấm chất lượng nước vừa đi.
library;

import 'chess/engine.dart';
import 'chess/position.dart';
import 'i18n.dart';

/// Bên được gợi ý: trắng, đen, cả hai (gợi ý cho bên đang đi), hoặc không bên nào — chỉ ghi lại nước đi.
enum Side {
  white,
  black,
  both,
  none;

  /// Có gợi ý và chấm nước cho bên [color] không.
  bool coaches(int color) => switch (this) { Side.both => true, Side.none => false, Side.white => color == 0, Side.black => color == 1 };
}

/// Độ mạnh của gợi ý = thời gian engine được nghĩ.
enum Level {
  easy(300, 3),
  normal(1000, 64),
  strong(3000, 64);

  const Level(this.ms, this.depth);
  final int ms, depth;

  String get label => switch (this) { Level.easy => 'Nhanh'.tr, Level.normal => 'Vừa'.tr, Level.strong => 'Kỹ'.tr };
}

/// Một màn đánh với máy. Máy mạnh dần: màn đầu hay đi bừa và chỉ nhìn một nước, màn 10 đánh hết sức, màn 11 là
/// Stockfish nghĩ 10 giây mỗi nước (bản Pro).
class Stage {
  const Stage(this.no, this.random, this.depth, this.ms, {this.stockfish = false});

  /// Số màn, 1…10.
  final int no;

  /// Xác suất máy đi bừa một nước.
  final double random;

  /// Engine có sẵn được nhìn sâu tối đa bao nhiêu nước và nghĩ bao lâu; [depth] = 0 là đánh hết sức.
  final int depth, ms;

  bool get full => depth == 0;

  /// Màn chỉ đánh bằng Stockfish (cần bản Pro).
  final bool stockfish;

  static const all = [
    Stage(1, 0.6, 1, 100),
    Stage(2, 0.4, 1, 100),
    Stage(3, 0.2, 1, 100),
    Stage(4, 0.1, 2, 200),
    Stage(5, 0, 2, 200),
    Stage(6, 0, 3, 300),
    Stage(7, 0, 4, 500),
    Stage(8, 0, 5, 800),
    Stage(9, 0, 64, 1500),
    Stage(10, 0, 0, 3000),
    Stage(11, 0, 0, 10000, stockfish: true),
  ];

  static Stage of(int no) => all[(no - 1).clamp(0, all.length - 1)];
}

const _initialFen = startFen;

class Game {
  Game({String? startFen, List<String>? moves, DateTime? startedAt, this.whiteName = '', this.blackName = '', Map<int, int>? marks})
      : startFen = startFen ?? _initialFen,
        moves = moves ?? [],
        startedAt = startedAt ?? DateTime.now(),
        marks = marks ?? {};
  final String startFen;

  /// Các nước đã đi, dạng UCI.
  final List<String> moves;

  /// Lúc bắt đầu ván; cũng là mã phân biệt các ván đã lưu.
  final DateTime startedAt;

  /// Tên người chơi ghi trong biên bản (có thể để trống).
  String whiteName, blackName;

  /// Lời chấm của engine cho từng nước: chỉ số nước (0 = nước đầu) → chỉ số [MoveQuality].
  final Map<int, int> marks;

  Position position([int? upto]) {
    final p = Position.fromFen(startFen);
    for (final u in moves.take(upto ?? moves.length)) {
      final m = p.parseUci(u);
      if (m == null) break;
      p.make(m);
    }
    return p;
  }

  List<String> sans() {
    final p = Position.fromFen(startFen);
    final out = <String>[];
    for (final u in moves) {
      final m = p.parseUci(u);
      if (m == null) break;
      out.add(p.san(m));
      p.make(m);
    }
    return out;
  }

  /// Bên đi nước đầu tiên và số thứ tự của nước đó (ván xếp sẵn có thể bắt đầu từ lượt đen, nước 23…).
  (int, int) get _start {
    final f = startFen.split(' ');
    return (f.length > 1 && f[1] == 'b' ? black : white, f.length > 5 ? int.tryParse(f[5]) ?? 1 : 1);
  }

  /// Số thứ tự và bên đi của nước thứ [ply] (0 = nước đầu).
  (int, int) moveNo(int ply) {
    final (side, no) = _start;
    final half = ply + (side == black ? 1 : 0);
    return (no + half ~/ 2, half.isEven ? white : black);
  }

  /// Kết quả kiểu PGN: 1-0, 0-1, 1/2-1/2, hoặc * khi ván chưa xong.
  String get result {
    final p = position();
    return switch (p.status()) {
      GameStatus.ongoing => '*',
      GameStatus.checkmate => p.side == white ? '0-1' : '1-0',
      _ => '1/2-1/2',
    };
  }

  /// Các nước đi dạng "1. e4 e5 2. Nf3 …"; [nags] thêm ký hiệu chấm nước của PGN ($2 sai lầm, $4 nghiêm trọng, $6 chưa
  /// chính xác).
  List<String> moveTokens({bool nags = false}) {
    final s = sans();
    final out = <String>[];
    for (var i = 0; i < s.length; i++) {
      final (no, side) = moveNo(i);
      if (side == white) {
        out.add('$no.');
      } else if (i == 0) {
        out.add('$no...');
      }
      out.add(s[i]);
      if (nags) {
        final nag = switch (marks[i]) { 2 => r'$6', 3 => r'$2', 4 => r'$4', _ => null };
        if (nag != null) out.add(nag);
      }
    }
    return out;
  }

  /// Biên bản ván cờ dạng PGN — mở được bằng Lichess, Chess.com, ChessBase…
  String pgn() {
    String q(String v) => v.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    String two(int v) => v.toString().padLeft(2, '0');
    final d = startedAt;
    final sb = StringBuffer()
      ..writeln('[Event "Casual game"]')
      ..writeln('[Site "?"]')
      ..writeln('[Date "${d.millisecondsSinceEpoch == 0 ? '????.??.??' : '${d.year}.${two(d.month)}.${two(d.day)}'}"]')
      ..writeln('[Round "-"]')
      ..writeln('[White "${whiteName.trim().isEmpty ? '?' : q(whiteName.trim())}"]')
      ..writeln('[Black "${blackName.trim().isEmpty ? '?' : q(blackName.trim())}"]')
      ..writeln('[Result "$result"]');
    if (startFen != _initialFen) {
      sb
        ..writeln('[SetUp "1"]')
        ..writeln('[FEN "$startFen"]');
    }
    sb.writeln();
    var line = '';
    for (final t in [...moveTokens(nags: true), result]) {
      if (line.isNotEmpty && line.length + 1 + t.length > 80) {
        sb.writeln(line);
        line = t;
      } else {
        line = line.isEmpty ? t : '$line $t';
      }
    }
    sb.writeln(line);
    return sb.toString();
  }

  Map<String, dynamic> toJson() => {
        'fen': startFen,
        'moves': moves,
        'at': startedAt.millisecondsSinceEpoch,
        'white': whiteName,
        'black': blackName,
        'marks': {for (final e in marks.entries) '${e.key}': e.value},
      };
  static Game fromJson(Map<dynamic, dynamic> j) => Game(
        startFen: j['fen'] as String? ?? _initialFen,
        moves: [...(j['moves'] as List? ?? const []).cast<String>()],
        startedAt: DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
        whiteName: j['white'] as String? ?? '',
        blackName: j['black'] as String? ?? '',
        marks: {for (final e in (j['marks'] as Map? ?? const {}).entries) int.parse('${e.key}'): e.value as int},
      );
}

const pieceNames = ['', 'Tốt', 'Mã', 'Tượng', 'Xe', 'Hậu', 'Vua'];

/// "Mã g1 → f3" — cách đọc nước đi cho người mới, kèm SAN.
String describeMove(Position p, int m) {
  final t = typeOf(p.board[mFrom(m)]);
  if (mFlags(m) & fCastle != 0) return mTo(m) > mFrom(m) ? 'Nhập thành cánh vua'.tr : 'Nhập thành cánh hậu'.tr;
  final cap = mFlags(m) & fCapture != 0;
  final victim = mFlags(m) & fEp != 0 ? pawn : typeOf(p.board[mTo(m)]);
  var s = '${pieceNames[t].tr} ${sqName(mFrom(m))} → ${sqName(mTo(m))}';
  if (cap) s += ' ${'ăn {0}'.trArgs([pieceNames[victim].tr.toLowerCase()])}';
  if (mPromo(m) != 0) s += ', ${'phong {0}'.trArgs([pieceNames[mPromo(m)].tr.toLowerCase()])}';
  return s;
}

/// Điểm thế cờ cho người xem: "+1.3", "-0.4", "M3" (chiếu hết sau 3 nước).
String scoreText(Analysis a) {
  final m = a.mateIn;
  if (m != null) return m > 0 ? '#$m' : '#-${-m}';
  // Làm tròn trước khi xét dấu, để điểm rất nhỏ không hiện thành "-0.0".
  final t = (a.whiteScore / 100).toStringAsFixed(1);
  if (t == '-0.0' || t == '0.0') return '0.0';
  return t.startsWith('-') ? t : '+$t';
}

/// Điểm bên trắng quy về thang -1…1 để vẽ thanh đánh giá.
double scoreBar(Analysis a) {
  final m = a.mateIn;
  if (m != null) return m > 0 ? 1 : -1;
  final v = a.whiteScore / 600;
  return v.clamp(-1.0, 1.0);
}

enum MoveQuality { best, good, inaccuracy, mistake, blunder }

extension MoveQualityText on MoveQuality {
  String get label => switch (this) {
        MoveQuality.best => 'Nước hay nhất'.tr,
        MoveQuality.good => 'Nước tốt'.tr,
        MoveQuality.inaccuracy => 'Chưa chính xác'.tr,
        MoveQuality.mistake => 'Sai lầm'.tr,
        MoveQuality.blunder => 'Sai lầm nghiêm trọng'.tr,
      };
}

/// Điểm (centipawn, góc nhìn bên trắng) có quy đổi chiếu hết thành số lớn để so sánh được.
int _cp(Analysis a) {
  final m = a.mateIn;
  if (m == null) return a.whiteScore.clamp(-3000, 3000);
  return m > 0 ? 5000 - m * 10 : -5000 - m * 10;
}

/// Chấm nước [played] (UCI) mà bên [mover] vừa đi: so điểm trước nước đi ([before], phân tích thế cũ, có nước tốt
/// nhất) với điểm sau nước đi ([after]). Trả về chất lượng và số điểm mất (centipawn, ≥ 0).
(MoveQuality, int) judge(Analysis before, Analysis after, String played, int mover) {
  if (played == before.best) return (MoveQuality.best, 0);
  final sign = mover == white ? 1 : -1;
  final loss = ((_cp(before) - _cp(after)) * sign).clamp(0, 10000);
  final q = loss < 30
      ? MoveQuality.good
      : loss < 90
          ? MoveQuality.inaccuracy
          : loss < 250
              ? MoveQuality.mistake
              : MoveQuality.blunder;
  return (q, loss);
}

String statusText(GameStatus s, int sideToMove) => switch (s) {
      GameStatus.checkmate => 'Chiếu hết! {0} thắng.'.trArgs([sideToMove == white ? 'Đen'.tr : 'Trắng'.tr]),
      GameStatus.stalemate => 'Hết nước đi (pat) — hoà.'.tr,
      GameStatus.fiftyMoves => 'Hoà theo luật 50 nước.'.tr,
      GameStatus.repetition => 'Hoà do lặp lại thế cờ ba lần.'.tr,
      GameStatus.material => 'Hoà do không đủ quân chiếu hết.'.tr,
      GameStatus.ongoing => '',
    };
