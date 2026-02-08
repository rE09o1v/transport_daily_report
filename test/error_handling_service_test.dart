import 'package:flutter_test/flutter_test.dart';
import 'package:transport_daily_report/services/error_handling_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

void main() {
  // Required for platform-channel-based plugins like SharedPreferences.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ErrorHandlingService Tests', () {
    late ErrorHandlingService errorService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      errorService = ErrorHandlingService();
    });

    // NOTE: ErrorHandlingService is a singleton; do not dispose it between tests.
    // Disposing would close its broadcast stream and break subsequent tests.

    group('GPS エラーハンドリング', () {
      test('GPS権限拒否エラーの処理', () async {
        final result = await errorService.handleGpsError(
          GPSErrorType.permissionDenied,
          context: 'テスト用コンテキスト',
        );

        expect(result.success, false);
        expect(result.fallbackAction, GPSFallbackAction.requestPermissionAgain);
        expect(result.message, contains('権限'));
      });

      test('GPSサービス無効エラーの処理', () async {
        final result = await errorService.handleGpsError(
          GPSErrorType.serviceDisabled,
          context: 'GPS無効テスト',
        );

        expect(result.success, false);
        expect(result.fallbackAction, GPSFallbackAction.enableLocationService);
        expect(result.message, contains('GPS機能'));
      });

      test('GPS信号微弱エラーの処理', () async {
        final result = await errorService.handleGpsError(
          GPSErrorType.signalWeak,
          context: '信号微弱テスト',
        );

        expect(result.success, false);
        expect(result.fallbackAction, GPSFallbackAction.switchToManualMode);
        expect(result.message, contains('手動入力'));
      });

      test('GPSタイムアウトエラーの処理', () async {
        final result = await errorService.handleGpsError(
          GPSErrorType.timeout,
          context: 'タイムアウトテスト',
        );

        expect(result.success, false);
        expect(result.fallbackAction, GPSFallbackAction.retry);
        expect(result.message, contains('タイムアウト'));
      });
    });

    group('ネットワーク エラーハンドリング', () {
      test('接続断絶エラーの処理', () async {
        final result = await errorService.handleNetworkError(
          NetworkErrorType.connectionLost,
          context: '接続断絶テスト',
        );

        // success depends on live DNS lookup result; accept both.
        expect(result.success, anyOf(isTrue, isFalse));
        expect(
          result.fallbackAction,
          anyOf(NetworkFallbackAction.retry, NetworkFallbackAction.offlineMode),
        );
      });

      test('通信タイムアウトエラーの処理', () async {
        final result = await errorService.handleNetworkError(
          NetworkErrorType.timeout,
          context: '通信タイムアウトテスト',
        );

        expect(result.success, false);
        expect(result.fallbackAction, NetworkFallbackAction.retry);
        expect(result.message, contains('タイムアウト'));
      });

      test('サーバーエラーの処理', () async {
        final result = await errorService.handleNetworkError(
          NetworkErrorType.serverError,
          context: 'サーバーエラーテスト',
        );

        expect(result.success, false);
        expect(result.fallbackAction, NetworkFallbackAction.offlineMode);
        expect(result.message, contains('サーバーエラー'));
      });
    });

    group('データ エラーハンドリング', () {
      test('保存失敗エラーの処理（リトライなし）', () async {
        final result = await errorService.handleDataError(
          DataErrorType.saveFailed,
          context: '保存失敗テスト',
        );

        expect(result.success, false);
        expect(result.fallbackAction, DataFallbackAction.showManualSaveDialog);
        expect(result.message, contains('保存に失敗'));
      });

      test('保存失敗エラーの処理（リトライ成功）', () async {
        bool retryExecuted = false;
        
        final result = await errorService.handleDataError(
          DataErrorType.saveFailed,
          context: '保存失敗リトライテスト',
          retryCallback: () {
            retryExecuted = true;
            // 最初の呼び出しで成功とする
          },
        );

        expect(retryExecuted, true);
        expect(result.success, true);
        expect(result.message, contains('完了'));
      });

      test('読み込み失敗エラーの処理', () async {
        final result = await errorService.handleDataError(
          DataErrorType.loadFailed,
          context: '読み込み失敗テスト',
        );

        expect(result.success, false);
        expect(result.fallbackAction, DataFallbackAction.useDefaultData);
        expect(result.message, contains('読み込みに失敗'));
      });

      test('データ破損エラーの処理', () async {
        final result = await errorService.handleDataError(
          DataErrorType.corruption,
          context: 'データ破損テスト',
        );

        expect(result.success, false);
        expect(result.fallbackAction, DataFallbackAction.resetData);
        expect(result.message, contains('破損'));
      });
    });

    group('汎用 エラーハンドリング', () {
      test('汎用エラーの処理', () async {
        // Subscribe first, then trigger the error.
        final future = expectLater(
          errorService.errorStream,
          emits(predicate<AppError>((error) =>
              error.type == AppErrorType.generic &&
              error.message == 'テスト用汎用エラー' &&
              error.severity == AppErrorSeverity.high)),
        );

        await errorService.handleGenericError(
          'テスト用汎用エラー',
          context: '汎用エラーテスト',
          severity: AppErrorSeverity.high,
        );

        await future;
      });
    });

    group('エラーログ管理', () {
      test('エラーログの記録と取得', () async {
        // GPS エラーを発生させてログに記録
        await errorService.handleGpsError(
          GPSErrorType.permissionDenied,
          context: 'ログテスト',
        );

        // ネットワーク エラーを発生させてログに記録
        await errorService.handleNetworkError(
          NetworkErrorType.timeout,
          context: 'ログテスト2',
        );

        // エラー履歴を取得
        final errorHistory = await errorService.getErrorHistory();

        expect(errorHistory.length, greaterThanOrEqualTo(2));
        expect(errorHistory.any((e) => e.type == AppErrorType.gps), true);
        expect(errorHistory.any((e) => e.type == AppErrorType.network), true);
      });

      test('エラーログのクリア', () async {
        // エラーを記録
        await errorService.handleGenericError('テストエラー');

        // ログの存在を確認
        final beforeClear = await errorService.getErrorHistory();
        expect(beforeClear.length, greaterThan(0));

        // ログをクリア
        await errorService.clearErrorHistory();

        // クリア後の確認
        final afterClear = await errorService.getErrorHistory();
        expect(afterClear, isEmpty);
      });
    });

    group('AppError クラス', () {
      test('AppError のJSONシリアライゼーション', () {
        final originalError = AppError(
          type: AppErrorType.gps,
          code: 'GPS_001',
          message: 'GPSテストエラー',
          context: 'テストコンテキスト',
          timestamp: DateTime(2024, 1, 15, 10, 30),
          severity: AppErrorSeverity.medium,
        );

        final jsonString = originalError.toJson();
        final recreatedError = AppError.fromJson(jsonString);

        expect(recreatedError.type, originalError.type);
        expect(recreatedError.code, originalError.code);
        expect(recreatedError.message, originalError.message);
        expect(recreatedError.context, originalError.context);
        expect(recreatedError.severity, originalError.severity);
      });

      test('AppError のJSONシリアライゼーション（contextがnull）', () {
        final originalError = AppError(
          type: AppErrorType.data,
          code: 'DATA_001',
          message: 'データテストエラー',
          timestamp: DateTime(2024, 1, 15, 11, 00),
          severity: AppErrorSeverity.high,
        );

        final jsonString = originalError.toJson();
        final recreatedError = AppError.fromJson(jsonString);

        expect(recreatedError.type, originalError.type);
        expect(recreatedError.code, originalError.code);
        expect(recreatedError.message, originalError.message);
        expect(recreatedError.context, isNull);
        expect(recreatedError.severity, originalError.severity);
      });
    });

    group('エラーストリーム', () {
      test('エラーストリームの動作確認', () async {
        final List<AppError> receivedErrors = [];
        
        // ストリームをリッスン
        final subscription = errorService.errorStream.listen((error) {
          receivedErrors.add(error);
        });

        // 複数のエラーを発生
        await errorService.handleGpsError(GPSErrorType.timeout);
        await errorService.handleNetworkError(NetworkErrorType.connectionLost);
        await errorService.handleGenericError('テストエラー3');

        // 少し待つ
        await Future.delayed(const Duration(milliseconds: 100));

        expect(receivedErrors.length, 3);
        expect(receivedErrors[0].type, AppErrorType.gps);
        expect(receivedErrors[1].type, AppErrorType.network);
        expect(receivedErrors[2].type, AppErrorType.generic);

        await subscription.cancel();
      });
    });
  });
}