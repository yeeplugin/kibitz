import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoThemeData;
import 'package:material_ui/material_ui.dart';

import 'data/store.dart';
import 'debug_remote.dart';
import 'features/root_page.dart';
import 'shared/board_view.dart' show brandBlue;
import 'services/billing.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await Store.open();
  final billing = Billing(store: Billing.platformStore(), isPro: () => store.pro, setPro: store.setPro);
  // Hỏi lại cửa hàng quyền Pro; không chờ để app mở ngay.
  unawaited(billing.start());
  runApp(ChessApp(store: store, billing: billing));
  startDebugRemote();
}

class ChessApp extends StatelessWidget {
  const ChessApp({super.key, required this.store, required this.billing});
  final Store store;
  final Billing billing;

  ThemeData _theme(Brightness b) {
    // Màu chủ đạo: xanh dương kiểu iOS (#007AFF; nền tối dùng #0A84FF cho dễ đọc).
    final light = b == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: brandBlue,
      brightness: b,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ).copyWith(primary: light ? brandBlue : const Color(0xFF0A84FF), onPrimary: Colors.white);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: light ? const Color(0xFFF2F2F7) : Colors.black,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      cupertinoOverrideTheme: CupertinoThemeData(brightness: b, primaryColor: light ? brandBlue : const Color(0xFF0A84FF)),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: light ? Colors.white : const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: 'Kibitz',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        locale: Locale(store.lang),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: RootPage(store: store, billing: billing),
      ),
    );
  }
}
