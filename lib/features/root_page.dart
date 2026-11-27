/// Khung gốc của app: thanh tab kiểu iOS với ba mục Chơi / Ván đã ghi / Cài đặt.
library;

import 'package:cupertino_ui/cupertino_ui.dart';

import '../core/i18n.dart';
import '../data/store.dart';
import '../services/billing.dart';
import '../shared/ios.dart';
import 'home_page.dart';
import 'record_page.dart';
import 'settings_page.dart';

/// Tên app hiện ở đầu thanh bên.
const appName = 'Kibitz';

class RootPage extends StatefulWidget {
  const RootPage({super.key, required this.store, required this.billing});
  final Store store;
  final Billing billing;

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (CupertinoIcons.camera_viewfinder, CupertinoIcons.camera_viewfinder, 'Chơi'.tr),
      (CupertinoIcons.clock, CupertinoIcons.clock_fill, 'Ván đã ghi'.tr),
      (CupertinoIcons.gear, CupertinoIcons.gear_solid, 'Cài đặt'.tr),
    ];
    final pages = IndexedStack(index: _tab, children: [
      HomePage(store: widget.store, billing: widget.billing),
      GamesPage(store: widget.store),
      SettingsPage(store: widget.store, billing: widget.billing),
    ]);
    // Màn rộng (iPad, máy gập mở): thanh bên thay cho thanh tab dưới đáy.
    if (iosWide(context)) {
      final pad = MediaQuery.paddingOf(context);
      return ColoredBox(
        color: iosGroupedBg(context),
        child: Row(children: [
          Container(
            width: 250 + pad.left,
            padding: EdgeInsets.fromLTRB(pad.left + 12, pad.top + 16, 12, pad.bottom + 12),
            decoration: BoxDecoration(color: iosCellBg(context), border: Border(right: BorderSide(color: iosSeparator(context), width: 0.5))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
                child: Text(appName, maxLines: 1, overflow: TextOverflow.ellipsis, style: tTitle2.copyWith(color: iosLabel(context), decoration: TextDecoration.none)),
              ),
              for (var i = 0; i < tabs.length; i++)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _tab = i),
                  child: Container(
                    height: 46,
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: i == _tab ? iosTint(context).withValues(alpha: 0.14) : null, borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Icon(i == _tab ? tabs[i].$2 : tabs[i].$1, size: 22, color: iosTint(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(tabs[i].$3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tBody.copyWith(color: iosLabel(context), fontWeight: i == _tab ? FontWeight.w600 : FontWeight.w400, decoration: TextDecoration.none)),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
          Expanded(child: MediaQuery.removePadding(context: context, removeLeft: true, child: pages)),
        ]),
      );
    }
    return ColoredBox(
      color: iosGroupedBg(context),
      child: Column(children: [
        Expanded(child: MediaQuery.removePadding(context: context, removeBottom: true, child: pages)),
        CupertinoTabBar(
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
          items: [for (final t in tabs) BottomNavigationBarItem(icon: Icon(t.$1), activeIcon: Icon(t.$2), label: t.$3)],
        ),
      ]),
    );
  }
}
