import '../services/storage_service.dart';
import '../services/mileage_service.dart';
import '../models/roll_call_record.dart';
import '../models/mileage_record.dart';
import '../utils/logger.dart';

/// データ移行サービス
/// 
/// 点呼記録からメーター値を抽出してMileageRecordに移行する
class DataMigrationService {
  static const String _migrationVersionKey = 'migration_version';
  static const int _currentMigrationVersion = 1;
  
  final StorageService _storageService;
  final MileageService _mileageService;
  
  DataMigrationService({
    StorageService? storageService,
    MileageService? mileageService,
  }) : 
    _storageService = storageService ?? StorageService(),
    _mileageService = mileageService ?? MileageService();

  /// マイグレーションが必要かどうかを確認
  Future<bool> needsMigration() async {
    final currentVersion = await _storageService.getMigrationVersion();
    return currentVersion < _currentMigrationVersion;
  }

  /// すべてのマイグレーションを実行
  Future<void> runMigrations() async {
    final currentVersion = await _storageService.getMigrationVersion();
    AppLogger.info('データ移行開始: バージョン $currentVersion → $_currentMigrationVersion', 'DataMigrationService');

    if (currentVersion < 1) {
      await _migrateRollCallMileageToMileageRecords();
      await _storageService.setMigrationVersion(1);
      AppLogger.info('マイグレーション v1 完了: 点呼記録のメーター値をMileageRecordに移行', 'DataMigrationService');
    }

    AppLogger.info('すべてのデータ移行が完了しました', 'DataMigrationService');
  }

  /// 点呼記録のメーター値をMileageRecordに移行
  Future<void> _migrateRollCallMileageToMileageRecords() async {
    try {
      AppLogger.info('点呼記録のメーター値移行を開始', 'DataMigrationService');
      
      // 既存の点呼記録を全件取得（移行前のフォーマット）
      final rollCallRecords = await _getLegacyRollCallRecords();
      
      int migratedCount = 0;
      int startRecordCount = 0;
      int endRecordCount = 0;

      // 日付ごとにグループ化
      final recordsByDate = <String, List<Map<String, dynamic>>>{};
      for (final record in rollCallRecords) {
        final dateKey = _getDateKey(record['datetime']);
        recordsByDate.putIfAbsent(dateKey, () => []);
        recordsByDate[dateKey]!.add(record);
      }

      // 日付ごとに処理
      for (final dateKey in recordsByDate.keys) {
        final dayRecords = recordsByDate[dateKey]!;
        
        // 開始と終了の記録を探す
        Map<String, dynamic>? startRecord;
        Map<String, dynamic>? endRecord;
        
        for (final record in dayRecords) {
          if (record['type'] == 'start' && record['startMileage'] != null) {
            startRecord = record;
          }
          if (record['type'] == 'end' && (record['endMileage'] != null || record['calculatedDistance'] != null)) {
            endRecord = record;
          }
        }

        // メーター値記録を作成
        if (startRecord != null) {
          await _createMileageRecordFromLegacyData(startRecord, endRecord);
          migratedCount++;
          startRecordCount++;
          if (endRecord != null) {
            endRecordCount++;
          }
        }
      }

      AppLogger.info('点呼記録メーター値移行完了: $migratedCount件のメーター値記録を作成 (開始: $startRecordCount, 終了: $endRecordCount)', 'DataMigrationService');
    } catch (e) {
      AppLogger.error('点呼記録メーター値移行エラー', 'DataMigrationService', e);
      throw Exception('メーター値移行に失敗しました: $e');
    }
  }

  /// レガシーフォーマットの点呼記録を取得
  Future<List<Map<String, dynamic>>> _getLegacyRollCallRecords() async {
    try {
      // ストレージから直接JSONデータを取得
      final prefs = await _storageService.getPreferences();
      final jsonString = prefs.getString(StorageService.rollCallKey);
      
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> jsonList = _storageService.parseJsonList(jsonString);
      return jsonList.cast<Map<String, dynamic>>();
    } catch (e) {
      AppLogger.error('レガシー点呼記録の取得に失敗', 'DataMigrationService', e);
      return [];
    }
  }

  /// レガシーデータからMileageRecordを作成
  Future<void> _createMileageRecordFromLegacyData(
    Map<String, dynamic> startRecord,
    Map<String, dynamic>? endRecord,
  ) async {
    try {
      final date = DateTime.parse(startRecord['datetime']);
      final startMileage = startRecord['startMileage']?.toDouble();
      final gpsTrackingEnabled = startRecord['gpsTrackingEnabled'] ?? false;

      if (startMileage == null) return;

      // MileageRecordを作成
      final mileageRecord = MileageRecord(
        id: 'migrated_${startRecord['id']}',
        date: date,
        startMileage: startMileage,
        endMileage: endRecord?['endMileage']?.toDouble(),
        distance: endRecord?['calculatedDistance']?.toDouble(),
        source: gpsTrackingEnabled ? MileageSource.gps : MileageSource.manual,
        createdAt: date,
        updatedAt: DateTime.now(),
      );

      // 既存のMileageRecordがないかチェック
      final existingRecords = await _mileageService.getMileageHistory(
        date.subtract(const Duration(days: 1)),
        date.add(const Duration(days: 1)),
      );

      final hasSameDateRecord = existingRecords.any((existing) => 
        existing.date.year == date.year &&
        existing.date.month == date.month &&
        existing.date.day == date.day
      );

      // 同じ日のレコードがなければ追加
      if (!hasSameDateRecord) {
        await _storageService.addMileageRecord(mileageRecord);
        
        // 監査ログを追加
        final auditEntry = MileageAuditEntry(
          id: 'migration_${DateTime.now().millisecondsSinceEpoch}',
          recordId: mileageRecord.id,
          timestamp: DateTime.now(),
          action: AuditAction.create,
          newValue: startMileage,
          reason: 'データ移行：点呼記録からMileageRecordへ移行',
        );
        await _storageService.addMileageAuditEntry(auditEntry);

        AppLogger.info('レガシーデータ移行: ${date.toString().split(' ')[0]} - 開始: ${startMileage}km${endRecord != null ? ', 終了: ${endRecord['endMileage']}km' : ''}', 'DataMigrationService');
      }
    } catch (e) {
      AppLogger.error('MileageRecord作成エラー', 'DataMigrationService', e);
    }
  }

  /// 日付キーを生成
  String _getDateKey(String datetimeString) {
    final date = DateTime.parse(datetimeString);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 移行完了後に古い点呼記録をクリーンアップ（メーター値フィールドのみ）
  Future<void> cleanupLegacyMileageData() async {
    try {
      AppLogger.info('レガシーメーター値データのクリーンアップ開始', 'DataMigrationService');
      
      // 既存の点呼記録を読み込み
      final rollCallRecords = await _storageService.loadRollCallRecords();
      
      // メーター値フィールドを削除した新しいフォーマットで再保存
      // （この時点では新しいRollCallRecordモデルを使用するため、メーター値フィールドは自動的に除外される）
      final cleanedRecords = <RollCallRecord>[];
      
      for (final oldRecord in rollCallRecords) {
        // 新しいモデルに変換（メーター値フィールドは自動的に除外される）
        final cleanedRecord = RollCallRecord(
          id: oldRecord.id,
          datetime: oldRecord.datetime,
          type: oldRecord.type,
          method: oldRecord.method,
          otherMethodDetail: oldRecord.otherMethodDetail,
          inspectorName: oldRecord.inspectorName,
          isAlcoholTestUsed: oldRecord.isAlcoholTestUsed,
          hasDrunkAlcohol: oldRecord.hasDrunkAlcohol,
          alcoholValue: oldRecord.alcoholValue,
          remarks: oldRecord.remarks,
        );
        cleanedRecords.add(cleanedRecord);
      }

      // クリーンアップされた点呼記録を保存
      await _storageService.saveRollCallRecords(cleanedRecords);
      
      AppLogger.info('レガシーメーター値データのクリーンアップ完了: ${cleanedRecords.length}件の点呼記録を更新', 'DataMigrationService');
    } catch (e) {
      AppLogger.error('レガシーデータクリーンアップエラー', 'DataMigrationService', e);
    }
  }
}