import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'storage_service.dart';
import 'cloud_storage_interface.dart';
import 'google_drive_service.dart';
import 'app_state_service.dart';
import '../utils/logger.dart';
import '../models/visit_record.dart';
import '../models/client.dart';
import '../models/daily_record.dart';
import '../models/roll_call_record.dart';

/// 自動バックアップサービス
class BackupService {
  static const String _configKey = 'backup_config';
  static const String _lastBackupKey = 'last_backup_time';
  static const String _currentVersion = '1.0.0';
  
  // シングルトンパターン
  static BackupService? _instance;
  static BackupService getInstance(StorageService storageService) {
    _instance ??= BackupService._internal(storageService);
    return _instance!;
  }
  
  final StorageService _storageService;
  CloudStorageInterface? _cloudStorage;
  BackupConfig _config = const BackupConfig();
  Timer? _backupTimer;
  
  // バックアップ状態管理
  bool _isBackingUp = false;
  bool _isRestoring = false;
  String? _lastError;
  DateTime? _lastBackupTime;
  
  // イベントストリーム
  final StreamController<BackupEvent> _eventController = StreamController<BackupEvent>.broadcast();
  Stream<BackupEvent> get events => _eventController.stream;
  
  BackupService._internal(this._storageService);
  
  // 外部用のファクトリーコンストラクター
  factory BackupService(StorageService storageService) {
    return getInstance(storageService);
  }
  
  /// 初期化
  Future<void> initialize() async {
    await _loadConfig();
    await _loadLastBackupTime();
    await _initializeCloudStorage();
    
    if (_config.autoBackup) {
      _startAutoBackup();
    }
  }
  
  /// 設定を取得
  BackupConfig get config => _config;
  
  /// バックアップ状態
  bool get isBackingUp => _isBackingUp;
  bool get isRestoring => _isRestoring;
  String? get lastError => _lastError;
  DateTime? get lastBackupTime => _lastBackupTime;
  bool get isCloudConnected => _cloudStorage?.isAuthenticated == true;
  String? get currentUser => _cloudStorage?.currentUser;
  
  /// バックアップ設定を更新
  Future<void> updateConfig(BackupConfig newConfig) async {
    _config = newConfig;
    await _saveConfig();
    
    // 自動バックアップの設定変更
    if (_config.autoBackup) {
      _startAutoBackup();
    } else {
      _stopAutoBackup();
    }
    
    _eventController.add(BackupEvent.configUpdated(_config));
  }
  
  /// クラウドストレージに接続
  Future<bool> connectToCloud(CloudStorageType type) async {
    try {
      switch (type) {
        case CloudStorageType.googleDrive:
          _cloudStorage = GoogleDriveService();
          break;
        case CloudStorageType.firebaseStorage:
          // TODO: Firebase Storage実装
          throw UnimplementedError('Firebase Storage is not implemented yet');
      }
      
      // 認証状態ストリームの監視開始
      if (_cloudStorage is GoogleDriveService) {
        final googleDriveService = _cloudStorage as GoogleDriveService;
        googleDriveService.authStateChanges.listen((account) {
          if (account != null) {
            _eventController.add(BackupEvent.cloudConnected(account.displayName ?? 'Unknown'));
            // 接続成功時にサービス情報を保存
            _saveCloudServiceInfo('google_drive');
          } else {
            _eventController.add(BackupEvent.cloudDisconnected());
          }
        });
      }
      
      final success = await _cloudStorage!.connect();
      if (success) {
        await _saveCloudServiceInfo(type.name);
      } else {
        _lastError = _cloudStorage!.lastError ?? 'クラウド接続に失敗しました';
        _eventController.add(BackupEvent.error(_lastError!));
      }
      
      return success;
    } catch (e) {
      _lastError = 'クラウド接続エラー: $e';
      _eventController.add(BackupEvent.error(_lastError!));
      return false;
    }
  }
  
  /// クラウドストレージから切断
  Future<void> disconnectFromCloud() async {
    await _cloudStorage?.disconnect();
    _cloudStorage = null;
    _stopAutoBackup();
    _eventController.add(BackupEvent.cloudDisconnected());
  }
  
  /// 手動バックアップ実行
  Future<bool> performBackup() async {
    if (_isBackingUp || _cloudStorage == null || !_cloudStorage!.isAuthenticated) {
      return false;
    }
    
    try {
      _isBackingUp = true;
      _lastError = null;
      _eventController.add(BackupEvent.backupStarted());
      
      // 全データを収集
      final backupData = await _collectAllData();
      
      // バックアップファイル名を生成
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'backup_$timestamp.json';
      
      // データを暗号化（設定に応じて）
      String dataToUpload = backupData;
      if (_config.encryptData) {
        dataToUpload = _encryptData(backupData);
      }
      
      // クラウドにアップロード
      final success = await _cloudStorage!.uploadData(fileName, dataToUpload);
      
      if (success) {
        _lastBackupTime = DateTime.now();
        await _saveLastBackupTime();
        
        // 古いバックアップファイルを削除
        await _cleanupOldBackups();
        
        _eventController.add(BackupEvent.backupCompleted(fileName));
        print('バックアップが完了しました: $fileName');
        return true;
      } else {
        _lastError = _cloudStorage!.lastError ?? 'バックアップのアップロードに失敗しました';
        _eventController.add(BackupEvent.error(_lastError!));
        return false;
      }
    } catch (e) {
      _lastError = 'バックアップエラー: $e';
      _eventController.add(BackupEvent.error(_lastError!));
      return false;
    } finally {
      _isBackingUp = false;
    }
  }
  
  /// バックアップからデータを復元
  Future<bool> restoreFromBackup(String fileName) async {
    if (_isRestoring || _cloudStorage == null || !_cloudStorage!.isAuthenticated) {
      return false;
    }
    
    try {
      _isRestoring = true;
      _lastError = null;
      _eventController.add(BackupEvent.restoreStarted());
      
      // クラウドからダウンロード
      String? downloadedData = await _cloudStorage!.downloadData(fileName);
      if (downloadedData == null) {
        _lastError = 'バックアップファイルのダウンロードに失敗しました';
        _eventController.add(BackupEvent.error(_lastError!));
        return false;
      }
      
      // データを復号化（必要に応じて）
      if (_config.encryptData) {
        downloadedData = _decryptData(downloadedData);
      }
      
      // データを復元
      final success = await _restoreAllData(downloadedData);
      
      if (success) {
        _eventController.add(BackupEvent.restoreCompleted(fileName));
        print('データの復元が完了しました: $fileName');
        
        // アプリ全体にデータ更新を通知
        AppStateService().notifyAllDataUpdated();
        
        return true;
      } else {
        _lastError = 'データの復元に失敗しました';
        _eventController.add(BackupEvent.error(_lastError!));
        return false;
      }
    } catch (e) {
      _lastError = '復元エラー: $e';
      _eventController.add(BackupEvent.error(_lastError!));
      return false;
    } finally {
      _isRestoring = false;
    }
  }
  
  /// 利用可能なバックアップファイル一覧を取得
  Future<List<BackupMetadata>> getAvailableBackups() async {
    print('getAvailableBackups開始');
    
    if (_cloudStorage == null || !_cloudStorage!.isAuthenticated) {
      print('クラウドストレージが未認証またはnull');
      return [];
    }
    
    try {
      print('クラウドからファイル一覧を取得中...');
      final files = await _cloudStorage!.listFiles();
      print('取得されたファイル数: ${files.length}');
      print('ファイル一覧: $files');
      
      final backupFiles = files.where((file) => file.startsWith('backup_') && file.endsWith('.json')).toList();
      print('バックアップファイル数: ${backupFiles.length}');
      print('バックアップファイル: $backupFiles');
      
      final metadataList = <BackupMetadata>[];
      for (final fileName in backupFiles) {
        print('メタデータ取得中: $fileName');
        final metadata = await _getBackupMetadata(fileName);
        if (metadata != null) {
          metadataList.add(metadata);
          print('メタデータ追加: ${metadata.fileName}');
        } else {
          print('メタデータ取得失敗: $fileName');
        }
      }
      
      // 作成日時の新しい順でソート
      metadataList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      print('最終的なメタデータ数: ${metadataList.length}');
      return metadataList;
    } catch (e) {
      print('バックアップファイル一覧取得エラー: $e');
      return [];
    }
  }
  
  /// 全データを収集
  Future<String> _collectAllData() async {
    final data = {
      'version': _currentVersion,
      'timestamp': DateTime.now().toIso8601String(),
      'visitRecords': (await _storageService.loadVisitRecords()).map((r) => r.toJson()).toList(),
      'clients': (await _storageService.loadClients()).map((c) => c.toJson()).toList(),
      'dailyRecords': (await _storageService.loadDailyRecords()).map((d) => d.toJson()).toList(),
      'rollCallRecords': (await _storageService.loadRollCallRecords()).map((r) => r.toJson()).toList(),
      // SharedPreferencesのデータも含める
      'preferences': await _getPreferencesData(),
    };
    
    return jsonEncode(data);
  }
  
  /// 全データを復元
  Future<bool> _restoreAllData(String jsonData) async {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      
      // バージョンチェック
      final version = data['version'] as String?;
      if (version != _currentVersion) {
        print('警告: バックアップのバージョンが異なります ($version vs $_currentVersion)');
      }
      
      // 各データを復元
      if (data['visitRecords'] != null) {
        final visitRecords = (data['visitRecords'] as List)
            .map((json) => VisitRecord.fromJson(json))
            .toList();
        await _storageService.saveVisitRecords(visitRecords);
      }
      
      if (data['clients'] != null) {
        final clients = (data['clients'] as List)
            .map((json) => Client.fromJson(json))
            .toList();
        await _storageService.saveClients(clients);
      }
      
      if (data['dailyRecords'] != null) {
        final dailyRecords = (data['dailyRecords'] as List)
            .map((json) => DailyRecord.fromJson(json))
            .toList();
        // DailyRecordの復元は個別に行う（StorageServiceの実装に依存）
        for (final record in dailyRecords) {
          await _storageService.saveDailyRecordObject(record);
        }
      }
      
      if (data['rollCallRecords'] != null) {
        final rollCallRecords = (data['rollCallRecords'] as List)
            .map((json) => RollCallRecord.fromJson(json))
            .toList();
        await _storageService.saveRollCallRecords(rollCallRecords);
      }
      
      // SharedPreferencesの復元
      if (data['preferences'] != null) {
        await _restorePreferencesData(data['preferences'] as Map<String, dynamic>);
      }
      
      return true;
    } catch (e) {
      print('データ復元エラー: $e');
      return false;
    }
  }
  
  /// SharedPreferencesのデータを取得
  Future<Map<String, dynamic>> _getPreferencesData() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final data = <String, dynamic>{};
    
    for (final key in keys) {
      // バックアップ関連の設定は除外
      if (key.startsWith('backup_') || key.startsWith('google_drive_')) continue;
      
      final value = prefs.get(key);
      data[key] = value;
    }
    
    return data;
  }
  
  /// SharedPreferencesのデータを復元
  Future<void> _restorePreferencesData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is List<String>) {
        await prefs.setStringList(key, value);
      }
    }
  }
  
  /// バックアップメタデータを取得
  Future<BackupMetadata?> _getBackupMetadata(String fileName) async {
    try {
      print('メタデータ取得開始: $fileName');
      
      // ファイル名から日時を抽出
      final match = RegExp(r'backup_(\d{8}_\d{6})\.json').firstMatch(fileName);
      if (match == null) {
        print('ファイル名パターンが一致しません: $fileName');
        return null;
      }
      
      final timestampStr = match.group(1)!;
      print('抽出されたタイムスタンプ文字列: $timestampStr');
      
      // 日付フォーマットを修正: yyyyMMdd_HHmmss
      DateTime createdAt;
      try {
        // 文字列を分割して解析
        final parts = timestampStr.split('_');
        if (parts.length != 2) {
          print('タイムスタンプの形式が無効: $timestampStr');
          return null;
        }
        
        final datePart = parts[0]; // 20250816
        final timePart = parts[1]; // 132400
        
        final year = int.parse(datePart.substring(0, 4));
        final month = int.parse(datePart.substring(4, 6));
        final day = int.parse(datePart.substring(6, 8));
        final hour = int.parse(timePart.substring(0, 2));
        final minute = int.parse(timePart.substring(2, 4));
        final second = int.parse(timePart.substring(4, 6));
        
        createdAt = DateTime(year, month, day, hour, minute, second);
        print('解析された日時: $createdAt');
      } catch (e) {
        print('日時解析エラー: $e');
        return null;
      }
      
      // ファイルサイズとチェックサムは実際のファイルをダウンロードして取得
      // （軽量化のため、ここでは推定値を使用）
      final metadata = BackupMetadata(
        fileName: fileName,
        createdAt: createdAt,
        dataSize: 0, // 実際のサイズは必要に応じて取得
        checksum: '', // 実際のチェックサムは必要に応じて計算
        version: _currentVersion,
      );
      
      print('メタデータ作成成功: ${metadata.fileName}');
      return metadata;
    } catch (e) {
      print('メタデータ取得エラー: $e');
      return null;
    }
  }
  
  /// データの暗号化（簡易実装）
  String _encryptData(String data) {
    // TODO: より強固な暗号化を実装
    final bytes = utf8.encode(data);
    final encoded = base64Encode(bytes);
    return encoded;
  }
  
  /// データの復号化（簡易実装）
  String _decryptData(String encryptedData) {
    // TODO: より強固な復号化を実装
    final bytes = base64Decode(encryptedData);
    final decoded = utf8.decode(bytes);
    return decoded;
  }
  
  /// 古いバックアップファイルを削除
  Future<void> _cleanupOldBackups() async {
    if (_cloudStorage == null) return;
    
    try {
      final files = await _cloudStorage!.listFiles();
      final backupFiles = files.where((file) => file.startsWith('backup_') && file.endsWith('.json')).toList();
      
      if (backupFiles.length > _config.maxBackupFiles) {
        // ファイル名でソート（古いものが先頭）
        backupFiles.sort();
        
        final filesToDelete = backupFiles.take(backupFiles.length - _config.maxBackupFiles);
        for (final fileName in filesToDelete) {
          await _cloudStorage!.deleteFile(fileName);
          print('古いバックアップファイルを削除: $fileName');
        }
      }
    } catch (e) {
      print('古いバックアップファイル削除エラー: $e');
    }
  }
  
  /// 自動バックアップを開始
  void _startAutoBackup() {
    _stopAutoBackup();
    
    if (_config.autoBackup && _cloudStorage?.isAuthenticated == true) {
      _backupTimer = Timer.periodic(_config.backupInterval, (timer) {
        performBackup();
      });
      print('自動バックアップを開始しました（間隔: ${_config.backupInterval}）');
    }
  }
  
  /// 自動バックアップを停止
  void _stopAutoBackup() {
    _backupTimer?.cancel();
    _backupTimer = null;
  }
  
  /// クラウドストレージを初期化（認証リフレッシュ機能付き）
  Future<void> _initializeCloudStorage() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Google Drive自動接続を必ず試行（設定されていない場合もデフォルトで試行）
    AppLogger.info('Google Drive自動接続を開始', 'BackupService');
    
    // Google Driveサービスを初期化
    _cloudStorage = GoogleDriveService();
    
    // 認証状態ストリームの監視開始
    if (_cloudStorage is GoogleDriveService) {
      final googleDriveService = _cloudStorage as GoogleDriveService;
      googleDriveService.authStateChanges.listen((account) {
        if (account != null) {
          AppLogger.info('認証状態変更: ログイン済み (${account.displayName})', 'BackupService');
          _eventController.add(BackupEvent.cloudConnected(account.displayName ?? 'Unknown'));
          // last_cloud_serviceを保存
          prefs.setString('last_cloud_service', 'google_drive');
        } else {
          AppLogger.info('認証状態変更: ログアウト', 'BackupService');
          _eventController.add(BackupEvent.cloudDisconnected());
        }
      });
    }
    
    // 認証復元と接続を試行
    bool connected = false;
    try {
      // Google Drive認証を積極的に試行
      if (_cloudStorage is GoogleDriveService) {
        final googleDriveService = _cloudStorage as GoogleDriveService;
        
        // まず認証リフレッシュを試行
        AppLogger.info('Google Drive認証リフレッシュを試行', 'BackupService');
        await googleDriveService.refreshAuthentication();
      }
      
      // 通常の接続を試行
      AppLogger.info('Google Drive接続を試行', 'BackupService');
      connected = await _cloudStorage!.connect();
      
      if (connected) {
        AppLogger.info('Google Drive自動接続成功', 'BackupService');
        await prefs.setString('last_cloud_service', 'google_drive');
      } else {
        AppLogger.info('初回接続失敗、追加のリフレッシュを試行', 'BackupService');
        
        // 追加のリフレッシュ試行
        if (_cloudStorage is GoogleDriveService) {
          final googleDriveService = _cloudStorage as GoogleDriveService;
          connected = await googleDriveService.refreshAuthentication();
          
          if (connected) {
            AppLogger.info('追加リフレッシュで接続成功', 'BackupService');
            await prefs.setString('last_cloud_service', 'google_drive');
          } else {
            AppLogger.warning('すべての自動接続試行が失敗', 'BackupService');
          }
        }
      }
      
    } catch (e) {
      AppLogger.error('Google Drive自動接続エラー', 'BackupService', e);
      connected = false;
    }
    
    // 接続に失敗した場合の処理
    if (!connected) {
      AppLogger.info('Google Drive自動接続に失敗 - 手動接続が必要', 'BackupService');
      // 失敗してもサービスは保持（手動接続用）
    }
  }
  
  /// 設定を保存
  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(_config.toJson()));
  }
  
  /// 設定を読み込み
  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString(_configKey);
    if (configJson != null) {
      _config = BackupConfig.fromJson(jsonDecode(configJson));
    }
  }
  
  /// 最後のバックアップ時刻を保存
  Future<void> _saveLastBackupTime() async {
    if (_lastBackupTime != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastBackupKey, _lastBackupTime!.toIso8601String());
    }
  }
  
  /// 最後のバックアップ時刻を読み込み
  Future<void> _loadLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_lastBackupKey);
    if (timeStr != null) {
      _lastBackupTime = DateTime.tryParse(timeStr);
    }
  }
  
  /// クラウドサービス情報を保存
  Future<void> _saveCloudServiceInfo(String serviceName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_cloud_service', serviceName);
      await prefs.setString('last_connection_time', DateTime.now().toIso8601String());
      AppLogger.debug('クラウドサービス情報を保存: $serviceName', 'BackupService');
    } catch (e) {
      AppLogger.warning('クラウドサービス情報の保存に失敗: $e', 'BackupService');
    }
  }

  /// リソースを解放
  void dispose() {
    _stopAutoBackup();
    _eventController.close();
  }
}

/// バックアップイベント
class BackupEvent {
  final BackupEventType type;
  final String? message;
  final dynamic data;
  
  const BackupEvent._(this.type, this.message, this.data);
  
  factory BackupEvent.configUpdated(BackupConfig config) => 
      BackupEvent._(BackupEventType.configUpdated, null, config);
  
  factory BackupEvent.cloudConnected(String user) => 
      BackupEvent._(BackupEventType.cloudConnected, 'クラウドに接続しました: $user', user);
  
  factory BackupEvent.cloudDisconnected() => 
      BackupEvent._(BackupEventType.cloudDisconnected, 'クラウドから切断しました', null);
  
  factory BackupEvent.backupStarted() => 
      BackupEvent._(BackupEventType.backupStarted, 'バックアップを開始しました', null);
  
  factory BackupEvent.backupCompleted(String fileName) => 
      BackupEvent._(BackupEventType.backupCompleted, 'バックアップが完了しました: $fileName', fileName);
  
  factory BackupEvent.restoreStarted() => 
      BackupEvent._(BackupEventType.restoreStarted, '復元を開始しました', null);
  
  factory BackupEvent.restoreCompleted(String fileName) => 
      BackupEvent._(BackupEventType.restoreCompleted, '復元が完了しました: $fileName', fileName);
  
  factory BackupEvent.error(String error) => 
      BackupEvent._(BackupEventType.error, error, null);
}

enum BackupEventType {
  configUpdated,
  cloudConnected,
  cloudDisconnected,
  backupStarted,
  backupCompleted,
  restoreStarted,
  restoreCompleted,
  error,
}