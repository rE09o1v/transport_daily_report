import 'package:permission_handler/permission_handler.dart';

/// パーミッションを管理するサービスクラス
class PermissionService {
  /// アプリケーションに必要なすべてのパーミッションを要求する
  ///
  /// 必要なパーミッション:
  /// - 位置情報 (常に許可)
  /// - 通知
  ///
  /// すべてのパーミッションが許可された場合は `true` を返す。
  /// 1つでも拒否された場合は `false` を返す。
  static Future<bool> requestAllPermissions() async {
    // 位置情報のパーミッションを要求
    final locationStatus = await Permission.location.request();
    if (locationStatus.isPermanentlyDenied) {
      // 永続的に拒否されている場合は設定画面を開くよう促す
      await openAppSettings();
      return false;
    }
    if (!locationStatus.isGranted) {
      return false;
    }

    // バックグラウンドでの位置情報アクセスを要求
    // `location`が許可されている場合のみ要求可能
    if (locationStatus.isGranted) {
      final backgroundLocationStatus = await Permission.locationAlways.request();
      if (backgroundLocationStatus.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      if (!backgroundLocationStatus.isGranted) {
        // バックグラウンドが必須でない場合、ここではfalseを返さずに
        // 機能制限で対応することもできるが、今回は必須とする
        return false;
      }
    }

    // 通知のパーミッションを要求
    final notificationStatus = await Permission.notification.request();
    if (notificationStatus.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    if (!notificationStatus.isGranted) {
      return false;
    }

    // すべてのパーミッションが許可された
    return true;
  }
}
