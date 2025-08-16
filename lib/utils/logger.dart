import 'package:flutter/foundation.dart';

/// アプリケーション用の統一されたロギングシステム
class AppLogger {
  static const String _tag = 'TransportDailyReport';

  /// デバッグレベルのログ
  static void debug(String message, [String? tag]) {
    if (kDebugMode) {
      debugPrint('${_formatLog('DEBUG', tag ?? _tag, message)}');
    }
  }

  /// 情報レベルのログ
  static void info(String message, [String? tag]) {
    if (kDebugMode) {
      debugPrint('${_formatLog('INFO', tag ?? _tag, message)}');
    }
  }

  /// 警告レベルのログ
  static void warning(String message, [String? tag]) {
    if (kDebugMode) {
      debugPrint('${_formatLog('WARNING', tag ?? _tag, message)}');
    }
  }

  /// エラーレベルのログ
  static void error(String message, [String? tag, dynamic error]) {
    if (kDebugMode) {
      final errorMessage = error != null ? '$message: $error' : message;
      debugPrint('${_formatLog('ERROR', tag ?? _tag, errorMessage)}');
    }
  }

  /// ログフォーマット統一
  static String _formatLog(String level, String tag, String message) {
    final timestamp = DateTime.now().toIso8601String();
    return '[$timestamp] [$level] [$tag] $message';
  }
}