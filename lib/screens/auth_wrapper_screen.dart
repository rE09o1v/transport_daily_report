import 'dart:async';
import 'package:flutter/material.dart';
import '../services/backup_service.dart';
import '../services/storage_service.dart';

import '../utils/logger.dart';
import 'home_screen.dart';

/// 認証状態管理ラッパー画面
/// アプリ起動時の認証復元とログイン維持を処理する
class AuthWrapperScreen extends StatefulWidget {
  const AuthWrapperScreen({super.key});

  @override
  State<AuthWrapperScreen> createState() => _AuthWrapperScreenState();
}

class _AuthWrapperScreenState extends State<AuthWrapperScreen> {
  late BackupService _backupService;
  bool _isInitializing = true;
  bool _isAuthenticated = false;
  String? _userName;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _initializeAuthentication();
  }

  /// 認証の初期化処理
  Future<void> _initializeAuthentication() async {
    try {
      AppLogger.info('認証初期化を開始', 'AuthWrapperScreen');
      
      final storageService = StorageService();
      _backupService = BackupService(storageService);
      
      // BackupServiceの初期化（認証復元を含む）- タイムアウト付き
      await _backupService.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          AppLogger.warning('認証初期化がタイムアウトしました', 'AuthWrapperScreen');
          throw TimeoutException('認証初期化がタイムアウトしました', const Duration(seconds: 10));
        },
      );
      
      // 認証状態のリスナーを設定
      _backupService.events.listen((event) {
        if (!mounted) return;
        
        setState(() {
          switch (event.type) {
            case BackupEventType.cloudConnected:
              _isAuthenticated = true;
              _userName = event.data as String?;
              _errorMessage = null;
              AppLogger.info('認証成功: $_userName', 'AuthWrapperScreen');
              break;
            case BackupEventType.cloudDisconnected:
              _isAuthenticated = false;
              _userName = null;
              break;
            case BackupEventType.error:
              _errorMessage = event.message;
              AppLogger.warning('認証エラー: $_errorMessage', 'AuthWrapperScreen');
              break;
            default:
              break;
          }
        });
      });
      
      // 初期状態をチェック
      if (mounted) {
        setState(() {
          _isAuthenticated = _backupService.isCloudConnected;
          _userName = _backupService.currentUser;
          _isInitializing = false;
        });
      }
      
      AppLogger.info('認証初期化完了 - 認証済み: $_isAuthenticated', 'AuthWrapperScreen');
      
    } catch (e) {
      AppLogger.error('認証初期化エラー', 'AuthWrapperScreen', e);
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = '初期化に失敗しました: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 初期化中はスプラッシュ画面を表示
    if (_isInitializing) {
      return _buildSplashScreen();
    }

    // メインアプリケーション画面を表示
    return const HomeScreen();
  }

  /// スプラッシュ画面の構築
  Widget _buildSplashScreen() {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // アプリアイコン
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(
                Icons.directions_bus,
                size: 60,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            
            const SizedBox(height: 40),
            
            // アプリ名
            Text(
              '軽量日報アプリ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                fontFamily: 'IPAexGothic',
              ),
            ),
            
            const SizedBox(height: 60),
            
            // 状態インジケーター
            _buildStatusIndicator(),
          ],
        ),
      ),
    );
  }

  /// 状態インジケーターの構築
  Widget _buildStatusIndicator() {
    if (_errorMessage != null) {
      return Column(
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.white70,
            size: 32,
          ),
          const SizedBox(height: 16),
          Text(
            'エラーが発生しました',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontFamily: 'IPAexGothic',
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: Colors.white60,
                fontSize: 12,
                fontFamily: 'IPAexGothic',
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    if (_isAuthenticated && _userName != null) {
      return Column(
        children: [
          Icon(
            Icons.check_circle_outline,
            color: Colors.white70,
            size: 32,
          ),
          const SizedBox(height: 16),
          Text(
            'ログイン済み',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontFamily: 'IPAexGothic',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _userName!,
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontFamily: 'IPAexGothic',
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            color: Colors.white70,
            strokeWidth: 3,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '初期化中...',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 16,
            fontFamily: 'IPAexGothic',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'ログイン状態を確認しています',
          style: TextStyle(
            color: Colors.white60,
            fontSize: 12,
            fontFamily: 'IPAexGothic',
          ),
        ),
      ],
    );
  }
}