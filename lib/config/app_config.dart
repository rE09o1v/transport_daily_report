import '../utils/logger.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// アプリケーション設定
class AppConfig {
  // Google Drive API設定（Android用）
  // AndroidのOAuth Client IDを設定してください
  // 例: "123456789-abcdefghijklmnop.apps.googleusercontent.com"
  // dotenvとString.fromEnvironmentの両方に対応
  static String get googleDriveClientId {
    // まずString.fromEnvironmentを試す（--dart-define使用時）
    const dartDefineValue = String.fromEnvironment('GOOGLE_DRIVE_CLIENT_ID');
    if (dartDefineValue.isNotEmpty && dartDefineValue != 'YOUR_ANDROID_OAUTH_CLIENT_ID_HERE') {
      return dartDefineValue;
    }
    
    // 次にdotenvを試す（.envファイル使用時）
    try {
      final envValue = dotenv.env['GOOGLE_DRIVE_CLIENT_ID'];
      if (envValue != null && envValue.isNotEmpty) {
        return envValue;
      }
    } catch (e) {
      // dotenvが初期化されていない場合は無視
    }
    
    // デフォルト値
    return 'YOUR_ANDROID_OAUTH_CLIENT_ID_HERE';
  }
  
  // Android版ではClient Secretは不要です
  static const String googleDriveClientSecret = '';
  
  // Firebase設定（firebase_optionsから自動生成）
  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'your-firebase-project-id',
  );
  
  // アプリ情報
  static const String appName = 'Transport Daily Report';
  static const String appVersion = '1.2.0';
  
  // Google Drive設定
  static const List<String> googleDriveScopes = [
    'https://www.googleapis.com/auth/drive.file',
  ];
  
  // バックアップ設定
  static const String backupFolderName = 'Transport Daily Report';
  static const Duration defaultBackupInterval = Duration(hours: 24);
  static const int defaultMaxBackupFiles = 7;
  
  // 開発モード判定
  static bool get isDebugMode {
    // まずString.fromEnvironmentを試す
    const dartDefineValue = bool.fromEnvironment('DEBUG_MODE', defaultValue: false);
    if (dartDefineValue != false) {
      return dartDefineValue;
    }
    
    // 次にdotenvを試す
    try {
      final envValue = dotenv.env['DEBUG_MODE'];
      if (envValue != null) {
        return envValue.toLowerCase() == 'true';
      }
    } catch (e) {
      // dotenvが初期化されていない場合は無視
    }
    
    // デフォルトはtrue（開発モード）
    return true;
  }
  
  // ログレベル
  static const bool enableDetailedLogging = bool.fromEnvironment('DETAILED_LOGGING', defaultValue: false);
}

/// 設定値の検証
class ConfigValidator {
  static bool validateGoogleDriveConfig() {
    if (AppConfig.googleDriveClientId == 'YOUR_ANDROID_OAUTH_CLIENT_ID_HERE') {
      AppLogger.warning('Android OAuth Client IDが設定されていません', 'ConfigValidator');
      AppLogger.info('GOOGLE_DRIVE_SETUP.mdの手順に従って設定してください', 'ConfigValidator');
      return false;
    }
    
    if (!AppConfig.googleDriveClientId.contains('.apps.googleusercontent.com')) {
      AppLogger.warning('Client IDの形式が正しくありません', 'ConfigValidator');
      AppLogger.info('正しい形式: "123456789-abcdef.apps.googleusercontent.com"', 'ConfigValidator');
      return false;
    }
    
    return true;
  }
  
  static void printConfigStatus() {
    AppLogger.info('=== アプリ設定状況 ===', 'ConfigValidator');
    AppLogger.info('アプリ名: ${AppConfig.appName}', 'ConfigValidator');
    AppLogger.info('バージョン: ${AppConfig.appVersion}', 'ConfigValidator');
    AppLogger.info('デバッグモード: ${AppConfig.isDebugMode}', 'ConfigValidator');
    AppLogger.info('Google Drive設定: ${validateGoogleDriveConfig() ? "✅ 設定済み" : "❌ 未設定"}', 'ConfigValidator');
    AppLogger.info('Firebase Project ID: ${AppConfig.firebaseProjectId}', 'ConfigValidator');
    AppLogger.info('==================', 'ConfigValidator');
  }
}