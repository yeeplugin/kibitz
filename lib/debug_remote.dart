/// Công cụ thử cho bản desktop, chỉ chạy ở bản debug khi đặt biến môi trường KIBITZ_REMOTE:
/// đọc lệnh từ tệp `cmd.txt` trong thư mục tạm của app ("tap x y", "wait ms", "shot tên") để bấm và chụp màn hình app.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

void startDebugRemote() {
  if (!kDebugMode || kIsWeb || Platform.environment['KIBITZ_REMOTE'] == null) return;
  final dir = Directory('${Directory.systemTemp.path}/kibitz_remote')..createSync(recursive: true);
  debugPrint('remote: ${dir.path}');
  var pointer = 100, busy = false;
  Timer.periodic(const Duration(milliseconds: 300), (_) async {
    final f = File('${dir.path}/cmd.txt');
    if (busy || !f.existsSync()) return;
    busy = true;
    final lines = f.readAsLinesSync();
    f.deleteSync();
    for (final line in lines) {
      final a = line.trim().split(' ');
      if (a[0] == 'tap') {
        final p = Offset(double.parse(a[1]), double.parse(a[2]));
        pointer++;
        GestureBinding.instance.handlePointerEvent(PointerDownEvent(pointer: pointer, position: p));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        GestureBinding.instance.handlePointerEvent(PointerUpEvent(pointer: pointer, position: p));
      } else if (a[0] == 'wait') {
        await Future<void>.delayed(Duration(milliseconds: int.parse(a[1])));
      } else if (a[0] == 'shot') {
        final view = RendererBinding.instance.renderViews.first;
        final layer = view.debugLayer! as OffsetLayer;
        final img = await layer.toImage(Offset.zero & view.size);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('${dir.path}/${a[1]}.png').writeAsBytesSync(png!.buffer.asUint8List());
      }
    }
    File('${dir.path}/done.txt').writeAsStringSync('${DateTime.now()}');
    busy = false;
  });
}
