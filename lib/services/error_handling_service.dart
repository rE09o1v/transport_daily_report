import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

/// エラーハンドリング強化サービス
/// 
/// 全体的なエラーハンドリングを強化し、ユーザーフレンドリーなエラー表示を提供
/// - GPS失敗時の適切なフォールバック
/// - ネットワークエラー対応
/// - データ保存失敗時のリトライ処理
/// - ユーザーフレンドリーなエラーメッセージ
/// - エラーログの記録
class ErrorHandlingService {
  static const String _errorLogKey = 'error_log_history';
  static const int _maxErrorLogSize = 100; // 保存するエラーログの最大件数
  
  // シングルトンパターン
  static final ErrorHandlingService _instance = ErrorHandlingService._internal();
  factory ErrorHandlingService() => _instance;
  ErrorHandlingService._internal();

  // エラー通知用のStreamController
  final StreamController<AppError> _errorStreamController = StreamController<AppError>.broadcast();
  
  /// エラー通知ストリーム
  Stream<AppError> get errorStream => _errorStreamController.stream;

  /// GPS関連エラーのハンドリング
  Future<GPSErrorRecoveryResult> handleGpsError(
    GPSErrorType errorType, {
    String? context,
    dynamic originalError,
  }) async {
    AppLogger.error('GPS関連エラー発生: ${errorType.name}', 'ErrorHandlingService', originalError);
    
    final appError = AppError(
      type: AppErrorType.gps,
      code: errorType.name,
      message: _getGpsErrorMessage(errorType),
      context: context,
      timestamp: DateTime.now(),
      originalError: originalError,
    );
    
    // エラーを記録
    await _recordError(appError);
    
    // エラー通知を送信
    _errorStreamController.add(appError);
    
    // リカバリ処理を実行
    final recovery = await _executeGpsRecovery(errorType);
    
    return recovery;
  }

  /// ネットワーク関連エラーのハンドリング
  Future<NetworkErrorRecoveryResult> handleNetworkError(
    NetworkErrorType errorType, {
    String? context,
    dynamic originalError,
  }) async {
    AppLogger.error('ネットワーク関連エラー発生: ${errorType.name}', 'ErrorHandlingService', originalError);
    
    final appError = AppError(
      type: AppErrorType.network,
      code: errorType.name,
      message: _getNetworkErrorMessage(errorType),
      context: context,
      timestamp: DateTime.now(),
      originalError: originalError,
    );
    
    await _recordError(appError);
    _errorStreamController.add(appError);
    
    final recovery = await _executeNetworkRecovery(errorType);
    
    return recovery;
  }

  /// データ保存関連エラーのハンドリング
  Future<DataErrorRecoveryResult> handleDataError(
    DataErrorType errorType, {
    String? context,
    dynamic originalError,
    VoidCallback? retryCallback,
  }) async {
    AppLogger.error('データ関連エラー発生: ${errorType.name}', 'ErrorHandlingService', originalError);
    
    final appError = AppError(
      type: AppErrorType.data,
      code: errorType.name,
      message: _getDataErrorMessage(errorType),
      context: context,
      timestamp: DateTime.now(),
      originalError: originalError,
    );
    
    await _recordError(appError);
    _errorStreamController.add(appError);
    
    final recovery = await _executeDataRecovery(errorType, retryCallback: retryCallback);
    
    return recovery;
  }

  /// 汎用エラーのハンドリング
  Future<void> handleGenericError(
    String message, {
    String? context,
    dynamic originalError,
    AppErrorSeverity severity = AppErrorSeverity.medium,
  }) async {
    AppLogger.error('汎用エラー発生: $message', 'ErrorHandlingService', originalError);
    
    final appError = AppError(
      type: AppErrorType.generic,
      code: 'GENERIC_ERROR',
      message: message,
      context: context,
      timestamp: DateTime.now(),
      originalError: originalError,
      severity: severity,
    );
    
    await _recordError(appError);
    _errorStreamController.add(appError);
  }

  /// GPS関連のリカバリ処理
  Future<GPSErrorRecoveryResult> _executeGpsRecovery(GPSErrorType errorType) async {
    switch (errorType) {
      case GPSErrorType.permissionDenied:
        return GPSErrorRecoveryResult(
          success: false,
          fallbackAction: GPSFallbackAction.requestPermissionAgain,
          message: '設定画面から位置情報の権限を許可してください',
        );
      
      case GPSErrorType.serviceDisabled:
        return GPSErrorRecoveryResult(
          success: false,
          fallbackAction: GPSFallbackAction.enableLocationService,
          message: 'GPS機能を有効にしてください',
        );
      
      case GPSErrorType.signalWeak:
        return GPSErrorRecoveryResult(
          success: false,
          fallbackAction: GPSFallbackAction.switchToManualMode,
          message: 'GPS信号が弱いため、手動入力モードに切り替えました',
        );
      
      case GPSErrorType.timeout:
        // 自動的にリトライを試行
        await Future.delayed(const Duration(seconds: 2));
        return GPSErrorRecoveryResult(
          success: false,
          fallbackAction: GPSFallbackAction.retry,
          message: 'GPS取得がタイムアウトしました。もう一度お試しください',
        );
      
      case GPSErrorType.unknown:
        return GPSErrorRecoveryResult(
          success: false,
          fallbackAction: GPSFallbackAction.switchToManualMode,
          message: 'GPS記録でエラーが発生しました。手動入力をご利用ください',
        );
    }
  }

  /// ネットワーク関連のリカバリ処理
  Future<NetworkErrorRecoveryResult> _executeNetworkRecovery(NetworkErrorType errorType) async {
    switch (errorType) {
      case NetworkErrorType.connectionLost:
        // 接続チェックを行う
        final hasConnection = await _checkNetworkConnection();
        if (hasConnection) {
          return NetworkErrorRecoveryResult(
            success: true,
            fallbackAction: NetworkFallbackAction.retry,
            message: 'ネットワーク接続が復旧しました',
          );
        }
        return NetworkErrorRecoveryResult(
          success: false,
          fallbackAction: NetworkFallbackAction.offlineMode,
          message: 'オフラインモードで継続します',
        );
      
      case NetworkErrorType.timeout:
        return NetworkErrorRecoveryResult(
          success: false,
          fallbackAction: NetworkFallbackAction.retry,
          message: '通信がタイムアウトしました。もう一度お試しください',
        );
      
      case NetworkErrorType.serverError:
        return NetworkErrorRecoveryResult(
          success: false,
          fallbackAction: NetworkFallbackAction.offlineMode,
          message: 'サーバーエラーが発生しました。しばらく時間をおいてお試しください',
        );
    }
  }

  /// データ関連のリカバリ処理
  Future<DataErrorRecoveryResult> _executeDataRecovery(
    DataErrorType errorType, {
    VoidCallback? retryCallback,
  }) async {
    switch (errorType) {
      case DataErrorType.saveFailed:
        // 3回まで自動リトライ
        if (retryCallback != null) {
          for (int i = 0; i < 3; i++) {
            await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
            try {
              retryCallback();
              return DataErrorRecoveryResult(
                success: true,
                fallbackAction: DataFallbackAction.none,
                message: 'データの保存が完了しました',
              );
            } catch (e) {
              AppLogger.warning('データ保存リトライ失敗 (${i + 1}/3)', 'ErrorHandlingService');
              if (i == 2) {
                // 最後のリトライも失敗
                return DataErrorRecoveryResult(
                  success: false,
                  fallbackAction: DataFallbackAction.showManualSaveDialog,
                  message: 'データの保存に失敗しました。後で再度お試しください',
                );
              }
            }
          }
        }
        break;
      
      case DataErrorType.loadFailed:
        return DataErrorRecoveryResult(
          success: false,
          fallbackAction: DataFallbackAction.useDefaultData,
          message: 'データの読み込みに失敗しました。初期データで開始します',
        );
      
      case DataErrorType.corruption:
        return DataErrorRecoveryResult(
          success: false,
          fallbackAction: DataFallbackAction.resetData,
          message: 'データが破損しています。データをリセットしますか？',
        );
    }
    
    return DataErrorRecoveryResult(
      success: false,
      fallbackAction: DataFallbackAction.none,
      message: 'データエラーが発生しました',
    );
  }

  /// エラーログの記録
  Future<void> _recordError(AppError error) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingLogs = prefs.getStringList(_errorLogKey) ?? [];
      
      // 新しいエラーをログに追加
      final errorJson = error.toJson();
      existingLogs.add(errorJson);
      
      // ログサイズを制限
      if (existingLogs.length > _maxErrorLogSize) {
        existingLogs.removeRange(0, existingLogs.length - _maxErrorLogSize);
      }
      
      await prefs.setStringList(_errorLogKey, existingLogs);
    } catch (e) {
      AppLogger.error('エラーログの記録に失敗', 'ErrorHandlingService', e);
    }
  }

  /// エラーログの取得
  Future<List<AppError>> getErrorHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logStrings = prefs.getStringList(_errorLogKey) ?? [];
      
      return logStrings.map((jsonString) => AppError.fromJson(jsonString)).toList();
    } catch (e) {
      AppLogger.error('エラーログの取得に失敗', 'ErrorHandlingService', e);
      return [];
    }
  }

  /// エラーログのクリア
  Future<void> clearErrorHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_errorLogKey);
      AppLogger.info('エラーログをクリアしました', 'ErrorHandlingService');
    } catch (e) {
      AppLogger.error('エラーログのクリアに失敗', 'ErrorHandlingService', e);
    }
  }

  /// ネットワーク接続チェック（簡易実装）
  Future<bool> _checkNetworkConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// GPS関連エラーメッセージの取得
  String _getGpsErrorMessage(GPSErrorType errorType) {
    switch (errorType) {
      case GPSErrorType.permissionDenied:
        return 'GPS機能の利用許可が必要です';
      case GPSErrorType.serviceDisabled:
        return 'GPS機能が無効になっています';
      case GPSErrorType.signalWeak:
        return 'GPS信号が弱すぎます';
      case GPSErrorType.timeout:
        return 'GPS情報の取得がタイムアウトしました';
      case GPSErrorType.unknown:
        return 'GPS関連で不明なエラーが発生しました';
    }
  }

  /// ネットワーク関連エラーメッセージの取得
  String _getNetworkErrorMessage(NetworkErrorType errorType) {
    switch (errorType) {
      case NetworkErrorType.connectionLost:
        return 'ネットワーク接続が切断されました';
      case NetworkErrorType.timeout:
        return '通信がタイムアウトしました';
      case NetworkErrorType.serverError:
        return 'サーバーエラーが発生しました';
    }
  }

  /// データ関連エラーメッセージの取得
  String _getDataErrorMessage(DataErrorType errorType) {
    switch (errorType) {
      case DataErrorType.saveFailed:
        return 'データの保存に失敗しました';
      case DataErrorType.loadFailed:
        return 'データの読み込みに失敗しました';
      case DataErrorType.corruption:
        return 'データが破損しています';
    }
  }

  /// リソース解放
  void dispose() {
    _errorStreamController.close();
  }
}

// ============ データクラス・列挙型 ============

/// アプリエラー情報
class AppError {
  final AppErrorType type;
  final String code;
  final String message;
  final String? context;
  final DateTime timestamp;
  final dynamic originalError;
  final AppErrorSeverity severity;

  AppError({
    required this.type,
    required this.code,
    required this.message,
    this.context,
    required this.timestamp,
    this.originalError,
    this.severity = AppErrorSeverity.medium,
  });

  String toJson() {
    return '{'
        '"type": "${type.name}", '
        '"code": "$code", '
        '"message": "$message", '
        '"context": ${context != null ? '"$context"' : 'null'}, '
        '"timestamp": "${timestamp.toIso8601String()}", '
        '"severity": "${severity.name}"'
        '}';
  }

  static AppError fromJson(String jsonString) {
    // 簡易的なJSONパース（実際の実装では json パッケージを使用）
    final parts = jsonString.replaceAll('{', '').replaceAll('}', '').split(', ');
    final map = <String, String>{};
    
    for (final part in parts) {
      final keyValue = part.split('": ');
      if (keyValue.length == 2) {
        final key = keyValue[0].replaceAll('"', '');
        final value = keyValue[1].replaceAll('"', '');
        map[key] = value;
      }
    }
    
    return AppError(
      type: AppErrorType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => AppErrorType.generic,
      ),
      code: map['code'] ?? 'UNKNOWN',
      message: map['message'] ?? 'Unknown error',
      context: map['context'] != 'null' ? map['context'] : null,
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
      severity: AppErrorSeverity.values.firstWhere(
        (e) => e.name == map['severity'],
        orElse: () => AppErrorSeverity.medium,
      ),
    );
  }
}

/// アプリエラータイプ
enum AppErrorType {
  gps,
  network,
  data,
  generic,
}

/// エラー重要度
enum AppErrorSeverity {
  low,
  medium,
  high,
  critical,
}

/// GPS関連エラータイプ
enum GPSErrorType {
  permissionDenied,
  serviceDisabled,
  signalWeak,
  timeout,
  unknown,
}

/// ネットワーク関連エラータイプ
enum NetworkErrorType {
  connectionLost,
  timeout,
  serverError,
}

/// データ関連エラータイプ
enum DataErrorType {
  saveFailed,
  loadFailed,
  corruption,
}

/// GPS関連エラーのリカバリ結果
class GPSErrorRecoveryResult {
  final bool success;
  final GPSFallbackAction fallbackAction;
  final String message;

  GPSErrorRecoveryResult({
    required this.success,
    required this.fallbackAction,
    required this.message,
  });
}

/// GPS関連フォールバック処理
enum GPSFallbackAction {
  none,
  requestPermissionAgain,
  enableLocationService,
  switchToManualMode,
  retry,
}

/// ネットワーク関連エラーのリカバリ結果
class NetworkErrorRecoveryResult {
  final bool success;
  final NetworkFallbackAction fallbackAction;
  final String message;

  NetworkErrorRecoveryResult({
    required this.success,
    required this.fallbackAction,
    required this.message,
  });
}

/// ネットワーク関連フォールバック処理
enum NetworkFallbackAction {
  none,
  retry,
  offlineMode,
}

/// データ関連エラーのリカバリ結果
class DataErrorRecoveryResult {
  final bool success;
  final DataFallbackAction fallbackAction;
  final String message;

  DataErrorRecoveryResult({
    required this.success,
    required this.fallbackAction,
    required this.message,
  });
}

/// データ関連フォールバック処理
enum DataFallbackAction {
  none,
  useDefaultData,
  resetData,
  showManualSaveDialog,
}