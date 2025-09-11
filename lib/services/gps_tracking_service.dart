import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/mileage_record.dart';
import 'storage_service.dart';

/// GPS追跡サービス
/// 
/// バックグラウンドでGPS位置情報を記録し、走行距離を計算する
/// 業務開始から終了まで継続的に動作
class GPSTrackingService {
  static final GPSTrackingService _instance = GPSTrackingService._internal();
  factory GPSTrackingService() => _instance;
  GPSTrackingService._internal();

  final StorageService _storageService = StorageService();
  
  StreamSubscription<Position>? _positionSubscription;
  GPSTrackingRecord? _currentTracking;
  
  Timer? _qualityCheckTimer;
  Timer? _saveTimer;
  
  // GPS設定
  static const LocationSettings _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10, // 10m移動で更新
    timeLimit: Duration(seconds: 30),
  );
  
  // 品質メトリクス閾値
  static const double _minAccuracy = 20.0; // 20m以下の精度を要求
  static const int _qualityWindowSeconds = 300; // 5分間のサンプリング
  
  /// GPS追跡開始
  Future<String> startTracking({
    required String rollCallId,
    required double startMileage,
  }) async {
    try {
      // 権限確認
      bool hasPermission = await _checkLocationPermission();
      if (!hasPermission) {
        throw GPSTrackingException('位置情報の権限が必要です');
      }
      
      // GPS利用可能性確認
      bool isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        throw GPSTrackingException('位置情報サービスが無効です');
      }
      
      // 既存の追跡を停止
      await stopTracking();
      
      // 初期位置取得
      Position initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: _locationSettings,
      );
      
      // 新しい追跡記録を作成
      _currentTracking = GPSTrackingRecord(
        trackingId: _generateTrackingId(),
        startTime: DateTime.now(),
        totalDistance: 0.0,
        isComplete: false,
        qualityMetrics: GPSQualityMetrics(
          accuracyPercentage: 100.0,
          signalQuality: 1.0,
          batteryImpact: 0.1,
          totalLocationPoints: 1,
          validLocationPoints: 1,
        ),
        locationPoints: [
          LocationPoint(
            latitude: initialPosition.latitude,
            longitude: initialPosition.longitude,
            accuracy: initialPosition.accuracy,
            timestamp: DateTime.now(),
          ),
        ],
      );
      
      // 位置追跡開始
      _startLocationTracking();
      
      // 品質チェック開始
      _startQualityCheck();
      
      // 定期保存開始
      _startPeriodicSave();
      
      // 初期保存（StorageServiceへの保存は後で実装）
      // await _storageService.saveGPSTrackingRecord(_currentTracking!);
      
      if (kDebugMode) {
        print('GPS追跡開始: ${_currentTracking!.trackingId}');
      }
      
      return _currentTracking!.trackingId;
      
    } catch (e) {
      throw GPSTrackingException('GPS追跡開始に失敗しました: $e');
    }
  }
  
  /// GPS追跡停止
  Future<GPSTrackingRecord?> stopTracking({double? endMileage}) async {
    if (_currentTracking == null || _currentTracking!.isComplete) {
      return null;
    }
    
    try {
      // 最終位置取得
      Position? finalPosition;
      try {
        finalPosition = await Geolocator.getCurrentPosition(
          locationSettings: _locationSettings,
        ).timeout(const Duration(seconds: 10));
      } catch (e) {
        if (kDebugMode) {
          print('最終位置取得に失敗: $e');
        }
      }
      
      // 追跡記録を終了
      final finalLocationPoints = List<LocationPoint>.from(_currentTracking!.locationPoints);
      if (finalPosition != null) {
        finalLocationPoints.add(LocationPoint(
          latitude: finalPosition.latitude,
          longitude: finalPosition.longitude,
          accuracy: finalPosition.accuracy,
          timestamp: DateTime.now(),
        ));
      }
      
      _currentTracking = _currentTracking!.copyWith(
        endTime: DateTime.now(),
        totalDistance: _calculateTotalDistance(),
        isComplete: true,
        locationPoints: finalLocationPoints,
      );
      
      // タイマー停止
      _positionSubscription?.cancel();
      _qualityCheckTimer?.cancel();
      _saveTimer?.cancel();
      
      // 最終保存（後で実装）
      // await _storageService.saveGPSTrackingRecord(_currentTracking!);
      
      if (kDebugMode) {
        print('GPS追跡終了: ${_currentTracking!.trackingId}, 距離: ${_currentTracking!.totalDistance.toStringAsFixed(1)}km');
      }
      
      GPSTrackingRecord result = _currentTracking!;
      _currentTracking = null;
      
      return result;
      
    } catch (e) {
      throw GPSTrackingException('GPS追跡停止に失敗しました: $e');
    }
  }
  
  /// 位置追跡開始
  void _startLocationTracking() {
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _locationSettings,
    ).listen(
      _onPositionUpdate,
      onError: (error) {
        if (kDebugMode) {
          print('GPS位置取得エラー: $error');
        }
        // エラー時の品質メトリクス更新は省略
      },
    );
  }
  
  /// 位置更新処理
  void _onPositionUpdate(Position position) {
    if (_currentTracking == null || _currentTracking!.isComplete) return;
    
    final locationPoint = LocationPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestamp: DateTime.now(),
    );
    
    // 位置を記録に追加
    List<LocationPoint> updatedLocations = List.from(_currentTracking!.locationPoints);
    updatedLocations.add(locationPoint);
    
    // 品質メトリクス更新
    final updatedMetrics = _updateQualityMetrics(
      currentMetrics: _currentTracking!.qualityMetrics,
      accuracy: position.accuracy,
      hasError: false,
    );
    
    _currentTracking = _currentTracking!.copyWith(
      locationPoints: updatedLocations,
      totalDistance: _calculateTotalDistance(),
      qualityMetrics: updatedMetrics,
    );
    
    if (kDebugMode) {
      print('位置更新: (${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}) 精度: ${position.accuracy.toStringAsFixed(1)}m');
    }
  }
  
  /// 品質メトリクス更新
  GPSQualityMetrics _updateQualityMetrics({
    required GPSQualityMetrics currentMetrics,
    double? accuracy,
    bool hasError = false,
  }) {
    final totalPoints = currentMetrics.totalLocationPoints + 1;
    final validPoints = hasError ? currentMetrics.validLocationPoints : 
                                  currentMetrics.validLocationPoints + 1;
    
    // 精度パーセンテージ計算
    double accuracyPercentage = 100.0;
    if (accuracy != null && accuracy > 0) {
      accuracyPercentage = math.max(0.0, 100.0 - (accuracy / 50.0 * 100.0));
    }
    
    // シグナル品質計算（エラー率から算出）
    final errorRate = totalPoints > 0 ? (totalPoints - validPoints) / totalPoints : 0.0;
    final signalQuality = math.max(0.0, 1.0 - errorRate);
    
    return GPSQualityMetrics(
      accuracyPercentage: accuracyPercentage,
      signalQuality: signalQuality,
      batteryImpact: 0.2, // 固定値（実際には使用時間などから算出）
      totalLocationPoints: totalPoints,
      validLocationPoints: validPoints,
    );
  }
  
  /// 品質チェック開始
  void _startQualityCheck() {
    _qualityCheckTimer = Timer.periodic(
      Duration(seconds: _qualityWindowSeconds),
      (_) => _performQualityCheck(),
    );
  }
  
  /// 品質チェック実行
  void _performQualityCheck() {
    if (_currentTracking == null) return;
    
    GPSQualityMetrics metrics = _currentTracking!.qualityMetrics;
    
    // エラー率計算
    double errorRate = metrics.totalLocationPoints > 0 ? 
                      (metrics.totalLocationPoints - metrics.validLocationPoints) / metrics.totalLocationPoints : 0.0;
    
    // 良好率計算（精度パーセンテージから）
    double goodRate = metrics.accuracyPercentage / 100.0;
    
    if (kDebugMode) {
      print('GPS品質チェック - エラー率: ${(errorRate * 100).toStringAsFixed(1)}%, 精度: ${metrics.accuracyPercentage.toStringAsFixed(1)}%, シグナル: ${(metrics.signalQuality * 100).toStringAsFixed(1)}%');
    }
    
    // 品質が悪い場合の警告
    if (errorRate > 0.3 || metrics.accuracyPercentage < 50) {
      if (kDebugMode) {
        print('GPS品質警告: 測定精度が低下しています');
      }
    }
  }
  
  /// 定期保存開始
  void _startPeriodicSave() {
    _saveTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _performPeriodicSave(),
    );
  }
  
  /// 定期保存実行
  Future<void> _performPeriodicSave() async {
    if (_currentTracking == null) return;
    
    try {
      // await _storageService.saveGPSTrackingRecord(_currentTracking!);
      if (kDebugMode) {
        print('GPS追跡データ自動保存完了（スキップ）');
      }
    } catch (e) {
      if (kDebugMode) {
        print('GPS追跡データ保存エラー: $e');
      }
    }
  }
  
  /// 総距離計算
  double _calculateTotalDistance() {
    if (_currentTracking == null || _currentTracking!.locationPoints.length < 2) {
      return 0.0;
    }
    
    double totalDistance = 0.0;
    List<LocationPoint> locations = _currentTracking!.locationPoints;
    
    for (int i = 1; i < locations.length; i++) {
      double distance = _calculateDistanceBetweenPoints(
        locations[i-1],
        locations[i],
      );
      
      // 異常な距離値をフィルタリング（時速200km以上の移動は除外）
      double timeDiff = locations[i].timestamp.difference(locations[i-1].timestamp).inSeconds.toDouble();
      if (timeDiff > 0) {
        double speed = (distance * 1000) / timeDiff; // m/s
        double speedKmh = speed * 3.6; // km/h
        
        if (speedKmh <= 200) {
          totalDistance += distance;
        }
      }
    }
    
    return totalDistance;
  }
  
  /// 2点間の距離計算（Haversineの公式）
  double _calculateDistanceBetweenPoints(LocationPoint point1, LocationPoint point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    ) / 1000.0; // メートルをキロメートルに変換
  }
  
  /// 位置情報権限確認
  Future<bool> _checkLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    return permission != LocationPermission.denied && 
           permission != LocationPermission.deniedForever;
  }
  
  /// 追跡ID生成
  String _generateTrackingId() {
    return 'gps_${DateTime.now().millisecondsSinceEpoch}';
  }
  
  /// 現在の追跡状態取得
  GPSTrackingRecord? get currentTracking => _currentTracking;
  
  /// 追跡中かどうか
  bool get isTracking => _currentTracking != null && !_currentTracking!.isComplete;
  
  /// リアルタイム距離取得
  double get currentDistance => _currentTracking?.totalDistance ?? 0.0;
  
  /// GPS品質取得
  GPSQualityMetrics? get currentQuality => _currentTracking?.qualityMetrics;
  
  /// 追跡記録取得
  Future<List<GPSTrackingRecord>> getTrackingHistory({
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    // StorageService未実装のため一時的に空リストを返す
    // return await _storageService.getGPSTrackingRecords(
    //   fromDate: fromDate,
    //   toDate: toDate,
    // );
    return [];
  }
  
  /// リソース解放
  void dispose() {
    _positionSubscription?.cancel();
    _qualityCheckTimer?.cancel();
    _saveTimer?.cancel();
    _currentTracking = null;
  }
}

/// GPS追跡例外
class GPSTrackingException implements Exception {
  final String message;
  const GPSTrackingException(this.message);
  
  @override
  String toString() => 'GPSTrackingException: $message';
}