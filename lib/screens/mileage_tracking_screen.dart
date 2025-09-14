import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/mileage_record.dart';
import '../services/mileage_service.dart';
import '../services/gps_tracking_service.dart';
import '../services/battery_optimization_service.dart';
import '../services/error_handling_service.dart';
import '../widgets/mileage_input_widget.dart';
import '../widgets/mileage_history_widget.dart';
import '../utils/logger.dart';

/// 走行距離追跡専用画面
/// 
/// 点呼記録とは完全に分離された走行距離測定・記録機能
/// - 開始・終了メーター値入力
/// - GPS自動追跡機能
/// - バッテリー最適化設定
/// - 履歴表示・異常値検知
class MileageTrackingScreen extends StatefulWidget {
  const MileageTrackingScreen({super.key});

  @override
  State<MileageTrackingScreen> createState() => _MileageTrackingScreenState();
}

class _MileageTrackingScreenState extends State<MileageTrackingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // サービス
  final MileageService _mileageService = MileageService();
  final GPSTrackingService _gpsService = GPSTrackingService();
  final BatteryOptimizationService _batteryService = BatteryOptimizationService();
  final ErrorHandlingService _errorService = ErrorHandlingService();
  
  // 状態管理
  MileageRecord? _currentRecord;
  bool _isLoading = false;
  String? _errorMessage;
  
  // 入力値
  double? _startMileage;
  double? _endMileage;
  bool _gpsTrackingEnabled = false;
  
  // GPS状態
  bool _isGpsTracking = false;
  double _currentGpsDistance = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initializeServices();
    _loadCurrentDayRecord();
    _setupListeners();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mileageService.dispose();
    _batteryService.dispose();
    _errorService.dispose();
    super.dispose();
  }

  /// サービス初期化
  Future<void> _initializeServices() async {
    try {
      await _batteryService.initialize();
    } catch (e) {
      AppLogger.error('サービス初期化エラー', 'MileageTrackingScreen', e);
    }
  }

  /// 現在日の記録を読み込み
  Future<void> _loadCurrentDayRecord() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final record = await _mileageService.getCurrentDayRecord();
      
      if (mounted) {
        setState(() {
          _currentRecord = record;
          _startMileage = record?.startMileage;
          _endMileage = record?.endMileage;
          _gpsTrackingEnabled = record?.source == MileageSource.gps;
          _isLoading = false;
        });
      }
      
      AppLogger.info('当日記録読み込み完了', 'MileageTrackingScreen');
    } catch (e) {
      AppLogger.error('当日記録読み込みエラー', 'MileageTrackingScreen', e);
      
      if (mounted) {
        setState(() {
          _errorMessage = 'データの読み込みに失敗しました';
          _isLoading = false;
        });
      }
    }
  }

  /// リスナー設定
  void _setupListeners() {
    // GPS追跡状態の監視
    _gpsService.isTrackingNotifier.addListener(() {
      if (mounted) {
        setState(() {
          _isGpsTracking = _gpsService.isTrackingNotifier.value;
        });
      }
    });
    
    // GPS距離の監視
    _gpsService.currentDistance.addListener(() {
      if (mounted) {
        setState(() {
          _currentGpsDistance = _gpsService.currentDistance.value;
        });
      }
    });

    // エラー通知の監視
    _errorService.errorStream.listen((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: _getErrorColor(error.severity),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });
  }

  /// エラー重要度による色取得
  Color _getErrorColor(AppErrorSeverity severity) {
    switch (severity) {
      case AppErrorSeverity.low:
        return Colors.blue;
      case AppErrorSeverity.medium:
        return Colors.orange;
      case AppErrorSeverity.high:
      case AppErrorSeverity.critical:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('走行距離追跡'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.speed), text: '記録'),
            Tab(icon: Icon(Icons.gps_fixed), text: 'GPS'),
            Tab(icon: Icon(Icons.settings), text: '設定'),
            Tab(icon: Icon(Icons.history), text: 'メーター値'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorWidget()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRecordingTab(),
                    _buildGpsTab(),
                    _buildSettingsTab(),
                    _buildMileageHistoryTab(),
                  ],
                ),
    );
  }

  /// エラー表示ウィジェット
  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadCurrentDayRecord,
            child: const Text('再試行'),
          ),
        ],
      ),
    );
  }

  /// 記録タブ
  Widget _buildRecordingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 当日情報カード
          _buildCurrentDayCard(),
          const SizedBox(height: 24),
          
          // 開始メーター値
          _buildStartMileageSection(),
          const SizedBox(height: 24),
          
          // GPS記録セクション
          if (_startMileage != null && _endMileage == null) ...[
            _buildGpsTrackingSection(),
            const SizedBox(height: 24),
          ],
          
          // 終了メーター値
          if (_startMileage != null) ...[
            _buildEndMileageSection(),
            const SizedBox(height: 24),
          ],
          
          // 計算結果
          if (_startMileage != null && (_endMileage != null || _isGpsTracking)) ...[
            _buildCalculationResultCard(),
            const SizedBox(height: 24),
          ],
          
          // アクションボタン
          _buildActionButtons(),
        ],
      ),
    );
  }

  /// 当日情報カード
  Widget _buildCurrentDayCard() {
    final today = DateTime.now();
    final formattedDate = DateFormat('yyyy年MM月dd日(E)', 'ja_JP').format(today);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 20),
                const SizedBox(width: 8),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatusItem(
                    '記録状況',
                    _getRecordStatus(),
                    _getRecordStatusColor(),
                  ),
                ),
                if (_currentRecord != null) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatusItem(
                      '記録方法',
                      _getMileageSourceLabel(_currentRecord!.source),
                      Colors.blue,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// ステータス項目
  Widget _buildStatusItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  /// 開始メーター値セクション
  Widget _buildStartMileageSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '開始メーター値',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            MileageInputWidget(
              label: '開始時のメーター値',
              hintText: '例: 12345.6',
              initialValue: _startMileage,
              isRequired: true,
              isReadOnly: _currentRecord?.startMileage != null,
              onChanged: (value) {
                setState(() {
                  _startMileage = value;
                });
              },
              suffixWidget: const Text('km'),
            ),
            if (_currentRecord?.startMileage == null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _startMileage != null ? _recordStartMileage : null,
                  child: const Text('開始メーター値を記録'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// GPS記録セクション
  Widget _buildGpsTrackingSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.gps_fixed),
                const SizedBox(width: 8),
                const Text(
                  'GPS自動追跡',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _gpsTrackingEnabled,
                  onChanged: (_startMileage != null && !_isGpsTracking) 
                      ? (value) {
                          setState(() {
                            _gpsTrackingEnabled = value;
                          });
                          if (value) {
                            _startGpsTracking();
                          }
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isGpsTracking) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'GPS追跡中',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '現在の走行距離: ${_currentGpsDistance.toStringAsFixed(1)} km',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _stopGpsTracking,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('GPS追跡を停止'),
                ),
              ),
            ] else ...[
              Text(
                'GPS自動追跡を有効にすると、移動中の走行距離を自動で計測します。\n'
                'バッテリー消費を抑えるため、省電力設定も利用できます。',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              if (_gpsTrackingEnabled && _startMileage != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _startGpsTracking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('GPS追跡を開始'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// 終了メーター値セクション
  Widget _buildEndMileageSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '終了メーター値',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (_isGpsTracking) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'GPS追跡中のため自動算出',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '推定終了メーター値: ${(_startMileage! + _currentGpsDistance).toStringAsFixed(1)} km',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'GPS追跡を停止すると、終了メーター値を手動で調整できます。',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ] else ...[
              MileageInputWidget(
                label: '終了時のメーター値',
                hintText: '例: 12389.2',
                initialValue: _endMileage,
                isRequired: true,
                onChanged: (value) {
                  setState(() {
                    _endMileage = value;
                  });
                },
                suffixWidget: const Text('km'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 計算結果カード
  Widget _buildCalculationResultCard() {
    double? calculatedDistance;
    
    if (_isGpsTracking) {
      calculatedDistance = _currentGpsDistance;
    } else if (_startMileage != null && _endMileage != null) {
      calculatedDistance = _endMileage! - _startMileage!;
    }
    
    if (calculatedDistance == null) return const SizedBox.shrink();
    
    final isAnomaly = calculatedDistance > 1000.0 || calculatedDistance < 0;
    
    return Card(
      color: isAnomaly ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isAnomaly ? Icons.warning : Icons.check_circle,
                  color: isAnomaly ? Colors.red : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  '計算結果',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isAnomaly ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildResultItem('開始', '${_startMileage?.toStringAsFixed(1) ?? '---'} km'),
                const Icon(Icons.arrow_forward),
                if (_isGpsTracking)
                  _buildResultItem('GPS距離', '${calculatedDistance.toStringAsFixed(1)} km')
                else
                  _buildResultItem('終了', '${_endMileage?.toStringAsFixed(1) ?? '---'} km'),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isAnomaly ? Colors.red : Colors.green).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '走行距離: ${calculatedDistance.toStringAsFixed(1)} km',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isAnomaly ? Colors.red : Colors.green,
                ),
              ),
            ),
            if (isAnomaly) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Text(
                  '⚠️ 異常値が検出されました\n'
                  '1日の走行距離が1000kmを超過しているか、'
                  'メーター値の逆転が発生している可能性があります。',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 結果項目
  Widget _buildResultItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// アクションボタン
  Widget _buildActionButtons() {
    return Column(
      children: [
        if (_startMileage != null && _endMileage != null && !_isGpsTracking) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _recordEndMileage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                '終了記録を保存',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/mileage-history');
                },
                child: const Text('履歴を見る'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _resetRecord,
                child: const Text('リセット'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// GPSタブ
  Widget _buildGpsTab() {
    return ValueListenableBuilder<BatteryStatus>(
      valueListenable: _batteryService.batteryStatusNotifier,
      builder: (context, batteryStatus, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // バッテリー状態カード
              _buildBatteryStatusCard(batteryStatus),
              const SizedBox(height: 16),
              
              // GPS追跡状況カード
              _buildGpsStatusCard(),
              const SizedBox(height: 16),
              
              // GPS品質情報
              _buildGpsQualityCard(),
            ],
          ),
        );
      },
    );
  }

  /// バッテリー状態カード
  Widget _buildBatteryStatusCard(BatteryStatus status) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'バッテリー状態',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatusItem(
                    'バッテリー残量',
                    '${status.level}%',
                    _getBatteryColor(status.level),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatusItem(
                    '省電力モード',
                    _getPowerModeLabel(status.powerMode),
                    Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  status.isCharging ? Icons.battery_charging_full : Icons.battery_std,
                  color: status.isCharging ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  status.isCharging ? '充電中' : '充電器未接続',
                  style: TextStyle(
                    color: status.isCharging ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// GPS状況カード
  Widget _buildGpsStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GPS追跡状況',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _isGpsTracking ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isGpsTracking ? 'GPS追跡中' : 'GPS停止中',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _isGpsTracking ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
            if (_isGpsTracking) ...[
              const SizedBox(height: 12),
              Text(
                '累積走行距離: ${_currentGpsDistance.toStringAsFixed(1)} km',
                style: const TextStyle(fontSize: 18),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// GPS品質カード
  Widget _buildGpsQualityCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GPS品質情報',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '現在のGPS品質情報は取得中です...',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            // TODO: GPS品質メトリクスの表示実装
          ],
        ),
      ),
    );
  }

  /// 設定タブ
  Widget _buildSettingsTab() {
    return ValueListenableBuilder<BatteryStatus>(
      valueListenable: _batteryService.batteryStatusNotifier,
      builder: (context, batteryStatus, child) {
        final config = _batteryService.getCurrentConfig();
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 省電力モード設定
              _buildPowerModeSettings(config),
              const SizedBox(height: 16),
              
              // バッテリー閾値設定
              _buildBatteryThresholdSettings(config),
              const SizedBox(height: 16),
              
              // 適応的間隔調整設定
              _buildAdaptiveIntervalSettings(config),
              const SizedBox(height: 16),
              
              // 推奨設定カード
              _buildRecommendationCard(),
            ],
          ),
        );
      },
    );
  }

  /// 省電力モード設定
  Widget _buildPowerModeSettings(BatteryOptimizationConfig config) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '省電力モード',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...PowerMode.values.map((mode) => RadioListTile<PowerMode>(
              title: Text(_getPowerModeLabel(mode)),
              subtitle: Text(_getPowerModeDescription(mode)),
              value: mode,
              groupValue: config.powerMode,
              onChanged: (value) {
                if (value != null) {
                  _batteryService.setPowerMode(value);
                }
              },
            )).toList(),
          ],
        ),
      ),
    );
  }

  /// バッテリー閾値設定
  Widget _buildBatteryThresholdSettings(BatteryOptimizationConfig config) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'バッテリー省電力切替閾値',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '現在の設定: ${config.batteryThreshold}%',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Slider(
              value: config.batteryThreshold.toDouble(),
              min: 5,
              max: 50,
              divisions: 9,
              label: '${config.batteryThreshold}%',
              onChanged: (value) {
                _batteryService.setBatteryThreshold(value.round());
              },
            ),
            const Text(
              'バッテリー残量がこの値以下になると自動で省電力モードに切り替わります',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  /// 適応的間隔調整設定
  Widget _buildAdaptiveIntervalSettings(BatteryOptimizationConfig config) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '適応的間隔調整',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '速度に応じてGPS記録間隔を自動調整してバッテリーを節約',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('有効にする'),
              subtitle: Text(
                config.adaptiveIntervalEnabled 
                    ? '低速時は記録間隔を長く、高速時は短くします'
                    : '固定間隔で記録します',
              ),
              value: config.adaptiveIntervalEnabled,
              onChanged: (value) {
                _batteryService.setAdaptiveIntervalEnabled(value);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 推奨設定カード
  Widget _buildRecommendationCard() {
    return Card(
      color: Colors.blue.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  '推奨設定',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _applyRecommendedSettings,
              child: const Text('推奨設定を適用'),
            ),
          ],
        ),
      ),
    );
  }

  // ============ イベントハンドラー ============

  /// 開始メーター値記録
  Future<void> _recordStartMileage() async {
    if (_startMileage == null) return;

    try {
      final record = await _mileageService.recordStartMileage(
        _startMileage!,
        _gpsTrackingEnabled,
      );

      setState(() {
        _currentRecord = record;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('開始メーター値を記録しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      await _errorService.handleGenericError(
        '開始メーター値の記録に失敗しました',
        originalError: e,
        severity: AppErrorSeverity.medium,
      );
    }
  }

  /// GPS追跡開始
  Future<void> _startGpsTracking() async {
    if (_startMileage == null) return;

    try {
      await _gpsService.startTracking(startMileage: _startMileage!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS追跡を開始しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      await _errorService.handleGpsError(
        GPSErrorType.unknown,
        context: 'GPS追跡開始',
        originalError: e,
      );
    }
  }

  /// GPS追跡停止
  Future<void> _stopGpsTracking() async {
    try {
      await _gpsService.stopTracking();
      
      setState(() {
        _endMileage = _startMileage! + _currentGpsDistance;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS追跡を停止しました'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      await _errorService.handleGpsError(
        GPSErrorType.unknown,
        context: 'GPS追跡停止',
        originalError: e,
      );
    }
  }

  /// 終了メーター値記録
  Future<void> _recordEndMileage() async {
    if (_startMileage == null || _endMileage == null) return;

    try {
      final source = _isGpsTracking 
          ? MileageSource.gps 
          : MileageSource.manual;

      final record = await _mileageService.recordEndMileage(
        _endMileage!,
        source,
        gpsDistance: _isGpsTracking ? _currentGpsDistance : null,
      );

      setState(() {
        _currentRecord = record;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('終了メーター値を記録しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      await _errorService.handleGenericError(
        '終了メーター値の記録に失敗しました',
        originalError: e,
        severity: AppErrorSeverity.medium,
      );
    }
  }

  /// 記録リセット
  Future<void> _resetRecord() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('記録をリセット'),
        content: const Text('本日の記録をリセットしますか？この操作は元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'リセット',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _currentRecord = null;
        _startMileage = null;
        _endMileage = null;
        _gpsTrackingEnabled = false;
      });

      if (_isGpsTracking) {
        await _gpsService.stopTracking();
      }
    }
  }

  /// 推奨設定適用
  Future<void> _applyRecommendedSettings() async {
    try {
      final recommendation = await _batteryService.getStartTrackingRecommendation();
      
      await _batteryService.setPowerMode(recommendation.recommendedPowerMode);
      await _batteryService.setBatteryThreshold(20);
      await _batteryService.setAdaptiveIntervalEnabled(true);
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('推奨設定適用完了'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('以下の設定を適用しました：'),
                const SizedBox(height: 8),
                ...recommendation.recommendations.map(
                  (rec) => Text('• $rec'),
                ).toList(),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      await _errorService.handleGenericError(
        '推奨設定の適用に失敗しました',
        originalError: e,
      );
    }
  }

  // ============ ヘルパーメソッド ============

  /// 記録状況取得
  String _getRecordStatus() {
    if (_currentRecord == null) return '未開始';
    if (_currentRecord!.isComplete) return '完了';
    if (_currentRecord!.startMileage != null) return '記録中';
    return '未開始';
  }

  /// 記録状況色取得
  Color _getRecordStatusColor() {
    if (_currentRecord == null) return Colors.grey;
    if (_currentRecord!.isComplete) return Colors.green;
    if (_currentRecord!.startMileage != null) return Colors.blue;
    return Colors.grey;
  }

  /// メーター値ソースラベル取得
  String _getMileageSourceLabel(MileageSource source) {
    switch (source) {
      case MileageSource.manual:
        return '手動入力';
      case MileageSource.gps:
        return 'GPS記録';
      case MileageSource.hybrid:
        return 'GPS+手動修正';
    }
  }

  /// バッテリー色取得
  Color _getBatteryColor(int level) {
    if (level <= 20) return Colors.red;
    if (level <= 50) return Colors.orange;
    return Colors.green;
  }

  /// 省電力モードラベル取得
  String _getPowerModeLabel(PowerMode mode) {
    switch (mode) {
      case PowerMode.highAccuracy:
        return '高精度';
      case PowerMode.balanced:
        return 'バランス';
      case PowerMode.powerSaver:
        return '省電力';
    }
  }

  /// 省電力モード説明取得
  String _getPowerModeDescription(PowerMode mode) {
    switch (mode) {
      case PowerMode.highAccuracy:
        return '5秒間隔・最高精度（バッテリー消費大）';
      case PowerMode.balanced:
        return '15秒間隔・標準精度（推奨）';
      case PowerMode.powerSaver:
        return '30秒間隔・省電力（バッテリー長持ち）';
    }
  }

  /// メーター値履歴タブ
  Widget _buildMileageHistoryTab() {
    return const MileageHistoryWidget();
  }
}