import 'dart:io';

import 'package:chess_coach/core/coach.dart';
import 'package:chess_coach/core/i18n_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mọi chuỗi .tr đều có bản tiếng Anh', () {
    final re = RegExp(r"'((?:[^'\\]|\\.)*)'\s*\.\s*tr(?:Args)?\b");
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in re.allMatches(f.readAsStringSync())) {
        final k = m.group(1)!.replaceAll(r"\'", "'");
        if (!i18nEn.containsKey(k)) missing.add('${f.path}: $k');
      }
    }
    for (final n in pieceNames.skip(1)) {
      if (!i18nEn.containsKey(n)) missing.add('pieceNames: $n');
    }
    expect(missing, isEmpty);
  });
}
