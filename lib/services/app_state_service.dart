import 'dart:async';
import '../utils/logger.dart';

/// アプリ全体の状態管理とイベント通知サービス
class AppStateService {
  static final AppStateService _instance = AppStateService._internal();
  factory AppStateService() => _instance;
  AppStateService._internal();

  // データ更新イベントストリーム
  final StreamController<DataUpdateEvent> _dataUpdateController = 
      StreamController<DataUpdateEvent>.broadcast();

  Stream<DataUpdateEvent> get dataUpdateStream => _dataUpdateController.stream;

  /// 訪問記録が更新されたことを通知
  void notifyVisitRecordsUpdated() {
    AppLogger.info('訪問記録の更新を通知', 'AppStateService');
    _dataUpdateController.add(DataUpdateEvent.visitRecordsUpdated());
  }

  /// 得意先データが更新されたことを通知
  void notifyClientsUpdated() {
    AppLogger.info('得意先データの更新を通知', 'AppStateService');
    _dataUpdateController.add(DataUpdateEvent.clientsUpdated());
  }

  /// 点呼記録が更新されたことを通知
  void notifyRollCallRecordsUpdated() {
    AppLogger.info('点呼記録の更新を通知', 'AppStateService');
    _dataUpdateController.add(DataUpdateEvent.rollCallRecordsUpdated());
  }

  /// 日報記録が更新されたことを通知
  void notifyDailyRecordsUpdated() {
    AppLogger.info('日報記録の更新を通知', 'AppStateService');
    _dataUpdateController.add(DataUpdateEvent.dailyRecordsUpdated());
  }

  /// 全データが更新されたことを通知（復元時などに使用）
  void notifyAllDataUpdated() {
    AppLogger.info('全データの更新を通知', 'AppStateService');
    _dataUpdateController.add(DataUpdateEvent.allDataUpdated());
  }

  /// リソースの解放
  void dispose() {
    _dataUpdateController.close();
  }
}

/// データ更新イベント
class DataUpdateEvent {
  final DataUpdateType type;
  final DateTime timestamp;

  DataUpdateEvent._(this.type) : timestamp = DateTime.now();

  factory DataUpdateEvent.visitRecordsUpdated() => 
      DataUpdateEvent._(DataUpdateType.visitRecords);
  
  factory DataUpdateEvent.clientsUpdated() => 
      DataUpdateEvent._(DataUpdateType.clients);
  
  factory DataUpdateEvent.rollCallRecordsUpdated() => 
      DataUpdateEvent._(DataUpdateType.rollCallRecords);
  
  factory DataUpdateEvent.dailyRecordsUpdated() => 
      DataUpdateEvent._(DataUpdateType.dailyRecords);
  
  factory DataUpdateEvent.allDataUpdated() => 
      DataUpdateEvent._(DataUpdateType.allData);
}

/// データ更新の種類
enum DataUpdateType {
  visitRecords,
  clients,
  rollCallRecords,
  dailyRecords,
  allData,
}