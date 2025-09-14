import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

/// バッテリー最適化サービス
/// 
/// 長時間のGPS記録時のバッテリー消費を最適化する機能を提供
/// - バッテリー残量監視
/// - 記録間隔の動的調整
/// - 省電力モード選択肢
/// - 速度に応じた記録間隔最適化
class BatteryOptimizationService {
  static const String _powerModeKey = 'gps_power_mode';
  static const String _batteryThresholdKey = 'battery_threshold';
  static const String _adaptiveIntervalKey = 'adaptive_interval_enabled';
  
  // 省電力モード
  static const PowerMode _defaultPowerMode = PowerMode.balanced;
  static const int _defaultBatteryThreshold = 20; // 20%以下で省電力モード
  static const bool _defaultAdaptiveInterval = true;

  // 記録間隔設定（秒）
  static const Map<PowerMode, int> _baseIntervals = {
    PowerMode.highAccuracy: 5,    // 高精度：5秒間隔
    PowerMode.balanced: 15,       // バランス：15秒間隔
    PowerMode.powerSaver: 30,     // 省電力：30秒間隔
  };

  // シングルトンパターン
  static final BatteryOptimizationService _instance = BatteryOptimizationService._internal();
  factory BatteryOptimizationService() => _instance;
  BatteryOptimizationService._internal();

  // 設定値
  PowerMode _currentPowerMode = _defaultPowerMode;
  int _batteryThreshold = _defaultBatteryThreshold;
  bool _adaptiveIntervalEnabled = _defaultAdaptiveInterval;
  
  // 監視状態
  Timer? _batteryMonitorTimer;
  final ValueNotifier<BatteryStatus> _batteryStatusNotifier = ValueNotifier(
    BatteryStatus(
      level: 100,
      isCharging: false,
      powerMode: _defaultPowerMode,
    ),
  );
  
  // バッテリー統計
  final ValueNotifier<BatteryStats> _batteryStatsNotifier = ValueNotifier(
    BatteryStats(),
  );

  /// バッテリー状態の通知用ValueNotifier
  ValueNotifier<BatteryStatus> get batteryStatusNotifier => _batteryStatusNotifier;
  
  /// バッテリー統計の通知用ValueNotifier
  ValueNotifier<BatteryStats> get batteryStatsNotifier => _batteryStatsNotifier;

  /// 初期化
  Future<void> initialize() async {
    AppLogger.info('BatteryOptimizationService初期化開始', 'BatteryOptimizationService');
    
    try {
      await _loadSettings();
      await _startBatteryMonitoring();
      
      AppLogger.info('BatteryOptimizationService初期化完了', 'BatteryOptimizationService');
    } catch (e) {
      AppLogger.error('BatteryOptimizationService初期化エラー', 'BatteryOptimizationService', e);
      rethrow;
    }
  }

  /// 設定を読み込み
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    _currentPowerMode = PowerMode.values[prefs.getInt(_powerModeKey) ?? _defaultPowerMode.index];
    _batteryThreshold = prefs.getInt(_batteryThresholdKey) ?? _defaultBatteryThreshold;
    _adaptiveIntervalEnabled = prefs.getBool(_adaptiveIntervalKey) ?? _defaultAdaptiveInterval;
    
    AppLogger.info('バッテリー設定読み込み完了: PowerMode=${_currentPowerMode.name}, Threshold=$_batteryThreshold%', 'BatteryOptimizationService');
  }

  /// バッテリー監視開始
  Future<void> _startBatteryMonitoring() async {
    // バッテリー監視タイマーを開始（30秒間隔）
    _batteryMonitorTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _updateBatteryStatus();
    });
    
    // 初回実行
    await _updateBatteryStatus();
  }

  /// バッテリー状態更新
  Future<void> _updateBatteryStatus() async {
    try {
      // プラットフォームごとのバッテリー取得実装は簡略化
      // 実際の実装では battery_plus パッケージなどを使用
      final batteryLevel = await _getBatteryLevel();
      final isCharging = await _getBatteryChargingStatus();
      
      // 省電力モード判定
      PowerMode effectivePowerMode = _currentPowerMode;
      if (batteryLevel <= _batteryThreshold && !isCharging) {
        effectivePowerMode = PowerMode.powerSaver;
        AppLogger.warning('バッテリー残量低下により省電力モードに切り替え: $batteryLevel%', 'BatteryOptimizationService');
      }
      
      final batteryStatus = BatteryStatus(
        level: batteryLevel,
        isCharging: isCharging,
        powerMode: effectivePowerMode,
      );
      
      _batteryStatusNotifier.value = batteryStatus;
      
      // 統計更新
      _updateBatteryStats(batteryLevel, effectivePowerMode);
      
    } catch (e) {
      AppLogger.error('バッテリー状態更新エラー', 'BatteryOptimizationService', e);
    }
  }

  /// プラットフォーム固有：バッテリー残量取得（簡易実装）
  Future<int> _getBatteryLevel() async {
    // 実際の実装では battery_plus パッケージを使用
    // ここでは簡易的にランダム値を返す（デモ用）
    if (kDebugMode) {
      return 85; // デバッグ時は固定値
    }
    return 100; // 本番時は満充電と仮定
  }

  /// プラットフォーム固有：充電状態取得（簡易実装）
  Future<bool> _getBatteryChargingStatus() async {
    // 実際の実装では battery_plus パッケージを使用
    return false; // 簡易的にfalse
  }

  /// バッテリー統計更新
  void _updateBatteryStats(int batteryLevel, PowerMode powerMode) {
    final currentStats = _batteryStatsNotifier.value;
    final now = DateTime.now();
    
    // 1時間あたりの消費量計算（簡易）
    final timeDiff = currentStats.lastUpdateTime != null
        ? now.difference(currentStats.lastUpdateTime!).inMinutes
        : 0;
    
    double consumptionRate = 0.0;
    if (timeDiff > 0 && currentStats.lastBatteryLevel != null) {
      final consumption = currentStats.lastBatteryLevel! - batteryLevel;
      consumptionRate = (consumption / timeDiff) * 60; // 1時間あたりの消費率
    }
    
    final updatedStats = currentStats.copyWith(
      lastBatteryLevel: batteryLevel,
      lastUpdateTime: now,
      consumptionRatePerHour: consumptionRate,
      totalGpsTime: currentStats.totalGpsTime + (timeDiff > 0 ? timeDiff : 0),
    );
    
    _batteryStatsNotifier.value = updatedStats;
  }

  /// 現在の記録間隔を取得（動的調整考慮）
  int getOptimalTrackingInterval({double? currentSpeed}) {
    final basePowerMode = _batteryStatusNotifier.value.powerMode;
    int baseInterval = _baseIntervals[basePowerMode] ?? _baseIntervals[PowerMode.balanced]!;
    
    if (!_adaptiveIntervalEnabled || currentSpeed == null) {
      return baseInterval;
    }
    
    // 速度に応じた間隔調整
    // 低速時（5km/h以下）：間隔を2倍に
    // 高速時（60km/h以上）：間隔を半分に
    if (currentSpeed <= 5.0) {
      return (baseInterval * 2).clamp(10, 120); // 最大2分
    } else if (currentSpeed >= 60.0) {
      return (baseInterval ~/ 2).clamp(3, 30); // 最小3秒
    }
    
    return baseInterval;
  }

  /// 省電力モード設定
  Future<void> setPowerMode(PowerMode mode) async {
    if (_currentPowerMode == mode) return;
    
    _currentPowerMode = mode;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_powerModeKey, mode.index);
      
      AppLogger.info('省電力モード変更: ${mode.name}', 'BatteryOptimizationService');
      
      // 即座にバッテリー状態を更新
      await _updateBatteryStatus();
    } catch (e) {
      AppLogger.error('省電力モード設定エラー', 'BatteryOptimizationService', e);
    }
  }

  /// バッテリー閾値設定
  Future<void> setBatteryThreshold(int threshold) async {
    if (threshold < 5 || threshold > 50) {
      throw ArgumentError('バッテリー閾値は5%〜50%の範囲で設定してください');
    }
    
    _batteryThreshold = threshold;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_batteryThresholdKey, threshold);
      
      AppLogger.info('バッテリー閾値変更: $threshold%', 'BatteryOptimizationService');
    } catch (e) {
      AppLogger.error('バッテリー閾値設定エラー', 'BatteryOptimizationService', e);
    }
  }

  /// 適応的間隔調整の有効/無効設定
  Future<void> setAdaptiveIntervalEnabled(bool enabled) async {
    _adaptiveIntervalEnabled = enabled;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_adaptiveIntervalKey, enabled);
      
      AppLogger.info('適応的間隔調整: ${enabled ? '有効' : '無効'}', 'BatteryOptimizationService');
    } catch (e) {
      AppLogger.error('適応的間隔調整設定エラー', 'BatteryOptimizationService', e);
    }
  }

  /// 現在の設定を取得
  BatteryOptimizationConfig getCurrentConfig() {
    return BatteryOptimizationConfig(
      powerMode: _currentPowerMode,
      batteryThreshold: _batteryThreshold,
      adaptiveIntervalEnabled: _adaptiveIntervalEnabled,
    );
  }

  /// GPS記録開始時の最適化設定適用
  Future<OptimizationRecommendation> getStartTrackingRecommendation() async {
    await _updateBatteryStatus();
    
    final batteryStatus = _batteryStatusNotifier.value;
    final recommendations = <String>[];
    PowerMode recommendedMode = _currentPowerMode;
    
    // バッテリー残量に基づく推奨
    if (batteryStatus.level <= _batteryThreshold) {
      recommendations.add('バッテリー残量が少ないため、省電力モードを推奨します');
      recommendedMode = PowerMode.powerSaver;
    } else if (batteryStatus.level <= 50) {
      recommendations.add('バランスモードでの記録を推奨します');
      recommendedMode = PowerMode.balanced;
    }
    
    // 充電状態に基づく推奨
    if (batteryStatus.isCharging) {
      recommendations.add('充電中のため、高精度モードも利用可能です');
    } else {
      recommendations.add('充電器の使用を推奨します');
    }
    
    return OptimizationRecommendation(
      recommendedPowerMode: recommendedMode,
      recommendations: recommendations,
      estimatedTrackingTime: _estimateTrackingTime(batteryStatus.level, recommendedMode),
    );
  }

  /// 記録可能時間予測
  Duration _estimateTrackingTime(int batteryLevel, PowerMode mode) {
    // モード別消費率（%/時間）の概算
    const consumptionRates = {
      PowerMode.highAccuracy: 8.0,   // 高精度：8%/時間
      PowerMode.balanced: 5.0,       // バランス：5%/時間
      PowerMode.powerSaver: 3.0,     // 省電力：3%/時間
    };
    
    final rate = consumptionRates[mode] ?? 5.0;
    final availableBattery = (batteryLevel - 10).clamp(0, 100); // 10%は予備
    final hours = availableBattery / rate;
    
    return Duration(hours: hours.floor(), minutes: ((hours % 1) * 60).floor());
  }

  /// リソース解放
  void dispose() {
    _batteryMonitorTimer?.cancel();
    _batteryStatusNotifier.dispose();
    _batteryStatsNotifier.dispose();
    AppLogger.info('BatteryOptimizationService disposed', 'BatteryOptimizationService');
  }
}

// ============ データクラス ============

/// 省電力モード
enum PowerMode {
  highAccuracy, // 高精度
  balanced,     // バランス
  powerSaver,   // 省電力
}

/// バッテリー状態
class BatteryStatus {
  final int level;               // バッテリー残量（%）
  final bool isCharging;         // 充電中かどうか
  final PowerMode powerMode;     // 現在の省電力モード

  BatteryStatus({
    required this.level,
    required this.isCharging,
    required this.powerMode,
  });

  BatteryStatus copyWith({
    int? level,
    bool? isCharging,
    PowerMode? powerMode,
  }) {
    return BatteryStatus(
      level: level ?? this.level,
      isCharging: isCharging ?? this.isCharging,
      powerMode: powerMode ?? this.powerMode,
    );
  }
}

/// バッテリー統計情報
class BatteryStats {
  final int? lastBatteryLevel;           // 前回のバッテリー残量
  final DateTime? lastUpdateTime;        // 最終更新時刻
  final double consumptionRatePerHour;   // 1時間あたりの消費率（%）
  final int totalGpsTime;                // 総GPS記録時間（分）

  BatteryStats({
    this.lastBatteryLevel,
    this.lastUpdateTime,
    this.consumptionRatePerHour = 0.0,
    this.totalGpsTime = 0,
  });

  BatteryStats copyWith({
    int? lastBatteryLevel,
    DateTime? lastUpdateTime,
    double? consumptionRatePerHour,
    int? totalGpsTime,
  }) {
    return BatteryStats(
      lastBatteryLevel: lastBatteryLevel ?? this.lastBatteryLevel,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      consumptionRatePerHour: consumptionRatePerHour ?? this.consumptionRatePerHour,
      totalGpsTime: totalGpsTime ?? this.totalGpsTime,
    );
  }
}

/// バッテリー最適化設定
class BatteryOptimizationConfig {
  final PowerMode powerMode;
  final int batteryThreshold;
  final bool adaptiveIntervalEnabled;

  BatteryOptimizationConfig({
    required this.powerMode,
    required this.batteryThreshold,
    required this.adaptiveIntervalEnabled,
  });
}

/// 最適化推奨情報
class OptimizationRecommendation {
  final PowerMode recommendedPowerMode;
  final List<String> recommendations;
  final Duration estimatedTrackingTime;

  OptimizationRecommendation({
    required this.recommendedPowerMode,
    required this.recommendations,
    required this.estimatedTrackingTime,
  });
}