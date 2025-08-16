import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/app_services.dart';
import '../services/backup_service.dart';
import '../services/data_export_service.dart';
import '../services/storage_service.dart';
import '../services/cloud_storage_interface.dart';
import '../utils/logger.dart';

/// バックアップ設定画面
class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> with TickerProviderStateMixin {
  late BackupService _backupService;
  late DataExportService _exportService;
  late TabController _tabController;
  
  bool _isLoading = true;
  String? _errorMessage;
  List<BackupMetadata> _availableBackups = [];
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeServices();
  }
  
  Future<void> _initializeServices() async {
    try {
      // AppServicesから既に初期化済みのBackupServiceを取得
      if (AppServices.instance.isBackupServiceInitialized) {
        _backupService = AppServices.instance.backupService!;
        AppLogger.info('既存のBackupServiceを使用', 'BackupSettingsScreen');
      } else {
        // フォールバック：新しくBackupServiceを作成
        final storageService = StorageService();
        _backupService = BackupService(storageService);
        await _backupService.initialize();
        AppServices.instance.setBackupService(_backupService);
        AppLogger.info('新しいBackupServiceを初期化', 'BackupSettingsScreen');
      }
      
      final storageService = StorageService();
      _exportService = DataExportService(storageService);
      
      _backupService.events.listen(_handleBackupEvent);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        await _loadAvailableBackups();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'サービスの初期化に失敗しました: $e';
        });
      }
    }
  }
  
  void _handleBackupEvent(BackupEvent event) {
    if (!mounted) return;
    
    switch (event.type) {
      case BackupEventType.cloudConnected:
        _showSnackBar('クラウドに接続しました', isError: false);
        _loadAvailableBackups();
        break;
      case BackupEventType.cloudDisconnected:
        _showSnackBar('クラウドから切断しました', isError: false);
        setState(() {
          _availableBackups.clear();
        });
        break;
      case BackupEventType.backupCompleted:
        _showSnackBar('バックアップが完了しました', isError: false);
        _loadAvailableBackups();
        break;
      case BackupEventType.restoreCompleted:
        _showSnackBar('復元が完了しました', isError: false);
        break;
      case BackupEventType.error:
        _showSnackBar(event.message ?? 'エラーが発生しました', isError: true);
        break;
      default:
        break;
    }
    
    setState(() {});
  }
  
  Future<void> _loadAvailableBackups() async {
    AppLogger.debug('バックアップ一覧の読み込み開始', 'BackupSettingsScreen');
    
    if (!_backupService.isCloudConnected) {
      AppLogger.warning('クラウドに接続されていません', 'BackupSettingsScreen');
      return;
    }
    
    try {
      AppLogger.debug('getAvailableBackups()を呼び出し中', 'BackupSettingsScreen');
      final backups = await _backupService.getAvailableBackups();
      AppLogger.info('取得されたバックアップ数: ${backups.length}', 'BackupSettingsScreen');
      
      if (mounted) {
        setState(() {
          _availableBackups = backups;
        });
        AppLogger.debug('UIを更新しました', 'BackupSettingsScreen');
      }
    } catch (e) {
      AppLogger.error('バックアップ一覧の読み込みエラー', 'BackupSettingsScreen', e);
    }
  }
  
  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _backupService.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('バックアップ設定')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('バックアップ設定')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!, style: TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                    _isLoading = true;
                  });
                  _initializeServices();
                },
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('バックアップ設定'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.cloud), text: 'クラウド'),
            Tab(icon: Icon(Icons.backup), text: 'バックアップ'),
            Tab(icon: Icon(Icons.import_export), text: 'エクスポート'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCloudTab(),
          _buildBackupTab(),
          _buildExportTab(),
        ],
      ),
    );
  }
  
  Widget _buildCloudTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 接続状態
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('接続状態', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        _backupService.isCloudConnected ? Icons.cloud_done : Icons.cloud_off,
                        color: _backupService.isCloudConnected ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _backupService.isCloudConnected 
                          ? 'Google Driveに接続済み'
                          : '未接続',
                        style: TextStyle(
                          color: _backupService.isCloudConnected ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  if (_backupService.isCloudConnected && _backupService.currentUser != null) ...[
                    const SizedBox(height: 8),
                    Text('ユーザー: ${_backupService.currentUser}'),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (!_backupService.isCloudConnected)
                        ElevatedButton.icon(
                          onPressed: () => _connectToGoogleDrive(),
                          icon: const Icon(Icons.cloud),
                          label: const Text('Google Driveに接続'),
                        ),
                      if (_backupService.isCloudConnected) ...[
                        ElevatedButton.icon(
                          onPressed: () => _refreshAuthentication(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('認証更新'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _disconnectFromCloud(),
                          icon: const Icon(Icons.cloud_off),
                          label: const Text('切断'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 同期設定
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('自動バックアップ設定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('自動バックアップを有効にする'),
                    subtitle: const Text('定期的にデータを自動でバックアップします'),
                    value: _backupService.config.autoBackup,
                    onChanged: _backupService.isCloudConnected ? (value) => _toggleAutoBackup(value) : null,
                  ),
                  if (_backupService.config.autoBackup) ...[
                    const Divider(),
                    ListTile(
                      title: const Text('バックアップ間隔'),
                      subtitle: Text('${_backupService.config.backupInterval.inHours}時間'),
                      trailing: DropdownButton<int>(
                        value: _backupService.config.backupInterval.inHours,
                        items: [1, 6, 12, 24, 48, 72].map((hours) {
                          return DropdownMenuItem(
                            value: hours,
                            child: Text('${hours}時間'),
                          );
                        }).toList(),
                        onChanged: (hours) => _updateBackupInterval(hours!),
                      ),
                    ),
                    ListTile(
                      title: const Text('保存するバックアップ数'),
                      subtitle: Text('${_backupService.config.maxBackupFiles}個'),
                      trailing: DropdownButton<int>(
                        value: _backupService.config.maxBackupFiles,
                        items: [3, 5, 7, 10, 14, 30].map((count) {
                          return DropdownMenuItem(
                            value: count,
                            child: Text('${count}個'),
                          );
                        }).toList(),
                        onChanged: (count) => _updateMaxBackupFiles(count!),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('データを暗号化'),
                      subtitle: const Text('バックアップデータを暗号化して保存'),
                      value: _backupService.config.encryptData,
                      onChanged: (value) => _toggleEncryption(value),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildBackupTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 手動バックアップ
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('手動バックアップ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('現在のデータを手動でバックアップします。'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _backupService.isCloudConnected && !_backupService.isBackingUp
                          ? () => _performManualBackup()
                          : null,
                        icon: _backupService.isBackingUp 
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.backup),
                        label: Text(_backupService.isBackingUp ? 'バックアップ中...' : 'バックアップ実行'),
                      ),
                    ],
                  ),
                  if (_backupService.lastBackupTime != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '最後のバックアップ: ${DateFormat('yyyy/MM/dd HH:mm').format(_backupService.lastBackupTime!)}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // バックアップ一覧
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('バックアップ履歴', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (!_backupService.isCloudConnected)
                    const Text('クラウドに接続するとバックアップ履歴が表示されます。')
                  else if (_availableBackups.isEmpty)
                    const Text('バックアップがありません。')
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _availableBackups.length,
                      itemBuilder: (context, index) {
                        final backup = _availableBackups[index];
                        return ListTile(
                          leading: const Icon(Icons.backup),
                          title: Text(backup.fileName),
                          subtitle: Text(DateFormat('yyyy/MM/dd HH:mm').format(backup.createdAt)),
                          trailing: PopupMenuButton(
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'restore',
                                child: const Row(
                                  children: [
                                    Icon(Icons.restore),
                                    SizedBox(width: 8),
                                    Text('復元'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: const Row(
                                  children: [
                                    Icon(Icons.delete, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('削除'),
                                  ],
                                ),
                              ),
                            ],
                            onSelected: (value) {
                              if (value == 'restore') {
                                _restoreFromBackup(backup.fileName);
                              } else if (value == 'delete') {
                                _deleteBackup(backup.fileName);
                              }
                            },
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildExportTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('データエクスポート', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('データをファイルとしてエクスポートして共有できます。'),
          const SizedBox(height: 16),
          
          ...DataExportService.supportedFormats.map((format) {
            return Card(
              child: ListTile(
                leading: Icon(_getFormatIcon(format.extension)),
                title: Text(format.name),
                subtitle: Text(format.description),
                trailing: ElevatedButton(
                  onPressed: () => _exportData(format),
                  child: const Text('エクスポート'),
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
  
  IconData _getFormatIcon(String extension) {
    switch (extension) {
      case 'json':
        return Icons.code;
      case 'csv':
        return Icons.table_chart;
      default:
        return Icons.file_present;
    }
  }
  
  Future<void> _connectToGoogleDrive() async {
    final success = await _backupService.connectToCloud(CloudStorageType.googleDrive);
    if (!success && _backupService.lastError != null) {
      _showSnackBar(_backupService.lastError!, isError: true);
    }
  }
  
  Future<void> _disconnectFromCloud() async {
    await _backupService.disconnectFromCloud();
  }
  
  Future<void> _refreshAuthentication() async {
    try {
      _showSnackBar('認証を更新中...', isError: false);
      
      if (_backupService.isCloudConnected) {
        // 直接認証リフレッシュを試行（切断せずに）
        final success = await _backupService.connectToCloud(CloudStorageType.googleDrive);
        
        if (success) {
          _showSnackBar('認証の更新が完了しました', isError: false);
          setState(() {}); // UI更新
        } else {
          _showSnackBar('認証の更新に失敗しました。完全に再接続を試します。', isError: false);
          
          // 失敗時のみ完全な再接続
          await _backupService.disconnectFromCloud();
          final retrySuccess = await _backupService.connectToCloud(CloudStorageType.googleDrive);
          
          if (retrySuccess) {
            _showSnackBar('再接続が完了しました', isError: false);
            setState(() {});
          } else {
            _showSnackBar('再接続に失敗しました', isError: true);
          }
        }
      }
    } catch (e) {
      _showSnackBar('認証更新エラー: $e', isError: true);
    }
  }
  
  Future<void> _toggleAutoBackup(bool enabled) async {
    final newConfig = BackupConfig(
      autoBackup: enabled,
      backupInterval: _backupService.config.backupInterval,
      maxBackupFiles: _backupService.config.maxBackupFiles,
      encryptData: _backupService.config.encryptData,
    );
    await _backupService.updateConfig(newConfig);
  }
  
  Future<void> _updateBackupInterval(int hours) async {
    final newConfig = BackupConfig(
      autoBackup: _backupService.config.autoBackup,
      backupInterval: Duration(hours: hours),
      maxBackupFiles: _backupService.config.maxBackupFiles,
      encryptData: _backupService.config.encryptData,
    );
    await _backupService.updateConfig(newConfig);
  }
  
  Future<void> _updateMaxBackupFiles(int count) async {
    final newConfig = BackupConfig(
      autoBackup: _backupService.config.autoBackup,
      backupInterval: _backupService.config.backupInterval,
      maxBackupFiles: count,
      encryptData: _backupService.config.encryptData,
    );
    await _backupService.updateConfig(newConfig);
  }
  
  Future<void> _toggleEncryption(bool enabled) async {
    final newConfig = BackupConfig(
      autoBackup: _backupService.config.autoBackup,
      backupInterval: _backupService.config.backupInterval,
      maxBackupFiles: _backupService.config.maxBackupFiles,
      encryptData: enabled,
    );
    await _backupService.updateConfig(newConfig);
  }
  
  Future<void> _performManualBackup() async {
    final success = await _backupService.performBackup();
    if (!success && _backupService.lastError != null) {
      _showSnackBar(_backupService.lastError!, isError: true);
    }
  }
  
  Future<void> _restoreFromBackup(String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('データ復元'),
        content: Text('バックアップ「$fileName」からデータを復元しますか？\n\n現在のデータは上書きされます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('復元'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final success = await _backupService.restoreFromBackup(fileName);
      if (!success && _backupService.lastError != null) {
        _showSnackBar(_backupService.lastError!, isError: true);
      }
    }
  }
  
  Future<void> _deleteBackup(String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('バックアップ削除'),
        content: Text('バックアップ「$fileName」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    
    // TODO: バックアップ削除機能をBackupServiceに追加
    if (confirmed == true) {
      _showSnackBar('バックアップ削除機能は実装中です', isError: false);
    }
  }
  
  Future<void> _exportData(ExportFormat format) async {
    try {
      _showSnackBar('エクスポートを開始しています...', isError: false);
      
      late final dynamic file;
      
      switch (format.id) {
        case 'json_all':
          file = await _exportService.exportAllDataAsJson();
          break;
        case 'csv_visits':
          file = await _exportService.exportVisitRecordsAsCsv();
          break;
        case 'csv_rollcall':
          file = await _exportService.exportRollCallRecordsAsCsv();
          break;
        case 'csv_clients':
          file = await _exportService.exportClientsAsCsv();
          break;
        default:
          throw Exception('サポートされていない形式です');
      }
      
      if (file != null) {
        _showSnackBar('エクスポートが完了しました', isError: false);
        
        // ファイル共有
        final shouldShare = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('エクスポート完了'),
            content: const Text('ファイルを共有しますか？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('閉じる'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('共有'),
              ),
            ],
          ),
        );
        
        if (shouldShare == true) {
          await _exportService.shareExportedFile(file);
        }
      } else {
        _showSnackBar('エクスポートに失敗しました', isError: true);
      }
    } catch (e) {
      _showSnackBar('エクスポートエラー: $e', isError: true);
    }
  }
}