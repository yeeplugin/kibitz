/// Gói Pro bán qua App Store / Google Play bằng plugin chính thức `in_app_purchase`.
///
/// App không có máy chủ: mỗi lần mở, app hỏi lại cửa hàng xem gói còn hiệu lực không ([Billing.refresh]).
/// `Store.pro` chỉ là bản lưu tạm của câu trả lời gần nhất, để app vẫn chạy khi cửa hàng không trả lời.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

/// Gói thuê bao tự gia hạn hằng tháng (giá đặt trên cửa hàng: 0,99 USD/tháng). Mã này phải trùng với mã sản phẩm tạo
/// trên App Store Connect và Play Console.
const proMonthly = 'pro_monthly';

/// Mọi sản phẩm mở khoá bản Pro. Thêm gói năm hay gói trọn đời: tạo sản phẩm trên hai cửa hàng rồi thêm mã vào đây.
const proProducts = <String>{proMonthly};

/// Lỗi khi cửa hàng không trả lời được.
class BillingException implements Exception {
  const BillingException(this.message);
  final String message;
  @override
  String toString() => 'BillingException: $message';
}

/// Những gì [Billing] cần ở cửa hàng. Tách ra để test thay bằng bản giả.
abstract class BillingStore {
  /// Giao dịch mới, giao dịch đang chờ và giao dịch được khôi phục.
  Stream<List<PurchaseDetails>> get purchases;

  Future<bool> available();

  Future<List<ProductDetails>> products(Set<String> ids);

  /// Mở hộp thanh toán của cửa hàng. Kết quả về qua [purchases].
  Future<void> buy(ProductDetails product);

  /// Báo cho cửa hàng là app đã nhận giao dịch. Android: không báo trong 3 ngày thì Google tự hoàn tiền.
  Future<void> complete(PurchaseDetails purchase);

  /// Người dùng bấm "Khôi phục giao dịch": cửa hàng đồng bộ lại với tài khoản.
  Future<void> restore();

  /// Mã các sản phẩm đang còn hiệu lực: gói thuê bao chưa hết hạn, sản phẩm mua một lần.
  /// Ném lỗi nếu không hỏi được cửa hàng.
  Future<Set<String>> owned();
}

/// Cửa hàng thật trên máy: Google Play (Android) hoặc App Store qua StoreKit 2 (iOS 15 trở lên).
class DeviceStore implements BillingStore {
  final InAppPurchase _iap = InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchases => _iap.purchaseStream;

  @override
  Future<bool> available() => _iap.isAvailable();

  @override
  Future<List<ProductDetails>> products(Set<String> ids) async {
    final r = await _iap.queryProductDetails(ids);
    if (r.error != null && r.productDetails.isEmpty) throw BillingException(r.error!.message);
    return r.productDetails;
  }

  @override
  Future<void> buy(ProductDetails product) =>
      // Gói thuê bao cũng mua bằng buyNonConsumable; Android tự lấy offerToken của gói cơ sở từ productDetails.
      _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));

  @override
  Future<void> complete(PurchaseDetails purchase) => _iap.completePurchase(purchase);

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<Set<String>> owned() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Google Play chỉ trả về giao dịch còn hiệu lực: gói đã hết hạn hoặc đã hoàn tiền không còn trong danh sách.
      final r = await _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>().queryPastPurchases();
      if (r.error != null) throw BillingException(r.error!.message);
      final ids = <String>{};
      for (final p in r.pastPurchases) {
        // Giao dịch còn chờ trả tiền (pending) thì chưa tính.
        if (p.billingClientPurchase.purchaseState != PurchaseStateWrapper.purchased) continue;
        ids.add(p.productID);
        // App bị tắt trước khi kịp xác nhận: xác nhận nốt, không thì Google hoàn tiền.
        if (!p.billingClientPurchase.isAcknowledged) await _iap.completePurchase(p);
      }
      return ids;
    }
    // StoreKit 2: Transaction.currentEntitlements chỉ gồm gói còn hạn và sản phẩm mua một lần chưa bị thu hồi.
    return {for (final t in await SK2Transaction.currentEntitlements()) t.productId};
  }
}

/// Thông báo gần nhất để màn hình nâng cấp hiện cho người dùng.
enum BillingNotice { unlocked, pending, failed, restored, nothingToRestore }

/// Trạng thái mua bán của app: danh sách gói, mua, khôi phục, và quyền Pro.
class Billing extends ChangeNotifier {
  Billing({required this.store, required this.isPro, required this.setPro});

  /// Cửa hàng của nền tảng đang chạy; `null` trên nền tảng không bán trong app (web).
  static BillingStore? platformStore() {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) { TargetPlatform.android || TargetPlatform.iOS => DeviceStore(), _ => null };
  }

  final BillingStore? store;

  /// Đọc và ghi bản lưu tạm của quyền Pro (Store).
  final bool Function() isPro;
  final Future<void> Function(bool) setPro;

  /// Nền tảng này có bán trong app không.
  bool get supported => store != null;

  /// Các gói lấy được từ cửa hàng, giá đã theo tiền tệ của người dùng.
  List<ProductDetails> products = const [];

  /// Đang tải danh sách gói.
  bool loading = false;

  /// Lần tải gần nhất không lấy được gói (mất mạng, cửa hàng không dùng được, chưa tạo sản phẩm).
  bool loadFailed = false;

  /// Đang chờ cửa hàng xử lý lệnh mua hoặc khôi phục.
  bool busy = false;

  BillingNotice? notice;

  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Gọi một lần khi mở app: nghe giao dịch và hỏi lại cửa hàng quyền Pro.
  Future<void> start() async {
    final s = store;
    if (s == null || _sub != null) return;
    _sub = s.purchases.listen(_onPurchases, onError: (Object _) {});
    await refresh();
  }

  /// Hỏi cửa hàng gói nào còn hiệu lực rồi cập nhật quyền Pro. Không hỏi được thì giữ nguyên bản lưu tạm.
  Future<void> refresh() async {
    final s = store;
    if (s == null) return;
    final Set<String> owned;
    try {
      owned = await s.owned();
    } catch (_) {
      return;
    }
    await _setPro(owned.any(proProducts.contains));
  }

  /// Tải danh sách gói để hiện ở màn hình nâng cấp.
  Future<void> loadProducts() async {
    final s = store;
    if (s == null || loading) return;
    loading = true;
    loadFailed = false;
    notifyListeners();
    try {
      if (await s.available()) {
        products = (await s.products(proProducts)).where((p) => proProducts.contains(p.id)).toList();
      } else {
        products = const [];
      }
    } catch (_) {
      products = const [];
    }
    loadFailed = products.isEmpty;
    loading = false;
    notifyListeners();
  }

  Future<void> buy(ProductDetails product) async {
    final s = store;
    if (s == null || busy) return;
    busy = true;
    notice = null;
    notifyListeners();
    try {
      await s.buy(product);
    } catch (_) {
      notice = BillingNotice.failed;
    }
    busy = false;
    notifyListeners();
  }

  /// Người dùng bấm "Khôi phục giao dịch" (đổi máy, cài lại app).
  Future<void> restore() async {
    final s = store;
    if (s == null || busy) return;
    busy = true;
    notice = null;
    notifyListeners();
    try {
      await s.restore();
      final owned = await s.owned();
      await _setPro(owned.any(proProducts.contains));
      notice = isPro() ? BillingNotice.restored : BillingNotice.nothingToRestore;
    } catch (_) {
      notice = BillingNotice.failed;
    }
    busy = false;
    notifyListeners();
  }

  void clearNotice() => notice = null;

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    final s = store!;
    var proEvent = false, boughtNow = false;
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.pending:
          notice = BillingNotice.pending;
        case PurchaseStatus.error:
          notice = BillingNotice.failed;
        case PurchaseStatus.canceled:
          break;
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          if (proProducts.contains(p.productID)) {
            proEvent = true;
            boughtNow |= p.status == PurchaseStatus.purchased;
          }
      }
      if (p.pendingCompletePurchase) {
        try {
          await s.complete(p);
        } catch (_) {
          // Lần mở app sau cửa hàng sẽ gửi lại giao dịch chưa xác nhận.
        }
      }
    }
    if (proEvent) {
      // Không bật Pro chỉ vì có sự kiện: trên iOS, gia hạn và cả hoàn tiền cũng về qua luồng này dưới dạng "purchased".
      // Hỏi lại cửa hàng gói nào đang còn hiệu lực; không hỏi được thì tin giao dịch vừa nhận.
      bool active;
      try {
        active = (await s.owned()).any(proProducts.contains);
      } catch (_) {
        active = true;
      }
      final had = isPro();
      await _setPro(active);
      if (active && !had && boughtNow) notice = BillingNotice.unlocked;
    }
    notifyListeners();
  }

  Future<void> _setPro(bool v) async {
    if (isPro() == v) return;
    await setPro(v);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
