/// Đa ngôn ngữ kiểu gettext: chuỗi tiếng Việt trong mã nguồn là khoá, bảng [i18nEn] dịch sang tiếng Anh.
library;

import 'dart:ui' show PlatformDispatcher;

import 'i18n_en.dart';

abstract final class I18n {
  static String lang = 'vi';
  static const languages = {'vi': 'Tiếng Việt', 'en': 'English'};

  static String fromDevice() => PlatformDispatcher.instance.locale.languageCode == 'vi' ? 'vi' : 'en';

  static String t(String s) => lang == 'vi' ? s : (i18nEn[s] ?? s);
}

extension Tr on String {
  String get tr => I18n.t(this);

  /// Thay {0}, {1}… bằng [args].
  String trArgs(List<Object?> args) {
    var s = I18n.t(this);
    for (var i = 0; i < args.length; i++) {
      s = s.replaceAll('{$i}', '${args[i]}');
    }
    return s;
  }
}
