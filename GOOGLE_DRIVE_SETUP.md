# Google Drive API 設定手順

## 1. Google Cloud Console設定

### ステップ1: プロジェクト作成
1. https://console.cloud.google.com/ にアクセス
2. 新しいプロジェクトを作成または既存のプロジェクトを選択
3. プロジェクト名を設定（例：transport-daily-report）

### ステップ2: Google Drive API有効化
1. **APIs & Services > Dashboard** に移動
2. **+ ENABLE APIS AND SERVICES** をクリック
3. "Google Drive API" を検索
4. **Enable** をクリック

### ステップ3: 認証情報の作成
1. **APIs & Services > Credentials** に移動
2. **+ CREATE CREDENTIALS** をクリック
3. **OAuth client ID** を選択

### ステップ4: OAuth同意画面の設定
1. **OAuth consent screen** を設定
2. **External** を選択（個人使用の場合）
3. 必要な情報を入力：
   - App name: "Transport Daily Report"
   - User support email: あなたのメールアドレス
   - Developer contact information: あなたのメールアドレス

### ステップ5: スコープの追加
1. **Scopes** タブで **ADD OR REMOVE SCOPES** をクリック
2. 以下のスコープを選択：
   - `https://www.googleapis.com/auth/drive.file`
   - `https://www.googleapis.com/auth/drive`

### ステップ6: OAuth Client IDの作成（Android用）
1. **Credentials** > **CREATE CREDENTIALS** > **OAuth client ID**
2. Application type: **Android**
3. Name: "Transport Daily Report Android Client"
4. Package name: `com.example.transport_daily_report`
5. SHA-1 certificate fingerprint: （前のステップで取得したSHA-1キー）

## 2. Androidアプリの設定

### SHA-1キーの取得（重要：最初に実行）
Windows PowerShellで以下を実行：
```powershell
cd android
./gradlew signingReport
```

または：
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

出力例：
```
Variant: debug
Config: debug
Store: ~/.android/debug.keystore
Alias: androiddebugkey
MD5: XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX
SHA1: AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD  <- この値をコピー
SHA-256: ...
```

### Firebase設定
1. https://console.firebase.google.com/ にアクセス
2. プロジェクトを作成または選択（Google Cloud Consoleと同じプロジェクト名）
3. **Project settings** > **General** タブ
4. **Android app** を追加
5. Package name: `com.example.transport_daily_report`
6. App nickname: "Transport Daily Report"
7. SHA-1証明書フィンガープリント: （上で取得したSHA-1キー）

### google-services.jsonの配置
1. Firebaseから `google-services.json` をダウンロード
2. `android/app/` フォルダに配置

### 重要：プロジェクトIDの確認
Firebase設定完了後、`google-services.json` 内の `project_id` を確認し、Google Cloud Consoleのプロジェクトと一致することを確認してください。

## 3. アプリコードの設定

### pubspec.yamlの確認
必要な依存関係が追加されていることを確認：
```yaml
dependencies:
  googleapis: ^13.2.0
  google_sign_in: ^6.2.1
  firebase_core: ^3.6.0
```

### AndroidManifest.xmlの設定
`android/app/src/main/AndroidManifest.xml` に権限を追加：
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

## 4. 認証情報の管理

### Android OAuth Client IDの特徴
- **Client Secret不要**: AndroidアプリのOAuth Client IDにはClient Secretがありません
- **パッケージ名とSHA-1で認証**: アプリの身元をパッケージ名とSHA-1証明書で確認
- **コードに直接記述可能**: Client IDは公開情報なので、コードに直接書いても問題なし

### 設定方法
`lib/config/app_config.dart` で以下を設定：
```dart
// AndroidのOAuth Client ID（例）
static const String googleDriveClientId = "123456789-abcdefg.apps.googleusercontent.com";

// Android版では不要
static const String googleDriveClientSecret = "";
```

### セキュリティ注意事項
- SHA-1証明書は開発用と本番用（リリース用）で異なります
- Google Play Consoleでアプリ署名を使用する場合は、アプリ署名証明書のSHA-1も追加が必要
- パッケージ名は本番リリース時に変更する場合があります

## 5. テスト手順

### 開発環境でのテスト
1. アプリを起動
2. バックアップ設定画面に移動
3. "Google Driveに接続" をタップ
4. Googleアカウントでログイン
5. アクセス許可を確認

### 確認事項
- ✅ Google認証が成功すること
- ✅ Google Driveフォルダが作成されること
- ✅ ファイルのアップロード/ダウンロードが動作すること

## 6. トラブルシューティング

### よくあるエラー
1. **"Google hasn't verified this app"**
   - テスト段階では「Continue」で進む
   - 本番環境では認証審査が必要

2. **"Access blocked: This app's request is invalid"**
   - OAuth同意画面の設定を確認
   - リダイレクトURIが正しく設定されているか確認

3. **"The project does not have a web app"**
   - Google Cloud Consoleで正しいOAuth Client IDが作成されているか確認

### デバッグのヒント
- ブラウザの開発者ツールでネットワークタブを確認
- Flutter Inspectorでログを確認
- Google Cloud Consoleの監査ログを確認

## 7. 本番環境への移行

### 認証審査
本番環境でのリリース前に：
1. OAuth同意画面の認証審査を申請
2. プライバシーポリシーの設定
3. 利用規約の設定
4. アプリの詳細説明

### ドメイン設定
1. 本番ドメインをAuthorized redirect URIsに追加
2. Firebase Hostingまたは他のホスティングサービスの設定
3. HTTPSの有効化