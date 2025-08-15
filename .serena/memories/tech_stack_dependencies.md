# 技術スタックと依存関係

## Flutter/Dart バージョン
- **Flutter**: 3.29.3 (Stable Channel)
- **Dart**: ^3.7.2
- **アプリバージョン**: 1.1.1+3

## 主要依存関係
### 位置情報・地図
- `geolocator: ^14.0.0` - GPS位置情報取得
- `permission_handler: ^12.0.0+1` - 位置情報権限管理
- `flutter_map: ^7.0.2` - マップ表示
- `latlong2: ^0.9.1` - 座標計算

### ストレージ・データ管理
- `shared_preferences: ^2.2.2` - 軽量データ保存
- `path_provider: ^2.1.5` - ファイルパス取得

### PDF・共有機能
- `pdf: ^3.11.3` - PDF生成
- `share_plus: ^11.0.0` - ファイル共有
- `url_launcher: ^6.3.1` - 外部アプリ起動

### 国際化・UI
- `flutter_localizations: (SDK)` - 多言語対応
- `intl: ^0.19.0` - 日付・数値フォーマット
- `cupertino_icons: ^1.0.8` - アイコンセット

### 開発・品質管理
- `flutter_test: (SDK)` - テストフレームワーク
- `flutter_lints: ^5.0.0` - Dart/Flutter推奨Lintルール

## カスタムフォント
- **IPAexGothic**: 日本語フォント（assets/fonts/ipaexg.ttf）

## アセット構成
- `assets/fonts/` - フォントファイル
- `assets/app_icons/` - アプリケーションアイコン

## プラットフォーム対応
全プラットフォーム（Android, iOS, Web, Windows, macOS, Linux）でビルド可能