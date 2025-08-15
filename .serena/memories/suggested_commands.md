# 推奨開発コマンド（Windows環境）

## 基本開発コマンド

### プロジェクト環境確認
```bash
flutter doctor              # Flutter環境の確認
flutter doctor -v           # 詳細環境情報表示
flutter --version           # Flutterバージョン確認
```

### 依存関係管理
```bash
flutter pub get             # 依存関係取得
flutter pub upgrade         # 依存関係更新
flutter pub outdated        # 更新可能パッケージ確認
```

### 開発・実行
```bash
flutter run                 # デフォルトデバイスで実行
flutter run -d chrome       # Web開発（推奨）
flutter run -d windows      # Windows向け実行
flutter run --hot           # ホットリロード有効
flutter run --release       # リリースモードで実行
```

### 品質管理・テスト
```bash
flutter analyze             # 静的解析（Lint警告表示）
flutter test               # テスト実行
flutter test --coverage    # カバレッジ付きテスト
```

### ビルド
```bash
flutter build apk          # Android APKビルド
flutter build web          # Webビルド
flutter build windows      # Windows実行ファイル
flutter build ios          # iOS（macOSでのみ実行可能）
```

### デバッグ・クリーン
```bash
flutter clean              # ビルドキャッシュクリア
flutter pub cache repair   # Pub依存関係修復
```

## Windows環境特有のコマンド
```cmd
dir                        # ファイル・ディレクトリ一覧
cd [path]                  # ディレクトリ移動
type [file]                # ファイル内容表示
findstr [pattern] [file]   # パターン検索
```

## 推奨ワークフロー
1. `flutter pub get` - 依存関係取得
2. `flutter analyze` - コード品質確認
3. `flutter run -d chrome` - Web開発
4. `flutter test` - テスト実行
5. `flutter build [target]` - ビルド実行

## 注意事項
- 現在122件のlint警告あり（主にprint文使用）
- Android Licensesが未承認（flutter doctor --android-licensesで解決）