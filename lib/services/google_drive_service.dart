import 'dart:async';
import 'dart:convert';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud_storage_interface.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';

/// Google Drive連携サービス
class GoogleDriveService implements CloudStorageInterface {
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: AppConfig.googleDriveScopes);
  drive.DriveApi? _driveApi;
  DateTime? _lastSyncTime;
  bool _isSyncing = false;
  String? _lastError;
  
  // アプリ専用フォルダ名
  String? _appFolderId;
  
  // 認証永続化のための追加フィールド
  GoogleSignInAccount? _cachedAccount;
  DateTime? _lastAuthCheck;
  int _authRetryCount = 0;
  static const int _maxAuthRetries = 3;
  static const Duration _authCheckInterval = Duration(minutes: 5);
  
  // 認証状態ストリーム管理
  final StreamController<GoogleSignInAccount?> _authStateController = 
      StreamController<GoogleSignInAccount?>.broadcast();
  Stream<GoogleSignInAccount?> get authStateChanges => _authStateController.stream;
  
  @override
  bool get isAuthenticated {
    // キャッシュされたアカウントと現在のアカウントの両方をチェック
    final currentAccount = _googleSignIn.currentUser;
    if (currentAccount != null) {
      _cachedAccount = currentAccount; // キャッシュを更新
      return true;
    }
    
    // キャッシュされたアカウントがある場合はそれも考慮
    return _cachedAccount != null;
  }
  
  @override
  String? get currentUser {
    final currentAccount = _googleSignIn.currentUser;
    if (currentAccount != null) {
      return currentAccount.displayName;
    }
    return _cachedAccount?.displayName;
  }
  
  @override
  DateTime? get lastSyncTime => _lastSyncTime;
  
  @override
  bool get isSyncing => _isSyncing;
  
  @override
  String? get lastError => _lastError;
  
  @override
  Future<bool> connect() async {
    try {
      _lastError = null;
      AppLogger.info('Google Drive接続を開始', 'GoogleDriveService');
      
      // 永続化された認証状態を読み込み
      await _loadPersistedAuthState();
      
      // 既に認証済みの場合は状態を通知
      final currentAccount = _googleSignIn.currentUser;
      if (currentAccount != null) {
        _authStateController.add(currentAccount);
      }
      
      // 設定の検証
      if (!ConfigValidator.validateGoogleDriveConfig()) {
        _lastError = 'Google Drive APIの設定が完了していません。GOOGLE_DRIVE_SETUP.mdを参照してください。';
        AppLogger.error(_lastError!, 'GoogleDriveService');
        AppLogger.error('現在の設定値: ${AppConfig.googleDriveClientId}', 'GoogleDriveService');
        return false;
      }
      
      AppLogger.info('Google Drive設定検証完了', 'GoogleDriveService');
      
      // 認証の試行（複数段階）
      GoogleSignInAccount? account = await _attemptAuthentication();
      
      if (account == null) {
        _lastError = 'Google Driveの認証に失敗しました';
        AppLogger.error(_lastError!, 'GoogleDriveService');
        return false;
      }
      
      // 認証情報をキャッシュ
      _cachedAccount = account;
      _lastAuthCheck = DateTime.now();
      _authRetryCount = 0;
      
      // 認証状態変更を通知
      _authStateController.add(account);
      
      // 認証情報を取得してDrive APIを初期化
      final success = await _initializeDriveApi(account);
      if (!success) {
        return false;
      }
      
      // アプリ専用フォルダを確保
      await _ensureAppFolder();
      
      // 最後の同期時刻を読み込み
      await _loadLastSyncTime();
      
      AppLogger.info('Google Driveに接続しました: ${account.displayName}', 'GoogleDriveService');
      
      // 認証状態を永続化
      await _saveAuthenticationState(account);
      
      return true;
    } catch (e) {
      _lastError = 'Google Drive接続エラー: $e';
      AppLogger.error(_lastError!, 'GoogleDriveService', e);
      return false;
    }
  }
  
  /// 認証を複数段階で試行
  Future<GoogleSignInAccount?> _attemptAuthentication() async {
    AppLogger.debug('認証試行を開始', 'GoogleDriveService');
    
    // 1. 既にサインイン済みかチェック
    GoogleSignInAccount? account = _googleSignIn.currentUser;
    if (account != null) {
      AppLogger.info('既存のサインイン状態を使用', 'GoogleDriveService');
      return account;
    }
    
    // 2. キャッシュされたアカウント情報をチェック
    if (_cachedAccount != null) {
      AppLogger.debug('キャッシュされたアカウント情報を確認', 'GoogleDriveService');
      // キャッシュが有効期限内かチェック
      if (_isAuthCacheValid()) {
        AppLogger.info('キャッシュされた認証を使用', 'GoogleDriveService');
        return _cachedAccount;
      }
    }
    
    // 3. サイレント認証を試行（リトライ付き）
    for (int i = 0; i < _maxAuthRetries; i++) {
      AppLogger.debug('サイレント認証試行 ${i + 1}/$_maxAuthRetries', 'GoogleDriveService');
      
      try {
        account = await _googleSignIn.signInSilently();
        if (account != null) {
          AppLogger.info('サイレント認証成功', 'GoogleDriveService');
          _authStateController.add(account);
          return account;
        }
      } catch (e) {
        AppLogger.warning('サイレント認証試行 ${i + 1} 失敗: $e', 'GoogleDriveService');
        if (i < _maxAuthRetries - 1) {
          // 短い待機時間を入れてリトライ
          await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
        }
      }
    }
    
    // 4. 手動認証を試行
    AppLogger.info('手動認証を試行', 'GoogleDriveService');
    try {
      account = await _googleSignIn.signIn();
      if (account != null) {
        AppLogger.info('手動認証成功', 'GoogleDriveService');
        _authStateController.add(account);
        return account;
      }
    } catch (e) {
      AppLogger.error('手動認証失敗', 'GoogleDriveService', e);
    }
    
    AppLogger.warning('すべての認証方法が失敗しました', 'GoogleDriveService');
    return null;
  }
  
  /// Drive API の初期化
  Future<bool> _initializeDriveApi(GoogleSignInAccount account) async {
    try {
      AppLogger.debug('Drive API初期化を開始', 'GoogleDriveService');
      
      // 認証情報を取得（リトライ付き）
      Map<String, String>? authHeaders;
      for (int i = 0; i < _maxAuthRetries; i++) {
        try {
          authHeaders = await account.authHeaders;
          break;
        } catch (e) {
          AppLogger.warning('認証ヘッダー取得試行 ${i + 1} 失敗: $e', 'GoogleDriveService');
          if (i < _maxAuthRetries - 1) {
            await Future.delayed(Duration(milliseconds: 1000 * (i + 1)));
          }
        }
      }
      
      if (authHeaders == null) {
        _lastError = '認証ヘッダーの取得に失敗しました';
        AppLogger.error(_lastError!, 'GoogleDriveService');
        return false;
      }
      
      final authenticateClient = GoogleAuthClient(authHeaders);
      
      // Drive APIクライアントを初期化
      _driveApi = drive.DriveApi(authenticateClient);
      
      AppLogger.info('Drive API初期化完了', 'GoogleDriveService');
      return true;
    } catch (e) {
      _lastError = 'Drive API初期化エラー: $e';
      AppLogger.error(_lastError!, 'GoogleDriveService', e);
      return false;
    }
  }
  
  /// 認証キャッシュの有効性をチェック
  bool _isAuthCacheValid() {
    if (_lastAuthCheck == null) return false;
    
    final now = DateTime.now();
    final timeSinceLastCheck = now.difference(_lastAuthCheck!);
    
    return timeSinceLastCheck < _authCheckInterval;
  }
  
  /// 認証状態を永続化
  Future<void> _saveAuthenticationState(GoogleSignInAccount account) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('google_drive_user_email', account.email);
      await prefs.setString('google_drive_user_name', account.displayName ?? '');
      await prefs.setString('google_drive_last_auth', DateTime.now().toIso8601String());
      
      AppLogger.debug('認証状態を永続化しました', 'GoogleDriveService');
    } catch (e) {
      AppLogger.warning('認証状態の永続化に失敗: $e', 'GoogleDriveService');
    }
  }
  
  /// 永続化された認証状態を読み込み
  Future<void> _loadPersistedAuthState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userEmail = prefs.getString('google_drive_user_email');
      final userName = prefs.getString('google_drive_user_name');
      final lastAuthStr = prefs.getString('google_drive_last_auth');
      
      if (userEmail != null && lastAuthStr != null) {
        final lastAuth = DateTime.tryParse(lastAuthStr);
        if (lastAuth != null) {
          _lastAuthCheck = lastAuth;
          AppLogger.debug('永続化された認証状態を読み込みました: $userEmail', 'GoogleDriveService');
        }
      }
    } catch (e) {
      AppLogger.warning('永続化された認証状態の読み込みに失敗: $e', 'GoogleDriveService');
    }
  }
  
  /// 認証をリフレッシュ
  Future<bool> refreshAuthentication() async {
    AppLogger.info('認証のリフレッシュを開始', 'GoogleDriveService');
    
    try {
      // 永続化された認証状態を読み込み
      await _loadPersistedAuthState();
      
      // まず現在のユーザーをチェック
      final currentUser = _googleSignIn.currentUser;
      if (currentUser != null) {
        AppLogger.info('既存の認証ユーザーを確認: ${currentUser.displayName}', 'GoogleDriveService');
        
        // Drive APIを初期化
        final success = await _initializeDriveApi(currentUser);
        if (success) {
          _cachedAccount = currentUser;
          _lastAuthCheck = DateTime.now();
          await _saveAuthenticationState(currentUser);
          _authStateController.add(currentUser);
          AppLogger.info('既存認証でリフレッシュ成功', 'GoogleDriveService');
          return true;
        }
      }
      
      // 認証を再試行
      final account = await _attemptAuthentication();
      if (account == null) {
        AppLogger.warning('認証リフレッシュに失敗', 'GoogleDriveService');
        return false;
      }
      
      // Drive APIを再初期化
      final success = await _initializeDriveApi(account);
      if (success) {
        _cachedAccount = account;
        _lastAuthCheck = DateTime.now();
        await _saveAuthenticationState(account);
        AppLogger.info('認証リフレッシュ成功', 'GoogleDriveService');
      }
      
      return success;
    } catch (e) {
      AppLogger.error('認証リフレッシュエラー', 'GoogleDriveService', e);
      return false;
    }
  }
  
  @override
  Future<void> disconnect() async {
    try {
      AppLogger.info('Google Driveから切断中', 'GoogleDriveService');
      
      await _googleSignIn.signOut();
      _driveApi = null;
      _appFolderId = null;
      _cachedAccount = null;
      _lastAuthCheck = null;
      _authRetryCount = 0;
      
      // 切断を通知
      _authStateController.add(null);
      
      // 永続化された認証状態をクリア
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('google_drive_user_email');
      await prefs.remove('google_drive_user_name');
      await prefs.remove('google_drive_last_auth');
      
      AppLogger.info('Google Driveから切断しました', 'GoogleDriveService');
    } catch (e) {
      AppLogger.error('切断エラー', 'GoogleDriveService', e);
    }
  }
  
  /// アプリ専用フォルダを確保
  Future<void> _ensureAppFolder() async {
    if (_driveApi == null) return;
    
    try {
      // 既存のフォルダを検索
      final query = "name='${AppConfig.backupFolderName}' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final fileList = await _driveApi!.files.list(q: query);
      
      if (fileList.files != null && fileList.files!.isNotEmpty) {
        _appFolderId = fileList.files!.first.id;
        AppLogger.info('既存のアプリフォルダを使用: $_appFolderId', 'GoogleDriveService');
      } else {
        // フォルダを新規作成
        final folder = drive.File()
          ..name = AppConfig.backupFolderName
          ..mimeType = 'application/vnd.google-apps.folder';
        
        final createdFolder = await _driveApi!.files.create(folder);
        _appFolderId = createdFolder.id;
        AppLogger.info('新しいアプリフォルダを作成: $_appFolderId', 'GoogleDriveService');
      }
    } catch (e) {
      throw Exception('アプリフォルダの作成に失敗: $e');
    }
  }
  
  @override
  Future<bool> uploadData(String fileName, String data, {String? folder}) async {
    if (_driveApi == null || _appFolderId == null) {
      _lastError = 'Google Driveに接続されていません';
      return false;
    }
    
    try {
      _isSyncing = true;
      _lastError = null;
      
      // ファイルの存在確認
      final existingFileId = await _findFileId(fileName, folder: folder);
      
      final file = drive.File()
        ..name = fileName
        ..parents = [folder ?? _appFolderId!];
      
      final media = drive.Media(
        Stream.value(utf8.encode(data)),
        data.length,
        contentType: 'application/json',
      );
      
      if (existingFileId != null) {
        // 既存ファイルを更新
        await _driveApi!.files.update(file, existingFileId, uploadMedia: media);
        AppLogger.info('ファイルを更新しました: $fileName', 'GoogleDriveService');
      } else {
        // 新規ファイルを作成
        await _driveApi!.files.create(file, uploadMedia: media);
        AppLogger.info('新規ファイルを作成しました: $fileName', 'GoogleDriveService');
      }
      
      await _saveLastSyncTime();
      return true;
    } catch (e) {
      _lastError = 'アップロードエラー: $e';
      AppLogger.error(_lastError!, 'GoogleDriveService', e);
      return false;
    } finally {
      _isSyncing = false;
    }
  }
  
  @override
  Future<String?> downloadData(String fileName, {String? folder}) async {
    if (_driveApi == null || _appFolderId == null) {
      _lastError = 'Google Driveに接続されていません';
      return null;
    }
    
    try {
      _isSyncing = true;
      _lastError = null;
      
      final fileId = await _findFileId(fileName, folder: folder);
      if (fileId == null) {
        AppLogger.warning('ファイルが見つかりません: $fileName', 'GoogleDriveService');
        return null;
      }
      
      final media = await _driveApi!.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final dataBytes = <int>[];
      
      await for (final chunk in media.stream) {
        dataBytes.addAll(chunk);
      }
      
      final data = utf8.decode(dataBytes);
      AppLogger.info('ファイルをダウンロードしました: $fileName', 'GoogleDriveService');
      return data;
    } catch (e) {
      _lastError = 'ダウンロードエラー: $e';
      AppLogger.error(_lastError!, 'GoogleDriveService', e);
      return null;
    } finally {
      _isSyncing = false;
    }
  }
  
  @override
  Future<bool> fileExists(String fileName, {String? folder}) async {
    if (_driveApi == null || _appFolderId == null) return false;
    
    try {
      final fileId = await _findFileId(fileName, folder: folder);
      return fileId != null;
    } catch (e) {
      AppLogger.error('ファイル存在確認エラー', 'GoogleDriveService', e);
      return false;
    }
  }
  
  @override
  Future<bool> deleteFile(String fileName, {String? folder}) async {
    if (_driveApi == null || _appFolderId == null) {
      _lastError = 'Google Driveに接続されていません';
      return false;
    }
    
    try {
      final fileId = await _findFileId(fileName, folder: folder);
      if (fileId == null) {
        AppLogger.warning('削除対象のファイルが見つかりません: $fileName', 'GoogleDriveService');
        return false;
      }
      
      await _driveApi!.files.delete(fileId);
      AppLogger.info('ファイルを削除しました: $fileName', 'GoogleDriveService');
      return true;
    } catch (e) {
      _lastError = 'ファイル削除エラー: $e';
      AppLogger.error(_lastError!, 'GoogleDriveService', e);
      return false;
    }
  }
  
  @override
  Future<List<String>> listFiles({String? folder}) async {
    if (_driveApi == null || _appFolderId == null) return [];
    
    try {
      final parentId = folder ?? _appFolderId!;
      final query = "'$parentId' in parents and trashed=false";
      final fileList = await _driveApi!.files.list(q: query);
      
      return fileList.files?.map((file) => file.name ?? '').where((name) => name.isNotEmpty).toList() ?? [];
    } catch (e) {
      AppLogger.error('ファイル一覧取得エラー', 'GoogleDriveService', e);
      return [];
    }
  }
  
  /// ファイルIDを検索
  Future<String?> _findFileId(String fileName, {String? folder}) async {
    final parentId = folder ?? _appFolderId!;
    final query = "name='$fileName' and '$parentId' in parents and trashed=false";
    
    final fileList = await _driveApi!.files.list(q: query);
    return fileList.files?.isNotEmpty == true ? fileList.files!.first.id : null;
  }
  
  /// 最後の同期時刻を保存
  Future<void> _saveLastSyncTime() async {
    _lastSyncTime = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('google_drive_last_sync', _lastSyncTime!.toIso8601String());
  }
  
  /// 最後の同期時刻を読み込み
  Future<void> _loadLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final syncTimeStr = prefs.getString('google_drive_last_sync');
    if (syncTimeStr != null) {
      _lastSyncTime = DateTime.tryParse(syncTimeStr);
    }
  }
  
  /// リソースを解放
  void dispose() {
    _authStateController.close();
  }
}

/// Google認証用のHTTPクライアント
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();
  
  GoogleAuthClient(this._headers);
  
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
  
  @override
  void close() {
    _client.close();
  }
}

