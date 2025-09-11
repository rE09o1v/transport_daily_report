import 'dart:async';
import 'dart:math';
import '../models/mileage_record.dart';
import '../models/roll_call_record.dart';
import '../utils/logger.dart';
import 'storage_service.dart';
import 'gps_tracking_service.dart';

/// メーター値の記録、検証、算出を担当するサービスクラス
/// 
/// 主な機能:
/// - 開始・終了メーター値の記録
/// - 走行距離の算出・検証
/// - 異常値検知（1000km/日超過、メーター逆転など）
/// - GPS記録との連携
/// - 監査ログの管理
class MileageService {
  final StorageService _storageService;
  final GPSTrackingService _gpsService;
  
  // 異常値判定の閾値
  static const double _maxDailyDistance = 1000.0; // 最大日走行距離 (km)
  static const double _minMileageValue = 0.0; // 最小メーター値
  static const double _maxMileageValue = 999999.0; // 最大メーター値（6桁まで）

  MileageService({
    StorageService? storageService,
    GPSTrackingService? gpsTrackingService,
  }) : _storageService = storageService ?? StorageService(),
       _gpsService = gpsTrackingService ?? GPSTrackingService();

  // ============ 開始メーター値記録 ============

  /// 始業点呼時のメーター値を記録
  /// 
  /// [mileage] メーター値 (km)
  /// [gpsEnabled] GPS記録を有効にするか
  /// [rollCallRecord] 対応する点呼記録
  /// 
  /// 戻り値: 作成されたMileageRecord
  Future<MileageRecord> recordStartMileage(
    double mileage, 
    bool gpsEnabled, {
    RollCallRecord? rollCallRecord,
  }) async {
    AppLogger.info('開始メーター値記録開始: $mileage km, GPS: $gpsEnabled', 'MileageService');
    
    try {
      // 入力値検証
      await _validateMileageValue(mileage);
      
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      // 既存の当日記録を確認
      final existingRecord = await _storageService.getMileageRecordByDate(today);
      
      MileageRecord record;
      
      if (existingRecord != null) {
        // 既存記録を更新
        record = existingRecord.copyWith(
          startMileage: mileage,
          source: gpsEnabled ? MileageSource.gps : MileageSource.manual,
          updatedAt: now,
        );
        
        await _storageService.updateMileageRecord(record);
        AppLogger.info('既存MileageRecord更新: ${record.id}', 'MileageService');
      } else {
        // 新規記録作成
        record = MileageRecord(
          id: MileageRecord.generateId(),
          date: today,
          startMileage: mileage,
          source: gpsEnabled ? MileageSource.gps : MileageSource.manual,
          createdAt: now,
          updatedAt: now,
        );
        
        await _storageService.addMileageRecord(record);
        AppLogger.info('新規MileageRecord作成: ${record.id}', 'MileageService');
      }
      
      // GPS追跡開始（有効な場合）
      String? gpsTrackingId;
      if (gpsEnabled) {
        try {
          gpsTrackingId = await _gpsService.startTracking(
            rollCallId: rollCallRecord?.id ?? record.id,
            startMileage: mileage,
          );
          
          // GPS追跡IDを記録に反映（trackingIdはGPSTrackingRecordに保存）
          // record = record.copyWith(gpsTrackingId: gpsTrackingId);
          // await _storageService.updateMileageRecord(record);
          
          AppLogger.info('GPS追跡開始: $gpsTrackingId', 'MileageService');
        } catch (e) {
          AppLogger.error('GPS追跡開始に失敗、手動モードに切り替え', 'MileageService', e);
          // GPS開始に失敗した場合は手動モードに切り替え
          record = record.copyWith(
            source: MileageSource.manual,
            // gpsError: 'GPS追跡開始エラー: $e', // MileageRecordにはgpsErrorフィールドなし
          );
          await _storageService.updateMileageRecord(record);
          rethrow; // エラーを上位に通知してUI側でハンドリング
        }
      }
      
      // 監査ログに記録
      await _logMileageAction(
        recordId: record.id,
        action: AuditAction.create,
        newValue: mileage,
        reason: '開始メーター値記録',
        // metadata: {
        //   'gps_enabled': gpsEnabled,
        //   'gps_tracking_id': gpsTrackingId,
        // },
      );
      
      // 点呼記録を更新（提供された場合）
      if (rollCallRecord != null) {
        final updatedRollCall = rollCallRecord.copyWith(
          startMileage: mileage,
          gpsTrackingEnabled: gpsEnabled,
          gpsTrackingId: gpsTrackingId,
        );
        
        await _storageService.updateRollCallRecord(updatedRollCall);
      }
      
      AppLogger.info('開始メーター値記録完了: ${record.id}', 'MileageService');
      return record;
      
    } catch (e) {
      AppLogger.error('開始メーター値記録中にエラー', 'MileageService', e);
      rethrow;
    }
  }

  // ============ 終了メーター値記録 ============

  /// 終業点呼時のメーター値を記録
  /// 
  /// [mileage] メーター値 (km)
  /// [source] 記録方法（手動・GPS・ハイブリッド）
  /// [gpsDistance] GPS算出距離（GPS使用時）
  /// [rollCallRecord] 対応する点呼記録
  /// 
  /// 戻り値: 更新されたMileageRecord
  Future<MileageRecord> recordEndMileage(
    double mileage, 
    MileageSource source, {
    double? gpsDistance,
    RollCallRecord? rollCallRecord,
  }) async {
    AppLogger.info('終了メーター値記録開始: $mileage km, Source: ${source.name}', 'MileageService');
    
    try {
      // 入力値検証
      await _validateMileageValue(mileage);
      
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      // 開始記録を取得
      final existingRecord = await _storageService.getMileageRecordByDate(today);
      if (existingRecord == null) {
        throw Exception('開始メーター値が記録されていません');
      }
      
      // 走行距離を算出
      double distance;
      if (source == MileageSource.gps && gpsDistance != null) {
        distance = gpsDistance;
      } else {
        distance = mileage - existingRecord.startMileage;
      }
      
      // 異常値検証
      final validation = await _validateDistanceData(
        existingRecord.startMileage, 
        mileage, 
        distance,
      );
      
      // 記録を更新
      final updatedRecord = existingRecord.copyWith(
        endMileage: mileage,
        distance: source == MileageSource.gps ? gpsDistance : null,
        source: source,
        updatedAt: now,
        auditLog: [
          ...existingRecord.auditLog,
          if (validation.hasWarnings) ...validation.auditEntries,
        ],
      );
      
      await _storageService.updateMileageRecord(updatedRecord);
      
      // GPS追跡停止（GPS記録が存在し、GPS追跡が有効な場合）
      GPSTrackingRecord? gpsRecord;
      if (_gpsService.isTracking) {
        try {
          gpsRecord = await _gpsService.stopTracking(endMileage: mileage);
          AppLogger.info('GPS追跡停止完了', 'MileageService');
        } catch (e) {
          AppLogger.error('GPS追跡停止に失敗', 'MileageService', e);
          // GPS停止に失敗しても終了記録は継続
        }
      }
      
      // 監査ログに記録
      await _logMileageAction(
        recordId: updatedRecord.id,
        action: AuditAction.modify,
        oldValue: existingRecord.endMileage,
        newValue: mileage,
        reason: '終了メーター値記録',
        // metadata: {
        //   'gps_tracking_id': existingRecord.gpsTrackingId,
        //   'gps_distance': gpsRecord?.calculatedDistance,
        //   'gps_stopped': gpsRecord != null,
        // },
      );
      
      // 点呼記録を更新（提供された場合）
      if (rollCallRecord != null) {
        final updatedRollCall = rollCallRecord.copyWith(
          endMileage: mileage,
          calculatedDistance: distance,
          mileageValidationFlags: validation.flags,
        );
        
        await _storageService.updateRollCallRecord(updatedRollCall);
      }
      
      // 警告がある場合はログに記録
      if (validation.hasWarnings) {
        AppLogger.warning('メーター値に異常値を検出: ${validation.warnings.join(', ')}', 'MileageService');
      }
      
      AppLogger.info('終了メーター値記録完了: ${updatedRecord.id}, 距離: ${distance.toStringAsFixed(1)}km', 'MileageService');
      return updatedRecord;
      
    } catch (e) {
      AppLogger.error('終了メーター値記録中にエラー', 'MileageService', e);
      rethrow;
    }
  }

  // ============ GPS記録からの距離算出 ============

  /// GPS記録から走行距離を算出
  /// 
  /// [trackingId] GPS記録ID
  /// 
  /// 戻り値: 算出された距離 (km)
  Future<double> calculateDistanceFromGPS(String trackingId) async {
    AppLogger.info('GPS距離算出開始: $trackingId', 'MileageService');
    
    try {
      // StorageService未実装のため一時的にスキップ
      // final gpsRecord = await _storageService.getGPSTrackingRecordById(trackingId);
      // if (gpsRecord == null) {
      //   throw Exception('GPS記録が見つかりません: $trackingId');
      // }
      // 
      // if (!gpsRecord.isComplete) {
      //   throw Exception('GPS記録が完了していません: $trackingId');
      // }
      // 
      // final distance = gpsRecord.totalDistance;
      
      final distance = 0.0; // 一時的な値
      AppLogger.info('GPS距離算出完了: ${distance.toStringAsFixed(1)}km', 'MileageService');
      
      return distance;
      
    } catch (e) {
      AppLogger.error('GPS距離算出中にエラー', 'MileageService', e);
      rethrow;
    }
  }

  // ============ GPS統合機能 ============

  /// 現在のGPS追跡状態を取得
  /// 
  /// 戻り値: GPS追跡中の場合はGPSTrackingRecord、そうでなければnull
  GPSTrackingRecord? getCurrentGPSTracking() {
    return _gpsService.currentTracking;
  }
  
  /// GPS追跡中かどうかを確認
  /// 
  /// 戻り値: 追跡中の場合true
  bool isGPSTracking() {
    return _gpsService.isTracking;
  }
  
  /// 現在のGPS距離を取得
  /// 
  /// 戻り値: 現在の累積GPS距離 (km)
  double getCurrentGPSDistance() {
    return _gpsService.currentDistance;
  }
  
  /// GPS品質メトリクスを取得
  /// 
  /// 戻り値: 現在のGPS品質情報
  GPSQualityMetrics? getCurrentGPSQuality() {
    return _gpsService.currentQuality;
  }
  
  /// GPS追跡履歴を取得
  /// 
  /// [fromDate] 開始日
  /// [toDate] 終了日
  /// 
  /// 戻り値: 指定期間のGPS追跡記録リスト
  Future<List<GPSTrackingRecord>> getGPSTrackingHistory({
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      return await _gpsService.getTrackingHistory(
        fromDate: fromDate,
        toDate: toDate,
      );
    } catch (e) {
      AppLogger.error('GPS追跡履歴取得エラー', 'MileageService', e);
      return []; // 空リストを返す
    }
  }

  // ============ データ検証機能 ============

  /// メーター値データの検証
  /// 
  /// [startMileage] 開始メーター値
  /// [endMileage] 終了メーター値
  /// [gpsDistance] GPS算出距離（オプション）
  /// 
  /// 戻り値: 検証結果
  Future<MileageValidationResult> validateMileageData(
    double startMileage, 
    double? endMileage, {
    double? gpsDistance,
  }) async {
    AppLogger.info('メーター値検証開始: Start=$startMileage, End=$endMileage', 'MileageService');
    
    try {
      return await _validateDistanceData(startMileage, endMileage, gpsDistance);
    } catch (e) {
      AppLogger.error('メーター値検証中にエラー', 'MileageService', e);
      rethrow;
    }
  }

  // ============ 履歴取得機能 ============

  /// メーター値履歴を取得
  /// 
  /// [from] 開始日
  /// [to] 終了日
  /// 
  /// 戻り値: MileageRecordのリスト
  Future<List<MileageRecord>> getMileageHistory(DateTime from, DateTime to) async {
    AppLogger.info('メーター値履歴取得: ${from.toString()} - ${to.toString()}', 'MileageService');
    
    try {
      final records = await _storageService.getMileageRecordsByDateRange(from, to);
      AppLogger.info('メーター値履歴取得完了: ${records.length}件', 'MileageService');
      return records;
    } catch (e) {
      AppLogger.error('メーター値履歴取得中にエラー', 'MileageService', e);
      return [];
    }
  }

  /// 当日のメーター値記録を取得
  /// 
  /// [date] 対象日（デフォルトは今日）
  /// 
  /// 戻り値: MileageRecord（存在しない場合はnull）
  Future<MileageRecord?> getCurrentDayRecord([DateTime? date]) async {
    final targetDate = date ?? DateTime.now();
    final normalizedDate = DateTime(targetDate.year, targetDate.month, targetDate.day);
    
    try {
      return await _storageService.getMileageRecordByDate(normalizedDate);
    } catch (e) {
      AppLogger.error('当日記録取得中にエラー', 'MileageService', e);
      return null;
    }
  }

  // ============ 異常値検知機能 ============

  /// 異常値を検知
  /// 
  /// [from] 開始日
  /// [to] 終了日
  /// 
  /// 戻り値: 異常値検知結果のリスト
  Future<List<MileageAnomalyReport>> detectAnomalies(DateTime from, DateTime to) async {
    AppLogger.info('異常値検知開始: ${from.toString()} - ${to.toString()}', 'MileageService');
    
    try {
      final records = await getMileageHistory(from, to);
      final anomalies = <MileageAnomalyReport>[];
      
      for (final record in records) {
        final anomaly = _analyzeRecordForAnomalies(record);
        if (anomaly != null) {
          anomalies.add(anomaly);
        }
      }
      
      AppLogger.info('異常値検知完了: ${anomalies.length}件の異常を発見', 'MileageService');
      return anomalies;
      
    } catch (e) {
      AppLogger.error('異常値検知中にエラー', 'MileageService', e);
      return [];
    }
  }

  // ============ プライベートメソッド ============

  /// メーター値の基本検証
  Future<void> _validateMileageValue(double mileage) async {
    if (mileage < _minMileageValue || mileage > _maxMileageValue) {
      throw ArgumentError('メーター値が範囲外です: $mileage (範囲: $_minMileageValue - $_maxMileageValue)');
    }
  }

  /// 距離データの詳細検証
  Future<MileageValidationResult> _validateDistanceData(
    double startMileage, 
    double? endMileage, 
    double? gpsDistance,
  ) async {
    final warnings = <String>[];
    final flags = <String>[];
    final auditEntries = <MileageAuditEntry>[];
    
    if (endMileage != null) {
      final calculatedDistance = endMileage - startMileage;
      
      // 1. メーター逆転チェック
      if (calculatedDistance < 0) {
        warnings.add('メーター値が逆転しています（メーター交換の可能性）');
        flags.add('METER_REVERSAL');
      }
      
      // 2. 異常な走行距離チェック
      if (calculatedDistance > _maxDailyDistance) {
        warnings.add('1日の走行距離が${_maxDailyDistance.toInt()}kmを超過しています');
        flags.add('EXCESSIVE_DISTANCE');
      }
      
      // 3. GPS距離との比較（GPS使用時）
      if (gpsDistance != null) {
        final difference = (calculatedDistance - gpsDistance).abs();
        final threshold = max(calculatedDistance * 0.1, 5.0); // 10%または5kmの大きい方
        
        if (difference > threshold) {
          warnings.add('GPS算出距離とメーター値に大きな差があります');
          flags.add('GPS_MILEAGE_MISMATCH');
        }
      }
    }
    
    return MileageValidationResult(
      isValid: warnings.isEmpty,
      warnings: warnings,
      flags: flags,
      auditEntries: auditEntries,
    );
  }

  /// 監査ログの記録
  Future<void> _logMileageAction({
    required String recordId,
    required AuditAction action,
    double? oldValue,
    double? newValue,
    required String reason,
  }) async {
    final auditEntry = MileageAuditEntry(
      id: MileageAuditEntry.generateId(),
      recordId: recordId,
      timestamp: DateTime.now(),
      action: action,
      oldValue: oldValue,
      newValue: newValue,
      deviceInfo: 'Flutter App',
      reason: reason,
    );
    
    await _storageService.addMileageAuditEntry(auditEntry);
  }

  /// 記録の異常値分析
  MileageAnomalyReport? _analyzeRecordForAnomalies(MileageRecord record) {
    final anomalies = <AnomalyType>[];
    
    if (record.hasAnomalies) {
      final distance = record.calculatedDistance;
      if (distance != null) {
        if (distance > _maxDailyDistance) {
          anomalies.add(AnomalyType.excessiveDistance);
        }
        if (distance < 0) {
          anomalies.add(AnomalyType.meterReversal);
        }
      }
    }
    
    if (record.hasMeterReversal) {
      anomalies.add(AnomalyType.meterReversal);
    }
    
    if (anomalies.isNotEmpty) {
      return MileageAnomalyReport(
        record: record,
        anomalyTypes: anomalies,
        detectedAt: DateTime.now(),
        severity: _calculateSeverity(anomalies),
      );
    }
    
    return null;
  }

  /// 異常の重要度を計算
  AnomalySeverity _calculateSeverity(List<AnomalyType> anomalies) {
    if (anomalies.contains(AnomalyType.meterReversal)) {
      return AnomalySeverity.high;
    } else if (anomalies.contains(AnomalyType.excessiveDistance)) {
      return AnomalySeverity.medium;
    } else {
      return AnomalySeverity.low;
    }
  }
  
  /// リソースの解放
  /// アプリ終了時やサービス停止時に呼び出す
  void dispose() {
    _gpsService.dispose();
  }
}

// ============ 関連データクラス ============

/// メーター値検証結果
class MileageValidationResult {
  final bool isValid;
  final List<String> warnings;
  final List<String> flags;
  final List<MileageAuditEntry> auditEntries;

  MileageValidationResult({
    required this.isValid,
    required this.warnings,
    required this.flags,
    required this.auditEntries,
  });

  bool get hasWarnings => warnings.isNotEmpty;
}

/// 異常値検知結果
class MileageAnomalyReport {
  final MileageRecord record;
  final List<AnomalyType> anomalyTypes;
  final DateTime detectedAt;
  final AnomalySeverity severity;

  MileageAnomalyReport({
    required this.record,
    required this.anomalyTypes,
    required this.detectedAt,
    required this.severity,
  });
}

/// 異常の種類
enum AnomalyType {
  excessiveDistance, // 異常な走行距離
  meterReversal, // メーター逆転
  gpsMismatch, // GPS値との不一致
  dataInconsistency, // データの不整合
}

/// 異常の重要度
enum AnomalySeverity {
  low,    // 低
  medium, // 中
  high,   // 高
}