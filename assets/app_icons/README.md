# アプリアイコン用ディレクトリ

このディレクトリには、アプリケーションのアイコンファイルを格納します。

## 含まれるファイル
- `app_icon.png` - アプリアイコンとして使用する丸い画像（基本アイコン）
- `app_icon_round.png` - アプリアイコンとして使用する丸い画像（同じ画像）

## アプリアイコン設定について
このプロジェクトでは、以下のディレクトリにアイコンを配置しています：

### Android
- `android/app/src/main/res/mipmap-mdpi/ic_launcher.png` (48x48 px)
- `android/app/src/main/res/mipmap-hdpi/ic_launcher.png` (72x72 px)
- `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png` (96x96 px)
- `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` (144x144 px)
- `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` (192x192 px)

ラウンドアイコン用にも以下のファイルを配置しています：
- `android/app/src/main/res/mipmap-mdpi/ic_launcher_round.png` (48x48 px)
- `android/app/src/main/res/mipmap-hdpi/ic_launcher_round.png` (72x72 px)
- `android/app/src/main/res/mipmap-xhdpi/ic_launcher_round.png` (96x96 px)
- `android/app/src/main/res/mipmap-xxhdpi/ic_launcher_round.png` (144x144 px)
- `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png` (192x192 px)

### iOS
iOSアイコンは以下のディレクトリに配置しています：
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

以下のサイズのアイコンが含まれています：
- App Store (1024x1024 px)
- iPhone (60x60, 120x120, 180x180 px)
- iPad (76x76, 152x152, 167x167 px)
- Notifications (20x20, 40x40, 60x60 px)
- Settings (29x29, 58x58, 87x87 px)
- Spotlight (40x40, 80x80, 120x120 px)

アイコンの変更が必要な場合は、上記の各ディレクトリのファイルを更新してください。

## アイコンについて
現在のアプリアイコンは丸いアイコンに統一されています。すべてのプラットフォームで同じ丸いアイコンが使用されます。 