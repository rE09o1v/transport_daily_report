import 'dart:async';
import 'package:flutter/material.dart';
import 'package:transport_daily_report/models/roll_call_record.dart';
import 'package:transport_daily_report/models/mileage_record.dart';
import 'package:transport_daily_report/services/storage_service.dart';
import 'package:transport_daily_report/services/mileage_service.dart';
import 'package:transport_daily_report/widgets/mileage_input_widget.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class RollCallScreen extends StatefulWidget {
  const RollCallScreen({super.key});

  @override
  _RollCallScreenState createState() => _RollCallScreenState();
}

class _RollCallScreenState extends State<RollCallScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storageService = StorageService();
  final _mileageService = MileageService();
  
  // フォームフィールド用のコントローラー
  final _inspectorNameController = TextEditingController();
  final _otherMethodDetailController = TextEditingController();
  final _remarksController = TextEditingController();
  final _alcoholValueController = TextEditingController();
  
  // フォームの状態
  String _method = '対面'; // デフォルトは対面
  bool _isAlcoholTestUsed = true;
  bool _hasDrunkAlcohol = false;
  
  // メーター値関連の状態
  double? _startMileage;
  double? _endMileage;
  double? _calculatedDistance;
  bool _gpsTrackingEnabled = false;
  String? _gpsTrackingId;
  MileageRecord? _currentMileageRecord;
  bool _showGpsDialog = false;
  String? _mileageErrorText;
  
  // GPS状態監視用
  Timer? _gpsUpdateTimer;
  bool _isGpsTracking = false;
  double _currentGpsDistance = 0.0;
  GPSQualityMetrics? _gpsQuality;
  
  // 点呼記録の状態管理
  bool _hasStartRecord = false;
  bool _hasEndRecord = false;
  bool _isProcessing = false;
  
  // 通知サービス
  FlutterLocalNotificationsPlugin? _notificationsPlugin;
  
  @override
  void initState() {
    super.initState();
    _loadExistingRecord();
    _startGpsMonitoring();
    _initializeNotifications();
  }
  
  @override
  void dispose() {
    // コントローラーを破棄
    _inspectorNameController.dispose();
    _otherMethodDetailController.dispose();
    _remarksController.dispose();
    _alcoholValueController.dispose();
    
    // Timer を破棄
    _gpsUpdateTimer?.cancel();
    _mileageService.dispose();
    
    super.dispose();
  }
  
  /// 通知機能を初期化
  Future<void> _initializeNotifications() async {
    try {
      _notificationsPlugin = FlutterLocalNotificationsPlugin();
      
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);
      
      await _notificationsPlugin?.initialize(initializationSettings);
    } catch (e) {
      print('通知初期化エラー: $e');
    }
  }
  
  /// GPS稼働中通知を表示
  Future<void> _showGpsTrackingNotification() async {
    if (_notificationsPlugin == null) return;
    
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'gps_tracking',
        'GPS追跡',
        channelDescription: 'GPS追跡の状態を表示します',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        icon: '@mipmap/ic_launcher',
      );
      
      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);
      
      await _notificationsPlugin!.show(
        1,
        'GPS追跡中',
        'GPS追跡が稼働中です。走行距離: ${_currentGpsDistance.toStringAsFixed(1)}km',
        platformChannelSpecifics,
      );
    } catch (e) {
      print('GPS通知エラー: $e');
    }
  }
  
  /// GPS追跡通知を削除
  Future<void> _cancelGpsTrackingNotification() async {
    if (_notificationsPlugin == null) return;
    
    try {
      await _notificationsPlugin!.cancel(1);
    } catch (e) {
      print('GPS通知削除エラー: $e');
    }
  }
  
  /// GPS状態監視を開始
  void _startGpsMonitoring() {
    _gpsUpdateTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        _updateGpsStatus();
      }
    });
  }
  
  /// GPS状態を更新
  void _updateGpsStatus() {
    final wasTracking = _isGpsTracking;
    final wasDistance = _currentGpsDistance;
    
    _isGpsTracking = _mileageService.isGPSTracking();
    _currentGpsDistance = _mileageService.getCurrentGPSDistance();
    _gpsQuality = _mileageService.getCurrentGPSQuality();
    
    // GPS追跡状態が変更された場合の通知処理
    if (wasTracking != _isGpsTracking) {
      if (_isGpsTracking) {
        _showGpsTrackingNotification();
      } else {
        _cancelGpsTrackingNotification();
      }
    }
    
    // GPS距離が更新された場合の通知更新
    if (_isGpsTracking && (wasDistance - _currentGpsDistance).abs() > 0.1) {
      _showGpsTrackingNotification();
    }
    
    // 状態が変更された場合のみUIを更新
    if (wasTracking != _isGpsTracking || 
        (wasDistance - _currentGpsDistance).abs() > 0.1) {
      setState(() {
        // 状態が更新される
      });
    }
  }
  
  // 既存の記録を読み込む
  Future<void> _loadExistingRecord() async {
    try {
      final now = DateTime.now();
      
      // 開始・終了記録の存在確認
      final startRecord = await _storageService.getRollCallRecordByDateAndType(now, 'start');
      final endRecord = await _storageService.getRollCallRecordByDateAndType(now, 'end');
      
      // メーター値記録を読み込み
      final mileageRecord = await _mileageService.getCurrentDayRecord(now);
      
      if (!mounted) return;
      setState(() {
        _hasStartRecord = startRecord != null;
        _hasEndRecord = endRecord != null;
        _currentMileageRecord = mileageRecord;
        
        // 既存の記録がある場合、最新の記録を読み込み
        final latestRecord = endRecord ?? startRecord;
        if (latestRecord != null) {
          _method = latestRecord.method;
          _inspectorNameController.text = latestRecord.inspectorName;
          _otherMethodDetailController.text = latestRecord.otherMethodDetail ?? '';
          _isAlcoholTestUsed = latestRecord.isAlcoholTestUsed;
          _hasDrunkAlcohol = latestRecord.hasDrunkAlcohol;
          _alcoholValueController.text = latestRecord.alcoholValue?.toString() ?? '';
          _remarksController.text = latestRecord.remarks ?? '';
          
          // メーター値関連データを設定
          _startMileage = latestRecord.startMileage;
          _endMileage = latestRecord.endMileage;
          _calculatedDistance = latestRecord.calculatedDistance;
          _gpsTrackingEnabled = latestRecord.gpsTrackingEnabled;
          _gpsTrackingId = latestRecord.gpsTrackingId;
        }
        
        if (mileageRecord != null) {
          if (_startMileage == null) {
            _startMileage = mileageRecord.startMileage;
          }
          if (_endMileage == null) {
            _endMileage = mileageRecord.endMileage;
          }
          if (_calculatedDistance == null) {
            _calculatedDistance = mileageRecord.calculatedDistance;
          }
        }
      });
    } catch (e) {
      print('Error loading existing record: $e');
    }
  }
  
  // メーター値変更時の処理
  void _onMileageChanged(double? value) {
    setState(() {
      if (_hasStartRecord && !_hasEndRecord) {
        // 終了記録時
        _endMileage = value;
        _updateCalculatedDistance();
      } else {
        // 開始記録時
        _startMileage = value;
      }
    });
  }

  // 走行距離を更新
  void _updateCalculatedDistance() {
    if (_startMileage != null && _endMileage != null && !_gpsTrackingEnabled) {
      setState(() {
        _calculatedDistance = _endMileage! - _startMileage!;
      });
    }
  }

  // GPS記録開始確認ダイアログを表示
  Future<void> _showGpsConfirmDialog() async {
    if (!mounted) return;
    
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GPS追跡開始'),
        content: const Text('GPS追跡を開始しますか？走行距離の自動記録が有効になります。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _gpsTrackingEnabled = false;
                _gpsTrackingId = null;
              });
            },
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _gpsTrackingEnabled = true;
                _gpsTrackingId = 'gps_${DateTime.now().millisecondsSinceEpoch}';
              });
              _startGpsTracking();
            },
            child: const Text('開始'),
          ),
        ],
      ),
    );
  }

  // GPS追跡を開始
  Future<void> _startGpsTracking() async {
    try {
      if (_startMileage != null) {
        await _mileageService.recordStartMileage(
          _startMileage!,
          _gpsTrackingEnabled,
        );
      }
      print('GPS追跡開始: $_gpsTrackingId');
    } catch (e) {
      setState(() {
        _mileageErrorText = 'GPS記録の開始に失敗しました: $e';
        _gpsTrackingEnabled = false;
        _gpsTrackingId = null;
      });
    }
  }

  // 開始点呼記録を保存
  Future<void> _saveStartRecord() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isProcessing = true);
      
      try {
        // アルコール検出値の変換
        double? alcoholValue;
        if (_alcoholValueController.text.isNotEmpty) {
          alcoholValue = double.tryParse(_alcoholValueController.text);
        }
        
        // メーター値記録を先に保存
        if (_startMileage != null) {
          await _mileageService.recordStartMileage(
            _startMileage!,
            _gpsTrackingEnabled,
          );
        }
        
        // 始業点呼記録オブジェクトを作成
        final record = RollCallRecord(
          id: RollCallRecord.generateId(),
          datetime: DateTime.now(),
          type: 'start',
          method: _method,
          otherMethodDetail: _method == 'その他' ? _otherMethodDetailController.text : null,
          inspectorName: _inspectorNameController.text,
          isAlcoholTestUsed: _isAlcoholTestUsed,
          hasDrunkAlcohol: _hasDrunkAlcohol,
          alcoholValue: alcoholValue,
          remarks: _remarksController.text.isEmpty ? null : _remarksController.text,
          startMileage: _startMileage,
          gpsTrackingEnabled: _gpsTrackingEnabled,
          gpsTrackingId: _gpsTrackingId,
          mileageValidationFlags: [],
        );
        
        await _storageService.addRollCallRecord(record);
        
        if (!mounted) return;
        
        setState(() {
          _hasStartRecord = true;
          _isProcessing = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('始業点呼記録を保存しました'),
            backgroundColor: Colors.green,
          ),
        );
        
      } catch (e) {
        print('Error saving start record: $e');
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('始業点呼の保存に失敗しました: $e')),
        );
      }
    }
  }

  // 終了点呼記録を保存
  Future<void> _saveEndRecord() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isProcessing = true);
      
      try {
        // アルコール検出値の変換
        double? alcoholValue;
        if (_alcoholValueController.text.isNotEmpty) {
          alcoholValue = double.tryParse(_alcoholValueController.text);
        }
        
        // メーター値記録を保存
        if (_endMileage != null) {
          await _mileageService.recordEndMileage(
            _endMileage!,
            _gpsTrackingEnabled ? MileageSource.gps : MileageSource.manual,
            gpsDistance: _gpsTrackingEnabled ? _currentGpsDistance : null,
          );
        }
        
        // 終業点呼記録オブジェクトを作成
        final record = RollCallRecord(
          id: RollCallRecord.generateId(),
          datetime: DateTime.now(),
          type: 'end',
          method: _method,
          otherMethodDetail: _method == 'その他' ? _otherMethodDetailController.text : null,
          inspectorName: _inspectorNameController.text,
          isAlcoholTestUsed: _isAlcoholTestUsed,
          hasDrunkAlcohol: _hasDrunkAlcohol,
          alcoholValue: alcoholValue,
          remarks: _remarksController.text.isEmpty ? null : _remarksController.text,
          startMileage: _startMileage,
          endMileage: _endMileage,
          calculatedDistance: _calculatedDistance,
          gpsTrackingEnabled: _gpsTrackingEnabled,
          gpsTrackingId: _gpsTrackingId,
          mileageValidationFlags: [],
        );
        
        await _storageService.addRollCallRecord(record);
        
        if (!mounted) return;
        
        setState(() {
          _hasEndRecord = true;
          _isProcessing = false;
        });
        
        // GPS追跡通知を削除
        _cancelGpsTrackingNotification();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('終業点呼記録を保存しました'),
            backgroundColor: Colors.green,
          ),
        );
        
      } catch (e) {
        print('Error saving end record: $e');
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('終業点呼の保存に失敗しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('点呼記録'),
        actions: [
          // GPS稼働状況インジケーター
          if (_isGpsTracking)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.gps_fixed,
                    color: Colors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'GPS',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // GPS稼働状況表示
              if (_isGpsTracking) ...[
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(Icons.gps_fixed, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'GPS追跡中',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                              Text(
                                '走行距離: ${_currentGpsDistance.toStringAsFixed(1)}km',
                                style: TextStyle(color: Colors.green.shade600),
                              ),
                              if (_gpsQuality != null)
                                Text(
                                  '精度: ${_gpsQuality!.accuracyPercentage.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    color: Colors.green.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // 点呼ボタン
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _hasStartRecord || _isProcessing
                          ? null
                          : _saveStartRecord,
                      icon: Icon(
                        _hasStartRecord ? Icons.check : Icons.play_arrow,
                        color: _hasStartRecord ? Colors.green : null,
                      ),
                      label: Text(
                        _hasStartRecord ? '始業点呼完了' : '始業点呼開始',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _hasStartRecord 
                            ? Colors.green.shade100
                            : Theme.of(context).primaryColor,
                        foregroundColor: _hasStartRecord 
                            ? Colors.green.shade700
                            : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: !_hasStartRecord || _hasEndRecord || _isProcessing
                          ? null
                          : _saveEndRecord,
                      icon: Icon(
                        _hasEndRecord ? Icons.check : Icons.stop,
                        color: _hasEndRecord ? Colors.green : null,
                      ),
                      label: Text(
                        _hasEndRecord ? '終業点呼完了' : '終業点呼開始',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _hasEndRecord 
                            ? Colors.green.shade100
                            : Colors.red.shade600,
                        foregroundColor: _hasEndRecord 
                            ? Colors.green.shade700
                            : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
              
              if (_isProcessing) ...[
                const SizedBox(height: 16),
                const Center(
                  child: CircularProgressIndicator(),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // メーター値入力セクション
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.speed, color: Colors.blue),
                          const SizedBox(width: 8),
                          const Text(
                            'メーター値記録',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      if (!_hasStartRecord) ...[
                        // 始業前：開始メーター値入力
                        MileageInputWidget(
                          label: '開始時メーター値',
                          hintText: '例: 45,230',
                          initialValue: _startMileage,
                          isRequired: true,
                          onChanged: _onMileageChanged,
                          errorText: _mileageErrorText,
                        ),
                        
                        const SizedBox(height: 16),
                        
                        Row(
                          children: [
                            Checkbox(
                              value: _gpsTrackingEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _gpsTrackingEnabled = value ?? false;
                                });
                                if (_gpsTrackingEnabled) {
                                  _showGpsConfirmDialog();
                                }
                              },
                            ),
                            const Text('GPS距離測定を有効にする'),
                          ],
                        ),
                      ] else if (!_hasEndRecord) ...[
                        // 始業後：開始値表示と終了値入力
                        MileageInputWidget(
                          label: '開始時メーター値',
                          initialValue: _startMileage,
                          isReadOnly: true,
                        ),
                        
                        const SizedBox(height: 16),
                        
                        if (_gpsTrackingEnabled && _currentGpsDistance > 0) ...[
                          // GPS記録モード：GPS距離表示
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              border: Border.all(color: Colors.green.shade200),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.gps_fixed, color: Colors.green),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'GPS測定走行距離',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        '${_currentGpsDistance.toStringAsFixed(1)} km',
                                        style: TextStyle(
                                          fontSize: 18,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          MileageInputWidget(
                            label: '終了時メーター値（自動算出）',
                            initialValue: _startMileage != null 
                              ? _startMileage! + _currentGpsDistance
                              : _endMileage,
                            isReadOnly: true,
                          ),
                        ] else ...[
                          // 手動入力モード：終了メーター値入力
                          MileageInputWidget(
                            label: '終了時メーター値',
                            hintText: '例: 45,476',
                            initialValue: _endMileage,
                            isRequired: true,
                            onChanged: _onMileageChanged,
                            errorText: _mileageErrorText,
                          ),
                          
                          const SizedBox(height: 12),
                          
                          // 走行距離表示
                          if (_calculatedDistance != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                border: Border.all(color: Colors.blue.shade200),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.straighten, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Text(
                                    '走行距離: ${_calculatedDistance!.toStringAsFixed(1)} km',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ] else ...[
                        // 終業後：記録完了表示
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            border: Border.all(color: Colors.green.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.check_circle, 
                                   color: Colors.green, 
                                   size: 48),
                              const SizedBox(height: 8),
                              const Text(
                                '本日の点呼記録が完了しました',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_startMileage != null && _endMileage != null)
                                Text(
                                  '走行距離: ${(_endMileage! - _startMileage!).toStringAsFixed(1)} km',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      
                      // エラーメッセージ表示
                      if (_mileageErrorText != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            border: Border.all(color: Colors.red.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _mileageErrorText!,
                                  style: TextStyle(color: Colors.red.shade600, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 点呼方法
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '点呼方法',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Radio<String>(
                            value: '対面',
                            groupValue: _method,
                            onChanged: (value) {
                              setState(() {
                                _method = value!;
                              });
                            },
                          ),
                          const Text('対面'),
                          const SizedBox(width: 16),
                          Radio<String>(
                            value: 'その他',
                            groupValue: _method,
                            onChanged: (value) {
                              setState(() {
                                _method = value!;
                              });
                            },
                          ),
                          const Text('その他'),
                        ],
                      ),
                      if (_method == 'その他') ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _otherMethodDetailController,
                          decoration: const InputDecoration(
                            labelText: '点呼方法の詳細',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (_method == 'その他' && (value == null || value.isEmpty)) {
                              return '点呼方法の詳細を入力してください';
                            }
                            return null;
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 点呼執行者
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '点呼執行者',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _inspectorNameController,
                        decoration: const InputDecoration(
                          labelText: '点呼執行者名',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '点呼執行者名を入力してください';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // アルコールチェック
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'アルコールチェック',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text('アルコール検知器の使用:'),
                          const SizedBox(width: 16),
                          Radio<bool>(
                            value: true,
                            groupValue: _isAlcoholTestUsed,
                            onChanged: (value) {
                              setState(() {
                                _isAlcoholTestUsed = value!;
                              });
                            },
                          ),
                          const Text('有'),
                          const SizedBox(width: 16),
                          Radio<bool>(
                            value: false,
                            groupValue: _isAlcoholTestUsed,
                            onChanged: (value) {
                              setState(() {
                                _isAlcoholTestUsed = value!;
                              });
                            },
                          ),
                          const Text('無'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text('酒気帯びの有無:'),
                          const SizedBox(width: 16),
                          Radio<bool>(
                            value: false,
                            groupValue: _hasDrunkAlcohol,
                            onChanged: (value) {
                              setState(() {
                                _hasDrunkAlcohol = value!;
                              });
                            },
                          ),
                          const Text('無'),
                          const SizedBox(width: 16),
                          Radio<bool>(
                            value: true,
                            groupValue: _hasDrunkAlcohol,
                            onChanged: (value) {
                              setState(() {
                                _hasDrunkAlcohol = value!;
                              });
                            },
                          ),
                          const Text('有'),
                        ],
                      ),
                      if (_isAlcoholTestUsed) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Text('アルコール検出値:'),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _alcoholValueController,
                                keyboardType: TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'mg/L',
                                  hintText: '0.00',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                ),
                                validator: (value) {
                                  if (value != null && value.isNotEmpty) {
                                    final alcoholValue = double.tryParse(value);
                                    if (alcoholValue == null) {
                                      return '有効な数値を入力してください';
                                    }
                                    if (alcoholValue < 0) {
                                      return '0以上の値を入力してください';
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 備考
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '備考',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _remarksController,
                        decoration: const InputDecoration(
                          labelText: '備考',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              
              // ナビゲーションバーとの重複を避けるための余白
              SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }
}