import 'package:flutter/material.dart';
import '../services/backup_service.dart';
import '../utils/logger.dart';
import 'home_screen.dart';

/// 事前認証状態を持つHomeScreenラッパー
class PreAuthenticatedHomeScreen extends StatefulWidget {
  final InitialAuthState initialAuthState;
  
  const PreAuthenticatedHomeScreen({
    super.key,
    required this.initialAuthState,
  });

  @override
  State<PreAuthenticatedHomeScreen> createState() => _PreAuthenticatedHomeScreenState();
}

class _PreAuthenticatedHomeScreenState extends State<PreAuthenticatedHomeScreen> {
  late BackupService _backupService;
  bool _isAuthenticated = false;
  String? _userName;

  @override
  void initState() {
    super.initState();
    
    // 事前認証状態を設定
    _backupService = widget.initialAuthState.backupService;
    _isAuthenticated = widget.initialAuthState.isAuthenticated;
    _userName = widget.initialAuthState.userName;
    
    // 認証状態の変更を監視
    _setupAuthStateListener();
    
    // 初期状態をログ出力
    if (_isAuthenticated) {
      AppLogger.info('アプリ起動時点でログイン済み: $_userName', 'PreAuthenticatedHomeScreen');
    } else {
      AppLogger.info('アプリ起動時点で未ログイン', 'PreAuthenticatedHomeScreen');
    }
  }

  /// 認証状態変更の監視を設定
  void _setupAuthStateListener() {
    _backupService.events.listen((event) {
      if (!mounted) return;
      
      setState(() {
        switch (event.type) {
          case BackupEventType.cloudConnected:
            _isAuthenticated = true;
            _userName = event.data as String?;
            AppLogger.info('認証状態変更: ログイン成功 ($_userName)', 'PreAuthenticatedHomeScreen');
            break;
          case BackupEventType.cloudDisconnected:
            _isAuthenticated = false;
            _userName = null;
            AppLogger.info('認証状態変更: ログアウト', 'PreAuthenticatedHomeScreen');
            break;
          default:
            break;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // HomeScreenに認証状態とサービスを渡す
    return HomeScreenWrapper(
      backupService: _backupService,
      isInitiallyAuthenticated: _isAuthenticated,
      initialUserName: _userName,
    );
  }
}

/// HomeScreenのラッパークラス
class HomeScreenWrapper extends StatelessWidget {
  final BackupService backupService;
  final bool isInitiallyAuthenticated;
  final String? initialUserName;
  
  const HomeScreenWrapper({
    super.key,
    required this.backupService,
    required this.isInitiallyAuthenticated,
    required this.initialUserName,
  });

  @override
  Widget build(BuildContext context) {
    // 実際のHomeScreenを表示
    // BackupServiceは既に初期化済みなので、HomeScreen内で新たに初期化する必要なし
    return const HomeScreen();
  }
}

/// main.dartで使用する初期認証状態クラス
class InitialAuthState {
  final bool isAuthenticated;
  final String? userName;
  final BackupService backupService;
  
  const InitialAuthState({
    required this.isAuthenticated,
    required this.userName,
    required this.backupService,
  });
}