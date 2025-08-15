# コードスタイルと開発規約

## Lintルール設定
- **基本ルール**: `package:flutter_lints/flutter.yaml`
- **設定ファイル**: `analysis_options.yaml`
- **追加ルール**: 現在はデフォルト設定を使用

## コーディング規約

### 命名規則
- **クラス名**: PascalCase（例：`Client`, `VisitRecord`）
- **ファイル名**: snake_case（例：`client.dart`, `visit_record.dart`）
- **メソッド・変数**: camelCase（例：`getCurrentLocation`, `visitRecords`）
- **定数**: lowerCamelCase（例：`defaultTimeout`）

### ファイル構成
```dart
// インポート順序
1. Dart core libraries
2. Flutter libraries  
3. Third-party packages
4. 相対インポート

// クラス構成
1. フィールド（プロパティ）
2. コンストラクタ
3. メソッド（public → private）
4. Static methods
```

### データモデル規約
- **JSON変換**: `toJson()` / `fromJson()` メソッド実装
- **不変性**: finalフィールドを優先
- **nullサフティ**: 適切な null 許可設定

### UI開発規約
- **StatelessWidget**: 状態を持たないウィジェット優先
- **StatefulWidget**: 状態管理が必要な場合のみ
- **Builder pattern**: 複雑なUIは分割して構築
- **const constructor**: パフォーマンス向上のため積極使用

### 国際化対応
- **言語**: 日本語メッセージ
- **ロケール**: flutter_localizations使用
- **フォント**: IPAexGothic（日本語表示）

## プロジェクト固有の規約

### ディレクトリ構造
- `models/`: ビジネスロジックのデータ構造
- `screens/`: UI画面コンポーネント
- `services/`: 外部サービス連携（GPS, PDF, Storage）
- `utils/`: プラットフォーム抽象化・共通処理

### 非同期処理
- **Future/async-await**: 標準的な非同期パターン
- **Completer**: 複雑な非同期制御に使用
- **StreamBuilder**: リアルタイム更新が必要な箇所

### エラーハンドリング
- **try-catch**: 例外処理の徹底
- **print文**: 現在はデバッグ用（本番環境向けロギング要検討）

## 品質指標

### 現在の状況
- **Lint警告**: 122件（主にprint文とBuildContext非同期使用）
- **優先改善**: print文の本番用ロギング化
- **テスト**: 基本テンプレートのみ（実装が必要）

### 推奨改善
1. ロギングシステム導入
2. 非同期UI状態管理改善
3. 単体テスト・統合テストの充実