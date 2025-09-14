import 'package:flutter/material.dart';
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
  static Future<bool> requestAllPermissions([BuildContext? context]) async {
    // 位置情報のパーミッションを要求
    final locationStatus = await Permission.location.request();
    if (locationStatus.isPermanentlyDenied) {
      // 永続的に拒否されている場合は設定画面を開くよう促す
      if (context != null) {
        await _showPermissionSettingsDialog(context, '位置情報');
      }
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
        if (context != null) {
          await _showPermissionSettingsDialog(context, 'バックグラウンド位置情報');
        }
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
      if (context != null) {
        await _showPermissionSettingsDialog(context, '通知');
      }
      return false;
    }
    if (!notificationStatus.isGranted) {
      return false;
    }

    // すべてのパーミッションが許可された
    return true;
  }

  /// 設定画面への遷移確認ダイアログを表示
  static Future<void> _showPermissionSettingsDialog(BuildContext context, String permissionName) async {
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('権限が必要です'),
          content: Text(
            '$permissionNameの権限が拒否されています。\n'
            'アプリの機能を正常に使用するため、設定画面で権限を許可してください。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('後で'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('設定を開く'),
            ),
          ],
        );
      },
    );

    if (shouldOpenSettings == true) {
      await openAppSettings();
    }
  }
}
