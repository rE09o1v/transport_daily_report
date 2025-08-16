import 'dart:convert';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud_storage_interface.dart';
import '../config/app_config.dart';

/// Google Drive連携サービス
class GoogleDriveService implements CloudStorageInterface {
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: AppConfig.googleDriveScopes);
  drive.DriveApi? _driveApi;
  DateTime? _lastSyncTime;
  bool _isSyncing = false;
  String? _lastError;
  
  // アプリ専用フォルダ名
  String? _appFolderId;
  
  @override
  bool get isAuthenticated => _googleSignIn.currentUser != null;
  
  @override
  String? get currentUser => _googleSignIn.currentUser?.displayName;
  
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
      
      // 設定の検証
      if (!ConfigValidator.validateGoogleDriveConfig()) {
        _lastError = 'Google Drive APIの設定が完了していません。GOOGLE_DRIVE_SETUP.mdを参照してください。';
        return false;
      }
      
      // 既にサインイン済みかチェック
      GoogleSignInAccount? account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signInSilently();
      account ??= await _googleSignIn.signIn();
      
      if (account == null) {
        _lastError = 'ユーザーがサインインをキャンセルしました';
        return false;
      }
      
      // 認証情報を取得
      final authHeaders = await account.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      
      // Drive APIクライアントを初期化
      _driveApi = drive.DriveApi(authenticateClient);
      
      // アプリ専用フォルダを確保
      await _ensureAppFolder();
      
      // 最後の同期時刻を読み込み
      await _loadLastSyncTime();
      
      print('Google Driveに接続しました: ${account.displayName}');
      return true;
    } catch (e) {
      _lastError = 'Google Drive接続エラー: $e';
      print(_lastError);
      return false;
    }
  }
  
  @override
  Future<void> disconnect() async {
    try {
      await _googleSignIn.signOut();
      _driveApi = null;
      _appFolderId = null;
      print('Google Driveから切断しました');
    } catch (e) {
      print('切断エラー: $e');
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
        print('既存のアプリフォルダを使用: $_appFolderId');
      } else {
        // フォルダを新規作成
        final folder = drive.File()
          ..name = AppConfig.backupFolderName
          ..mimeType = 'application/vnd.google-apps.folder';
        
        final createdFolder = await _driveApi!.files.create(folder);
        _appFolderId = createdFolder.id;
        print('新しいアプリフォルダを作成: $_appFolderId');
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
        print('ファイルを更新しました: $fileName');
      } else {
        // 新規ファイルを作成
        await _driveApi!.files.create(file, uploadMedia: media);
        print('新規ファイルを作成しました: $fileName');
      }
      
      await _saveLastSyncTime();
      return true;
    } catch (e) {
      _lastError = 'アップロードエラー: $e';
      print(_lastError);
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
        print('ファイルが見つかりません: $fileName');
        return null;
      }
      
      final media = await _driveApi!.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final dataBytes = <int>[];
      
      await for (final chunk in media.stream) {
        dataBytes.addAll(chunk);
      }
      
      final data = utf8.decode(dataBytes);
      print('ファイルをダウンロードしました: $fileName');
      return data;
    } catch (e) {
      _lastError = 'ダウンロードエラー: $e';
      print(_lastError);
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
      print('ファイル存在確認エラー: $e');
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
        print('削除対象のファイルが見つかりません: $fileName');
        return false;
      }
      
      await _driveApi!.files.delete(fileId);
      print('ファイルを削除しました: $fileName');
      return true;
    } catch (e) {
      _lastError = 'ファイル削除エラー: $e';
      print(_lastError);
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
      print('ファイル一覧取得エラー: $e');
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