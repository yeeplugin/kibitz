/// Bộ khung giao diện kiểu iOS dùng chung: trang có thanh tiêu đề, danh sách bo nhóm, nút, hộp thoại, bảng chọn.
library;

import 'dart:async';
import 'dart:ui' show DisplayFeatureType;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart' show Material, MaterialType, showModalBottomSheet;

export 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoIcons, CupertinoSwitch, CupertinoActivityIndicator, CupertinoColors, CupertinoButton, CupertinoTheme;

// Cỡ chữ theo bảng chữ của iOS.
const tLargeTitle = TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: 0.37);
const tTitle2 = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 0.35);
const tHeadline = TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.41);
const tBody = TextStyle(fontSize: 17, letterSpacing: -0.41);
const tSubhead = TextStyle(fontSize: 15, letterSpacing: -0.24);
const tFootnote = TextStyle(fontSize: 13, letterSpacing: -0.08);

Color _r(BuildContext c, CupertinoDynamicColor d) => CupertinoDynamicColor.resolve(d, c);

Color iosGroupedBg(BuildContext c) => _r(c, CupertinoColors.systemGroupedBackground);
Color iosCellBg(BuildContext c) => _r(c, CupertinoColors.secondarySystemGroupedBackground);
Color iosLabel(BuildContext c) => _r(c, CupertinoColors.label);
Color iosLabel2(BuildContext c) => _r(c, CupertinoColors.secondaryLabel);
Color iosLabel3(BuildContext c) => _r(c, CupertinoColors.tertiaryLabel);
Color iosSeparator(BuildContext c) => _r(c, CupertinoColors.separator);
Color iosFill(BuildContext c) => _r(c, CupertinoColors.tertiarySystemFill);
Color iosTint(BuildContext c) => CupertinoTheme.of(c).primaryColor;
Color iosRed(BuildContext c) => _r(c, CupertinoColors.systemRed);

/// Mở trang mới kiểu iOS (vuốt từ mép trái để quay lại).
Route<T> iosRoute<T>(Widget page) => CupertinoPageRoute<T>(builder: (_) => page);

Future<T?> iosPush<T>(BuildContext context, Widget page) => Navigator.of(context, rootNavigator: true).push<T>(iosRoute<T>(page));

/// Màn rộng (iPad, máy gập đang mở, điện thoại xoay ngang): từ 700 điểm trở lên.
bool iosWide(BuildContext c) => MediaQuery.sizeOf(c).width >= 700;

/// Nếp gập / bản lề dọc chia đôi màn hình (máy gập đang mở), null nếu không có.
Rect? iosHinge(BuildContext c) {
  for (final f in MediaQuery.displayFeaturesOf(c)) {
    final vertical = f.bounds.height > f.bounds.width;
    if (vertical && (f.type == DisplayFeatureType.hinge || f.type == DisplayFeatureType.fold) && f.bounds.left > 0) return f.bounds;
  }
  return null;
}

/// Trang có thanh tiêu đề iOS. [large]: tiêu đề lớn co lại khi cuộn (dùng cho các trang gốc của tab).
///
/// Trang có bàn cờ đưa bàn vào [board]: màn hẹp thì bàn nằm trong cột, sau [boardAfter] mục đầu;
/// màn rộng nằm ngang (iPad ngang, máy gập mở) thì bàn chiếm bên trái, các mục còn lại thành cột bên phải.
class IosPage extends StatelessWidget {
  const IosPage({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.large = false,
    this.grouped = true,
    this.board,
    this.boardAfter = 0,
    this.boardMaxWidth = 600,
  });
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final bool large;
  final bool grouped;
  final Widget? board;
  final int boardAfter;
  final double boardMaxWidth;

  Widget _twoPane(BuildContext c) {
    final size = MediaQuery.sizeOf(c), pad = MediaQuery.paddingOf(c);
    final hinge = iosHinge(c);
    // Có bản lề: bàn cờ nằm trọn nửa trái, điều khiển nửa phải, không gì vắt qua nếp gập.
    final right = hinge != null ? size.width - hinge.right - pad.right : (size.width * 0.42).clamp(340.0, 440.0);
    return Padding(
      padding: EdgeInsets.only(top: pad.top, left: pad.left, right: pad.right),
      child: Row(children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 8, pad.bottom + 12),
            child: LayoutBuilder(builder: (_, b) {
              final side = b.maxWidth < b.maxHeight ? b.maxWidth : b.maxHeight;
              return Center(child: SizedBox(width: side, child: board));
            }),
          ),
        ),
        if (hinge != null) SizedBox(width: hinge.width),
        SizedBox(
          width: right,
          child: MediaQuery.removePadding(
            context: c,
            removeTop: true,
            removeLeft: true,
            removeRight: true,
            child: ListView(padding: EdgeInsets.only(top: 12, bottom: pad.bottom + 32), children: children),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final twoPane = board != null && !large && size.width >= 700 && size.width >= size.height;
    final items = board == null || twoPane
        ? children
        : [
            ...children.take(boardAfter),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: boardMaxWidth),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: board),
              ),
            ),
            ...children.skip(boardAfter),
          ];
    final body = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
      ),
    );
    final bg = grouped ? iosGroupedBg(context) : _r(context, CupertinoColors.systemBackground);
    return CupertinoPageScaffold(
      backgroundColor: bg,
      navigationBar: large ? null : CupertinoNavigationBar(middle: Text(title), trailing: trailing, transitionBetweenRoutes: false),
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: tBody.copyWith(color: iosLabel(context)),
          child: large
              ? CustomScrollView(slivers: [
                  CupertinoSliverNavigationBar(largeTitle: Text(title), trailing: trailing, transitionBetweenRoutes: false),
                  SliverSafeArea(top: false, sliver: SliverPadding(padding: const EdgeInsets.only(top: 6, bottom: 32), sliver: SliverToBoxAdapter(child: body))),
                ])
              // Lề trên lấy trong Builder: ở đó MediaQuery đã tính cả chiều cao thanh tiêu đề.
              : Builder(
                  builder: (c) => twoPane
                      ? _twoPane(c)
                      : ListView(
                          padding: EdgeInsets.only(top: MediaQuery.paddingOf(c).top + 12, bottom: MediaQuery.paddingOf(c).bottom + 32),
                          children: [body],
                        ),
                ),
        ),
      ),
    );
  }
}

/// Nút biểu tượng trên thanh tiêu đề.
class IosNavButton extends StatelessWidget {
  const IosNavButton({super.key, this.icon, this.label, this.bold = false, required this.onPressed, this.color});
  final IconData? icon;
  final String? label;
  final bool bold;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(36, 36),
        onPressed: onPressed,
        child: icon != null
            ? Icon(icon, size: 23, color: onPressed == null ? null : color)
            : Text(label ?? '', style: TextStyle(fontSize: 17, fontWeight: bold ? FontWeight.w600 : FontWeight.w400, color: onPressed == null ? null : color)),
      );
}

/// Nhóm dòng bo góc (inset grouped) với tiêu đề và chú thích.
class IosSection extends StatelessWidget {
  const IosSection({super.key, this.header, this.footer, required this.children, this.dividerIndent = 16, this.top = 22});
  final String? header;
  final String? footer;
  final List<Widget> children;
  final double dividerIndent;
  final double top;

  @override
  Widget build(BuildContext context) {
    final note = tFootnote.copyWith(color: iosLabel2(context));
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (header != null) Padding(padding: const EdgeInsets.fromLTRB(32, 0, 32, 7), child: Text(header!.toUpperCase(), style: note)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: iosCellBg(context), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Padding(padding: EdgeInsets.only(left: dividerIndent), child: Container(height: 0.5, color: iosSeparator(context))),
              children[i],
            ],
          ]),
        ),
        if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(32, 7, 32, 0), child: Text(footer!, style: note)),
      ]),
    );
  }
}

/// Một dòng trong [IosSection]: biểu tượng vuông màu, tiêu đề, phụ đề, giá trị, mũi tên.
class IosTile extends StatefulWidget {
  const IosTile({super.key, this.icon, this.iconColor, this.leading, required this.title, this.subtitle, this.value, this.trailing, this.onTap, this.chevron, this.titleColor, this.bold = false});
  final IconData? icon;
  final Color? iconColor;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool? chevron;
  final Color? titleColor;
  final bool bold;

  @override
  State<IosTile> createState() => _IosTileState();
}

class _IosTileState extends State<IosTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final chevron = w.chevron ?? (w.onTap != null && w.trailing == null);
    final row = AnimatedContainer(
      duration: Duration(milliseconds: _down ? 0 : 250),
      color: _down ? _r(context, CupertinoColors.systemGrey4) : iosCellBg(context).withValues(alpha: 0),
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        if (w.leading != null) ...[w.leading!, const SizedBox(width: 12)],
        if (w.icon != null) ...[
          Container(
            width: 29,
            height: 29,
            decoration: BoxDecoration(color: w.iconColor ?? iosTint(context), borderRadius: BorderRadius.circular(7)),
            child: Icon(w.icon, size: 18, color: CupertinoColors.white),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(w.title, style: (w.bold ? tHeadline : tBody).copyWith(color: w.titleColor ?? iosLabel(context))),
            if (w.subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(w.subtitle!, style: tFootnote.copyWith(color: iosLabel2(context)))),
          ]),
        ),
        if (w.value != null) Padding(padding: const EdgeInsets.only(left: 8), child: Text(w.value!, style: tBody.copyWith(color: iosLabel2(context)))),
        if (w.trailing != null) Padding(padding: const EdgeInsets.only(left: 8), child: w.trailing!),
        if (chevron) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(CupertinoIcons.chevron_forward, size: 15, color: iosLabel3(context))),
      ]),
    );
    if (w.onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: w.onTap,
      child: row,
    );
  }
}

/// Dòng có công tắc.
class IosSwitchTile extends StatelessWidget {
  const IosSwitchTile({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onChanged == null ? 0.45 : 1,
        child: IosTile(title: title, subtitle: subtitle, trailing: CupertinoSwitch(value: value, onChanged: onChanged)),
      );
}

/// Dòng gồm nhãn và nội dung tự do bên dưới (thanh chọn, lưới…).
class IosBlock extends StatelessWidget {
  const IosBlock({super.key, this.label, required this.child});
  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (label != null) Padding(padding: const EdgeInsets.only(bottom: 9), child: Text(label!, style: tBody.copyWith(color: iosLabel(context)))),
          child,
        ]),
      );
}

/// Thanh chọn một trong vài lựa chọn (segmented control). [onChanged] null = khoá cả thanh.
class IosSegmented<T extends Object> extends StatelessWidget {
  const IosSegmented({super.key, required this.items, required this.value, required this.onChanged, this.disabled = const {}, this.icons = const {}});
  final Map<T, String> items;
  final T value;
  final ValueChanged<T>? onChanged;
  final Set<T> disabled;
  final Map<T, IconData> icons;

  @override
  Widget build(BuildContext context) {
    final off = onChanged == null;
    return IgnorePointer(
      ignoring: off,
      child: Opacity(
        opacity: off ? 0.45 : 1,
        child: SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<T>(
            groupValue: items.containsKey(value) ? value : null,
            disabledChildren: disabled,
            onValueChanged: (v) {
              if (v != null) onChanged?.call(v);
            },
            children: {
              for (final e in items.entries)
                e.key: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
                  child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (icons[e.key] != null) Padding(padding: const EdgeInsets.only(right: 3), child: Icon(icons[e.key], size: 13, color: iosLabel2(context))),
                    Flexible(
                      child: Text(e.value,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: TextStyle(fontSize: 13, fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w400, color: iosLabel(context), letterSpacing: -0.08)),
                    ),
                  ]),
                ),
            },
          ),
        ),
      ),
    );
  }
}

enum IosButtonKind { filled, tinted, gray, plain }

/// Nút lớn kiểu iOS: cao 50, bo 12.
class IosButton extends StatelessWidget {
  const IosButton({super.key, required this.label, this.icon, required this.onPressed, this.kind = IosButtonKind.filled, this.compact = false, this.color});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final IosButtonKind kind;
  final bool compact;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? iosTint(context);
    final off = onPressed == null;
    final fg = off
        ? iosLabel3(context)
        : kind == IosButtonKind.filled
            ? CupertinoColors.white
            : tint;
    final child = Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (icon != null) Padding(padding: const EdgeInsets.only(right: 7), child: Icon(icon, size: compact ? 18 : 20, color: fg)),
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: (compact ? tSubhead.copyWith(fontWeight: FontWeight.w600) : tHeadline).copyWith(color: fg))),
    ]);
    final size = Size(compact ? 0 : double.infinity, compact ? 40 : 50);
    final radius = BorderRadius.circular(compact ? 10 : 12);
    const pad = EdgeInsets.symmetric(horizontal: 14);
    return switch (kind) {
      IosButtonKind.filled => CupertinoButton(color: tint, disabledColor: iosFill(context), padding: pad, minimumSize: size, borderRadius: radius, onPressed: onPressed, child: child),
      IosButtonKind.tinted => CupertinoButton(color: tint.withValues(alpha: 0.15), disabledColor: iosFill(context), padding: pad, minimumSize: size, borderRadius: radius, onPressed: onPressed, child: child),
      IosButtonKind.gray => CupertinoButton(color: iosFill(context), disabledColor: iosFill(context), padding: pad, minimumSize: size, borderRadius: radius, onPressed: onPressed, child: child),
      IosButtonKind.plain => CupertinoButton(padding: pad, minimumSize: size, onPressed: onPressed, child: child),
    };
  }
}

/// Hộp thoại hỏi có/không kiểu iOS.
Future<bool> iosConfirm(BuildContext context, {required String title, String? message, required String ok, required String cancel, bool destructive = false}) async {
  final r = await showCupertinoDialog<bool>(
    context: context,
    builder: (c) => CupertinoAlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(c, false), child: Text(cancel)),
        CupertinoDialogAction(isDestructiveAction: destructive, isDefaultAction: !destructive, onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// Bảng chọn trượt từ dưới lên (action sheet).
Future<T?> iosActionSheet<T>(BuildContext context, {String? title, required Map<T, String> actions, required String cancel, T? selected}) =>
    showCupertinoModalPopup<T>(
      context: context,
      builder: (c) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        actions: [
          for (final e in actions.entries)
            CupertinoActionSheetAction(
              isDefaultAction: e.key == selected,
              onPressed: () => Navigator.pop(c, e.key),
              child: Text(e.value),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(c), child: Text(cancel, style: const TextStyle(fontWeight: FontWeight.w600))),
      ),
    );

/// Bảng trượt từ dưới lên chứa nội dung tự do.
Future<T?> iosSheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      // iPad và máy gập mở: bảng không trải hết bề ngang.
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: iosGroupedBg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (c) => DefaultTextStyle(style: tBody.copyWith(color: iosLabel(c)), child: builder(c)),
    );

OverlayEntry? _toast;
Timer? _toastTimer;

/// Thông báo ngắn nổi phía trên màn hình rồi tự tắt.
void iosToast(BuildContext context, String text) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toastTimer?.cancel();
  _toast?.remove();
  final entry = OverlayEntry(
    builder: (c) => Positioned(
      left: 16,
      right: 16,
      top: MediaQuery.paddingOf(c).top + 8,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 220),
            builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, -12 * (1 - v)), child: child)),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xF22C2C2E),
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
              ),
              child: Text(text, textAlign: TextAlign.center, style: tSubhead.copyWith(color: CupertinoColors.white, decoration: TextDecoration.none, fontWeight: FontWeight.w500)),
            ),
          ),
        ),
      ),
    ),
  );
  _toast = entry;
  overlay.insert(entry);
  _toastTimer = Timer(const Duration(milliseconds: 3200), () {
    entry.remove();
    if (_toast == entry) _toast = null;
  });
}

/// Thanh cán cân thế cờ: phần sáng là trắng, phần tối là đen. [value] 0..1 = phần của trắng.
class EvalBar extends StatelessWidget {
  const EvalBar({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          height: 10,
          child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Color(0xFF3A3A3C)),
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 300),
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: const ColoredBox(color: Color(0xFFE5E5EA)),
            ),
          ]),
        ),
      );
}
