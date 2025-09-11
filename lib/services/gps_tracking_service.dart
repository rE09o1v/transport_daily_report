import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_daily_report/services/background_service.dart'; // For SharedPreferences keys

/// GPS追跡サービス（コントローラー）
///
/// UIとバックグラウンドサービス間の通信を仲介する。
/// 実際の追跡ロジックはバックグラウンドサービスが担当する。
class GPSTrackingService {
  // SharedPreferencesのキー定数
  static const String distanceKey = 'gps_current_distance';
  static const String startMileageKey = 'start_mileage';
  static const String lastPositionKeyLat = 'last_position_lat';
  static const String lastPositionKeyLon = 'last_position_lon';
  static final GPSTrackingService _instance = GPSTrackingService._internal();
  factory GPSTrackingService() => _instance;

  final FlutterBackgroundService _service = FlutterBackgroundService();
  
  // UIにリアルタイムの距離を通知するためのValueNotifier
  final ValueNotifier<double> currentDistance = ValueNotifier(0.0);
  
  // サービスが実行中かどうかを管理するValueNotifier
  final ValueNotifier<bool> isTrackingNotifier = ValueNotifier(false);

  GPSTrackingService._internal() {
    // バックグラウンドサービスからの更新をリッスン
    _service.on('update').listen((event) {
      if (event != null && event['current_distance'] != null) {
        final distance = event['current_distance'] as double;
        currentDistance.value = distance;
      }
    });

    // サービスの実行状態をポーリングして確認
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      final isRunning = await _service.isRunning();
      if (isTrackingNotifier.value != isRunning) {
        isTrackingNotifier.value = isRunning;
        // サービスが停止していたら、最後の距離をSharedPreferencesから読み込む
        if (!isRunning) {
          final prefs = await SharedPreferences.getInstance();
          currentDistance.value = prefs.getDouble(distanceKey) ?? 0.0;
        }
      }
    });
  }

  /// GPS追跡開始
  Future<void> startTracking({
    required double startMileage,
  }) async {
    try {
      final isRunning = await _service.isRunning();
      if (isRunning) {
        // 既に実行中の場合は何もしない
        if (kDebugMode) {
          print('Background service is already running.');
        }
        return;
      }

      // SharedPreferencesをリセット
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(distanceKey, 0.0);
      await prefs.remove(lastPositionKeyLat);
      await prefs.remove(lastPositionKeyLon);
      await prefs.setDouble(startMileageKey, startMileage);
      
      // サービスを開始
      await _service.startService();
      
      // 開始コマンドを送信
      _service.invoke('startTracking', {'start_mileage': startMileage});

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
      final isRunning = await _service.isRunning();
      if (!isRunning) return;

      _service.invoke('stopService');
      isTrackingNotifier.value = false;

      // 最終的な距離をSharedPreferencesから読み込む
      final prefs = await SharedPreferences.getInstance();
      currentDistance.value = prefs.getDouble(distanceKey) ?? 0.0;

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
    // ValueNotifierはシングルトンのため、通常はdisposeしない
  }
}

/// GPS追跡例外
class GPSTrackingException implements Exception {
  final String message;
  const GPSTrackingException(this.message);

  @override
  String toString() => 'GPSTrackingException: $message';
}