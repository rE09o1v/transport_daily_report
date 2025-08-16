// クラウドストレージサービスの抽象化インターフェース
abstract class CloudStorageInterface {
  /// クラウドストレージサービスに接続
  Future<bool> connect();
  
  /// 接続を切断
  Future<void> disconnect();
  
  /// 認証状態を確認
  bool get isAuthenticated;
  
  /// 現在認証されているユーザー名を取得
  String? get currentUser;
  
  /// データをクラウドにアップロード
  /// [fileName] - ファイル名
  /// [data] - アップロードするデータ
  /// [folder] - オプション：保存先フォルダ
  Future<bool> uploadData(String fileName, String data, {String? folder});
  
  /// クラウドからデータをダウンロード
  /// [fileName] - ファイル名
  /// [folder] - オプション：検索するフォルダ
  Future<String?> downloadData(String fileName, {String? folder});
  
  /// ファイルの存在を確認
  /// [fileName] - ファイル名
  /// [folder] - オプション：検索するフォルダ
  Future<bool> fileExists(String fileName, {String? folder});
  
  /// ファイルを削除
  /// [fileName] - ファイル名
  /// [folder] - オプション：削除するフォルダ
  Future<bool> deleteFile(String fileName, {String? folder});
  
  /// フォルダ内のファイル一覧を取得
  /// [folder] - オプション：検索するフォルダ（nullの場合はルート）
  Future<List<String>> listFiles({String? folder});
  
  /// 最後の同期時刻を取得
  DateTime? get lastSyncTime;
  
  /// 同期状態を確認
  bool get isSyncing;
  
  /// エラー状態を確認
  String? get lastError;
}

/// クラウドストレージサービスの種類
enum CloudStorageType {
  googleDrive,
  firebaseStorage,
  // 将来的に他のサービスも追加可能
}

/// バックアップの設定
class BackupConfig {
  final bool autoBackup;
  final Duration backupInterval;
  final int maxBackupFiles;
  final bool encryptData;
  
  const BackupConfig({
    this.autoBackup = false,
    this.backupInterval = const Duration(hours: 24),
    this.maxBackupFiles = 7,
    this.encryptData = true,
  });
  
  Map<String, dynamic> toJson() => {
    'autoBackup': autoBackup,
    'backupIntervalHours': backupInterval.inHours,
    'maxBackupFiles': maxBackupFiles,
    'encryptData': encryptData,
  };
  
  factory BackupConfig.fromJson(Map<String, dynamic> json) => BackupConfig(
    autoBackup: json['autoBackup'] ?? false,
    backupInterval: Duration(hours: json['backupIntervalHours'] ?? 24),
    maxBackupFiles: json['maxBackupFiles'] ?? 7,
    encryptData: json['encryptData'] ?? true,
  );
}

/// バックアップのメタデータ
class BackupMetadata {
  final String fileName;
  final DateTime createdAt;
  final int dataSize;
  final String checksum;
  final String version;
  
  const BackupMetadata({
    required this.fileName,
    required this.createdAt,
    required this.dataSize,
    required this.checksum,
    required this.version,
  });
  
  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'createdAt': createdAt.toIso8601String(),
    'dataSize': dataSize,
    'checksum': checksum,
    'version': version,
  };
  
  factory BackupMetadata.fromJson(Map<String, dynamic> json) => BackupMetadata(
    fileName: json['fileName'],
    createdAt: DateTime.parse(json['createdAt']),
    dataSize: json['dataSize'],
    checksum: json['checksum'],
    version: json['version'],
  );
}