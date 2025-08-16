import 'backup_service.dart';
import 'storage_service.dart';

/// アプリ全体で共有するサービスの管理クラス
class AppServices {
  static AppServices? _instance;
  static AppServices get instance {
    _instance ??= AppServices._internal();
    return _instance!;
  }
  
  AppServices._internal();
  
  BackupService? _backupService;
  
  /// BackupServiceのインスタンスを設定
  void setBackupService(BackupService backupService) {
    _backupService = backupService;
  }
  
  /// BackupServiceのインスタンスを取得
  BackupService? get backupService => _backupService;
  
  /// BackupServiceが初期化済みかチェック
  bool get isBackupServiceInitialized => _backupService != null;
  
  /// 新しいBackupServiceインスタンスを作成（必要に応じて）
  BackupService getOrCreateBackupService() {
    if (_backupService == null) {
      final storageService = StorageService();
      _backupService = BackupService(storageService);
    }
    return _backupService!;
  }
  
  /// リソースをクリア
  void dispose() {
    _backupService?.dispose();
    _backupService = null;
  }
}