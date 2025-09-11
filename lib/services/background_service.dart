import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_daily_report/models/mileage_record.dart';

const String notificationChannelId = 'gps_tracking_channel';
const String notificationChannelName = 'GPS Tracking';
const String notificationChannelDescription = 'Shows the status of GPS distance tracking.';
const int notificationId = 888;

/// バックグラウンドサービスを初期化する
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  // 通知チャンネルを作成
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId,
    notificationChannelName,
    description: notificationChannelDescription,
    importance: Importance.low, // 常駐通知のためlowに設定
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'GPS追跡サービス',
      initialNotificationContent: '初期化しています...',
      foregroundServiceNotificationId: notificationId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onBackground,
    ),
  );
}

/// iOSのバックグラウンド処理エントリポイント
@pragma('vm:entry-point')
Future<bool> onBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // iOSのバックグラウンド処理はここでは実装しない
  return true;
}

/// バックグラウンドサービスのメインエントリポイント
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // サービスがフォアグラウンドで実行されていることを通知
  service.on('setAsForeground').listen((event) {
    // service.setAsForegroundService(); // メソッドが存在しないためコメントアウト
  });

  // サービスがバックグラウンドに移行したことを通知
  service.on('setAsBackground').listen((event) {
    // service.setAsBackgroundService(); // メソッドが存在しないためコメントアウト
  });

  // サービスを停止する
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // ここからGPS追跡ロジックを開始する
  // 追跡ロジックは後ほど実装
  Timer.periodic(const Duration(seconds: 5), (timer) async {
    //
    // TODO: 実際のGPS追跡ロジックをここに実装する
    // 1. Geolocatorのストリームを購読
    // 2. 位置情報を取得
    // 3. 距離を計算
    // 4. SharedPreferencesに保存
    // 5. 通知を更新
    // 6. UIにデータを送信
    //

    final prefs = await SharedPreferences.getInstance();
    double currentDistance = prefs.getDouble('current_distance') ?? 0;

    // ダミーで距離を増やす
    // currentDistance += 0.01;
    // await prefs.setDouble('current_distance', currentDistance);

    flutterLocalNotificationsPlugin.show(
      notificationId,
      '走行距離の記録中',
      '現在の走行距離: ${currentDistance.toStringAsFixed(2)} km',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          notificationChannelId,
          notificationChannelName,
          channelDescription: notificationChannelDescription,
          icon: 'ic_bg_service_small', // TODO: このアイコンを `android/app/src/main/res/drawable` に追加する必要がある
          ongoing: true,
          importance: Importance.low,
          priority: Priority.low,
        ),
      ),
    );

    // UIにデータを送信
    service.invoke(
      'update',
      {
        "current_distance": currentDistance,
      },
    );
  });
}
