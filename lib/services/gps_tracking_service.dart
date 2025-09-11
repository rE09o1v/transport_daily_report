import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_daily_report/services/location_service.dart';

/// GPS追跡サービス（コントローラー）
///
/// LocationServiceを使用したシンプルなGPS追跡機能。
/// 点呼記録画面での始業〜終業間の移動距離計測を担当する。
class GPSTrackingService {
  // SharedPreferencesのキー定数
  static const String distanceKey = 'gps_current_distance';
  static const String startMileageKey = 'start_mileage';
  static final GPSTrackingService _instance = GPSTrackingService._internal();
  factory GPSTrackingService() => _instance;

  final LocationService _locationService = LocationService();
  StreamSubscription<double>? _distanceSubscription;
  
  // UIにリアルタイムの距離を通知するためのValueNotifier
  final ValueNotifier<double> currentDistance = ValueNotifier(0.0);
  
  // サービスが実行中かどうかを管理するValueNotifier
  final ValueNotifier<bool> isTrackingNotifier = ValueNotifier(false);

  double _startMileage = 0.0;

  GPSTrackingService._internal() {
    // LocationServiceからの距離更新をリッスン
    _distanceSubscription = _locationService.distanceStream.listen((distance) {
      currentDistance.value = distance / 1000; // メートルをキロメートルに変換
      _saveDistanceToPrefs(distance / 1000);
    });
  }

  // 距離をSharedPreferencesに保存
  Future<void> _saveDistanceToPrefs(double distance) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(distanceKey, distance);
  }

  /// GPS追跡開始
  Future<void> startTracking({
    required double startMileage,
  }) async {
    try {
      if (isTrackingNotifier.value) {
        // 既に追跡中の場合は何もしない
        if (kDebugMode) {
          print('GPS tracking is already running.');
        }
        return;
      }

      // 開始前の初期化
      _startMileage = startMileage;
      currentDistance.value = 0.0;
      
      // SharedPreferencesをリセット
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(distanceKey, 0.0);
      await prefs.setDouble(startMileageKey, startMileage);
      
      // LocationServiceでGPS追跡を開始
      final success = await _locationService.startDistanceTracking();
      if (!success) {
        throw GPSTrackingException('位置情報の許可が必要です');
      }

      isTrackingNotifier.value = true;
      if (kDebugMode) {
        print('GPS追跡サービス開始');
      }
    } catch (e) {
      if (kDebugMode) {
        print('GPS追跡開始に失敗しました: $e');
      }
      throw GPSTrackingException('GPS追跡開始に失敗しました: $e');
    }
  }

  /// GPS追跡停止
  Future<void> stopTracking() async {
    try {
      if (!isTrackingNotifier.value) return;

      // LocationServiceのGPS追跡を停止
      await _locationService.stopDistanceTracking();
      isTrackingNotifier.value = false;

      // 最終的な距離を取得・保存
      final finalDistance = _locationService.totalDistance / 1000; // キロメートル単位
      currentDistance.value = finalDistance;
      await _saveDistanceToPrefs(finalDistance);

      if (kDebugMode) {
        print('GPS追跡サービス停止, 最終距離: ${currentDistance.value.toStringAsFixed(2)}km');
      }
    } catch (e) {
      if (kDebugMode) {
        print('GPS追跡停止に失敗しました: $e');
      }
      throw GPSTrackingException('GPS追跡停止に失敗しました: $e');
    }
  }

  /// 追跡中かどうか
  bool get isTracking => isTrackingNotifier.value;

  /// リソース解放
  void dispose() {
    _distanceSubscription?.cancel();
    _locationService.dispose();
  }
}

/// GPS追跡例外
class GPSTrackingException implements Exception {
  final String message;
  const GPSTrackingException(this.message);

  @override
  String toString() => 'GPSTrackingException: $message';
}