import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:transport_daily_report/screens/pre_authenticated_home_screen.dart';
import 'package:transport_daily_report/config/app_config.dart';
import 'package:transport_daily_report/services/app_services.dart';
import 'package:transport_daily_report/services/storage_service.dart';
import 'package:transport_daily_report/services/backup_service.dart';
import 'package:transport_daily_report/services/background_service.dart';
import 'package:transport_daily_report/services/data_migration_service.dart';
import 'package:transport_daily_report/utils/permissions.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background service (mobile platforms only)
  if (!kIsWeb) {
    await initializeService();
  }
  // Request all necessary permissions
  await PermissionService.requestAllPermissions();
  
  // .envファイルを読み込み
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    // .envファイルが見つからない場合は無視（dart-defineを使用する場合）
    print('dotenv読み込みエラー（無視されます）: $e');
  }
  
  
  // 設定状況を出力（デバッグモード時のみ）
  if (AppConfig.isDebugMode) {
    ConfigValidator.printConfigStatus();
  }
  
  // データマイグレーションを実行
  await _performDataMigration();
  
  // 事前認証復元を実行
  final initialAuthState = await _performPreAuthentication();
  
  runApp(MyApp(initialAuthState: initialAuthState));
}

/// データマイグレーションを実行
Future<void> _performDataMigration() async {
  try {
    print('[STARTUP] データマイグレーション開始');
    
    final migrationService = DataMigrationService();
    
    // マイグレーションが必要かチェック
    if (await migrationService.needsMigration()) {
      print('[STARTUP] データマイグレーション実行中...');
      await migrationService.runMigrations();
      
      // 古いデータのクリーンアップ
      await migrationService.cleanupLegacyMileageData();
      
      print('[STARTUP] ✅ データマイグレーション完了');
    } else {
      print('[STARTUP] データマイグレーション不要 - スキップ');
    }
  } catch (e) {
    print('[STARTUP] ❌ データマイグレーションエラー: $e');
    // エラーが発生してもアプリ起動は継続
  }
}

/// 事前認証復元を実行
Future<InitialAuthState> _performPreAuthentication() async {
  try {
    print('[STARTUP] 事前認証復元を開始');
    
    final storageService = StorageService();
    final backupService = BackupService(storageService);
    
    // AppServicesにBackupServiceを登録
    AppServices.instance.setBackupService(backupService);
    
    // タイムアウト付きでBackupService初期化
    await backupService.initialize().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        print('[STARTUP] 認証復元がタイムアウト - 未認証状態で開始');
        return;
      },
    );
    
    // 認証状態をチェック
    print('[STARTUP] 認証状態チェック中...');
    print('[STARTUP] isCloudConnected: ${backupService.isCloudConnected}');
    print('[STARTUP] currentUser: ${backupService.currentUser}');
    
    if (backupService.isCloudConnected) {
      final userName = backupService.currentUser;
      print('[STARTUP] ✅ Google Drive自動接続成功: $userName');
      return InitialAuthState(
        isAuthenticated: true,
        userName: userName,
        backupService: backupService,
      );
    } else {
      print('[STARTUP] ❌ Google Drive自動接続失敗 - 手動接続が必要');
      return InitialAuthState(
        isAuthenticated: false,
        userName: null,
        backupService: backupService,
      );
    }
  } catch (e) {
    print('[STARTUP] 事前認証エラー: $e - 通常起動');
    final storageService = StorageService();
    final backupService = BackupService(storageService);
    AppServices.instance.setBackupService(backupService);
    return InitialAuthState(
      isAuthenticated: false,
      userName: null,
      backupService: backupService,
    );
  }
}



class MyApp extends StatelessWidget {
  final InitialAuthState initialAuthState;
  
  const MyApp({super.key, required this.initialAuthState});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'らくレポ！',
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: ThemeMode.system, // システムテーマに従う
      home: PreAuthenticatedHomeScreen(initialAuthState: initialAuthState),
      // 日本語のロケールを設定
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja', 'JP'),
      ],
      locale: const Locale('ja', 'JP'),
    );
  }

  // ライトテーマの構築
  ThemeData _buildLightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      
      // カードテーマ
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(8),
      ),
      
      // リストタイルテーマ
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      
      // FloatingActionButtonテーマ
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      
      // ボタンテーマ
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      
      // テキストボタンテーマ
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      
      // 入力フィールドテーマ
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      
      // AppBarテーマ
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 4,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      
      // SnackBarテーマ
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        insetPadding: const EdgeInsets.all(16),
      ),
      
      // ダイアログテーマ
      dialogTheme: DialogTheme(
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        insetPadding: const EdgeInsets.all(16),
      ),
      
      // ボトムシートテーマ
      bottomSheetTheme: const BottomSheetThemeData(
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      
      // チップテーマ
      chipTheme: ChipThemeData(
        elevation: 2,
        pressElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  // ダークテーマの構築
  ThemeData _buildDarkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      
      // ダークテーマ用の設定を同様に構築
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(8),
      ),
      
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 4,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
    );
  }
}

