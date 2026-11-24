import 'package:chess_coach/core/chess/engine.dart';
import 'package:chess_coach/core/coach.dart';
import 'package:chess_coach/core/chess/position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('perft thế khởi đầu', () {
    final p = Position.start();
    expect([1, 2, 3, 4].map((d) => perft(p, d)).toList(), [20, 400, 8902, 197281]);
  });
  test('perft kiwipete', () {
    final p = Position.fromFen('r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1');
    expect([1, 2, 3].map((d) => perft(p, d)).toList(), [48, 2039, 97862]);
  });
  test('perft vị trí 3 (bắt tốt qua đường, chiếu)', () {
    final p = Position.fromFen('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1');
    expect([1, 2, 3, 4].map((d) => perft(p, d)).toList(), [14, 191, 2812, 43238]);
  });
  test('perft vị trí 4 (phong cấp)', () {
    final p = Position.fromFen('r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1');
    expect([1, 2, 3].map((d) => perft(p, d)).toList(), [6, 264, 9467]);
  });
  test('FEN và hash giữ nguyên sau đi/lùi', () {
    final p = Position.start();
    final h = p.hash;
    for (final u in ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6', 'e1g1']) {
      p.make(p.parseUci(u)!);
    }
    expect(p.fen, 'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQ1RK1 b kq - 5 4');
    expect(p.hash, p.computeHash());
    for (var i = 0; i < 7; i++) {
      p.unmake();
    }
    expect(p.fen, startFen);
    expect(p.hash, h);
  });
  test('SAN', () {
    final p = Position.fromFen('r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1');
    final sans = p.legalMoves().map(p.san).toSet();
    expect(sans, containsAll(['O-O', 'O-O-O', 'Nxd7', 'Qxf6', 'gxh3', 'Bxa6', 'd6', 'Rb1', 'Nc6']));
    final q = Position.fromFen('7k/8/8/8/8/8/6Q1/K5R1 w - - 0 1');
    expect(q.san(q.parseUci('g2g7')!), 'Qg7#');
  });
  test('engine thấy chiếu hết 1 và 2 nước', () {
    final r1 = analyzeSync('6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1', [], ms: 2000);
    expect(r1.best, 'a1a8');
    expect(r1.mateIn, 1);
    final r2 = analyzeSync('r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4', [], ms: 2000);
    expect(r2.best, 'h5f7');
  });
  test('engine ăn quân treo', () {
    final r = analyzeSync('rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2', ['g1f3', 'd8d6', 'f3e5', 'd6e5'], ms: 1000);
    expect(r.depth, greaterThan(3));
  });
  test('xuất PGN: thẻ, số nước, kết quả, ký hiệu chấm nước', () {
    final g = Game(moves: ['f2f3', 'e7e5', 'g2g4', 'd8h4'], startedAt: DateTime(2026, 11, 23), whiteName: 'An "A"', marks: {2: 4});
    final pgn = g.pgn();
    expect(pgn, contains('[Date "2026.11.23"]'));
    expect(pgn, contains(r'[White "An \"A\""]'));
    expect(pgn, contains('[Black "?"]'));
    expect(pgn, contains('[Result "0-1"]'));
    expect(pgn, isNot(contains('[FEN')));
    expect(pgn.trim().split('\n').last, r'1. f3 e5 2. g4 $4 Qh4# 0-1');
    final back = Game.fromJson(g.toJson());
    expect(back.pgn(), pgn);
  });
  test('xuất PGN: ván xếp sẵn bắt đầu từ lượt đen, dòng không quá 80 ký tự', () {
    const fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 7';
    final g = Game(startFen: fen, moves: ['e7e5', 'g1f3']);
    expect(g.pgn(), contains('[SetUp "1"]\n[FEN "$fen"]'));
    expect(g.moveTokens().join(' '), '7... e5 8. Nf3');
    final long = Game(moves: [for (var i = 0; i < 20; i++) ...['g1f3', 'g8f6', 'f3g1', 'f6g8']]);
    expect(long.pgn().split('\n').every((l) => l.length <= 80), isTrue);
    expect(long.result, '1/2-1/2');
  });
}
