import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../models/mileage_record.dart';

/// メーター値入力ウィジェット
/// 
/// 始業・終業点呼でのメーター値入力に使用
/// 数値キーパッド、フォーマット表示、バリデーション機能を提供
class MileageInputWidget extends StatefulWidget {
  final String label;
  final String? hintText;
  final double? initialValue;
  final bool isRequired;
  final bool isReadOnly;
  final ValueChanged<double?>? onChanged;
  final String? errorText;
  final Widget? suffixWidget;
  
  const MileageInputWidget({
    super.key,
    required this.label,
    this.hintText,
    this.initialValue,
    this.isRequired = false,
    this.isReadOnly = false,
    this.onChanged,
    this.errorText,
    this.suffixWidget,
  });

  @override
  State<MileageInputWidget> createState() => _MileageInputWidgetState();
}

class _MileageInputWidgetState extends State<MileageInputWidget> {
  late TextEditingController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue != null ? _formatMileage(widget.initialValue!) : ''
    );
    _controller.addListener(_onTextChanged);
  }
  
  @override
  void didUpdateWidget(MileageInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      _controller.text = widget.initialValue != null ? _formatMileage(widget.initialValue!) : '';
    }
  }
  
  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }
  
  void _onTextChanged() {
    final text = _controller.text.replaceAll(',', '');
    if (text.isEmpty) {
      widget.onChanged?.call(null);
      return;
    }
    
    final value = double.tryParse(text);
    widget.onChanged?.call(value);
  }
  
  String _formatMileage(double value) {
    // カンマ区切りでフォーマット（小数点以下は表示しない）
    return value.toInt().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ラベル
        RichText(
          text: TextSpan(
            text: widget.label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87,
            ),
            children: [
              if (widget.isRequired)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 16,
                  ),
                ),
            ],
          ),
        ),
        
        const SizedBox(height: 8),
        
        // 入力フィールド
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: widget.errorText != null
                ? Colors.red
                : Theme.of(context).colorScheme.outline,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(8),
            color: widget.isReadOnly
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(context).colorScheme.surface,
          ),
          child: Row(
            children: [
              // メイン入力フィールド
              Expanded(
                child: TextFormField(
                  controller: _controller,
                  readOnly: widget.isReadOnly,
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7), // 最大7桁
                    _MileageFormatter(), // カスタムフォーマッター
                  ],
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: widget.isReadOnly
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hintText ?? '例: 45,230',
                    hintStyle: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                    // suffixTextを削除して重複を回避
                    // suffixWidgetが提供されている場合はそちらを使用
                  ),
                  validator: widget.isRequired ? (value) {
                    if (value == null || value.isEmpty) {
                      return '${widget.label}を入力してください';
                    }
                    final numValue = double.tryParse(value.replaceAll(',', ''));
                    if (numValue == null) {
                      return '有効な数値を入力してください';
                    }
                    if (numValue < 0 || numValue > 999999) {
                      return 'メーター値は0〜999,999の範囲で入力してください';
                    }
                    return null;
                  } : null,
                ),
              ),
              
              // 単位表示（km）- ダークテーマ対応
              if (widget.suffixWidget != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    child: widget.suffixWidget!,
                  ),
                ),
            ],
          ),
        ),
        
        // エラーメッセージ
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.errorText!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 14,
              ),
            ),
          ),
      ],
    );
  }
}

/// メーター値フォーマッター
/// 入力時に自動的にカンマを挿入
class _MileageFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    // 数字のみを抽出
    final numericOnly = text.replaceAll(RegExp(r'[^\d]'), '');
    
    if (numericOnly.isEmpty) {
      return newValue.copyWith(text: '');
    }
    
    // カンマ区切りでフォーマット
    final formatted = numericOnly.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// 走行距離表示ウィジェット
/// GPS記録モード時の距離表示に使用
class DistanceDisplayWidget extends StatelessWidget {
  final String label;
  final double? distance;
  final bool isGpsCalculated;
  final VoidCallback? onRecalculate;
  
  const DistanceDisplayWidget({
    super.key,
    required this.label,
    this.distance,
    this.isGpsCalculated = false,
    this.onRecalculate,
  });

  String _formatDistance(double distance) {
    return '${distance.toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isGpsCalculated 
          ? Colors.green.shade50 
          : Colors.blue.shade50,
        border: Border.all(
          color: isGpsCalculated 
            ? Colors.green.shade200 
            : Colors.blue.shade200,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isGpsCalculated ? Icons.gps_fixed : Icons.calculate,
                color: isGpsCalculated ? Colors.green : Colors.blue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          Row(
            children: [
              Expanded(
                child: Text(
                  distance != null 
                    ? _formatDistance(distance!)
                    : '計算中...',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              
              if (onRecalculate != null)
                TextButton.icon(
                  onPressed: onRecalculate,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('再計算'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                  ),
                ),
            ],
          ),
          
          if (isGpsCalculated)
            const Text(
              'GPS測定による算出',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            const Text(
              'メーター値による算出',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

/// GPS記録選択ダイアログ（簡易版・後方互換性維持）
class GPSTrackingConfirmDialog extends StatelessWidget {
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  
  const GPSTrackingConfirmDialog({
    super.key,
    this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.gps_fixed, color: Colors.green),
          SizedBox(width: 8),
          Text('GPS走行距離記録'),
        ],
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日の業務でGPS走行距離記録を開始しますか？',
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'バックグラウンドで動作し、正確な走行距離を記録します。',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onCancel?.call();
          },
          child: const Text('いいえ（手動入力）'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm?.call();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: const Text('はい（GPS記録）'),
        ),
      ],
    );
  }
}

/// GPS設定ダイアログ（機能強化版）
/// 
/// GPS権限チェック、設定確認、エラーハンドリングを含む高機能版
class GPSSetupDialog extends StatefulWidget {
  final Function(bool useGPS)? onResult;
  final double? startMileage;
  
  const GPSSetupDialog({
    super.key,
    this.onResult,
    this.startMileage,
  });
  
  @override
  State<GPSSetupDialog> createState() => _GPSSetupDialogState();
}

class _GPSSetupDialogState extends State<GPSSetupDialog> {
  bool _isChecking = true;
  bool _hasLocationPermission = false;
  bool _isLocationServiceEnabled = false;
  String? _errorMessage;
  double? _currentAccuracy;
  
  @override
  void initState() {
    super.initState();
    _checkGPSStatus();
  }
  
  Future<void> _checkGPSStatus() async {
    try {
      // 権限確認
      final permissionService = PermissionHandler();
      _hasLocationPermission = await permissionService.hasLocationPermission();
      
      // GPSサービス確認  
      _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      
      // 現在位置の精度確認（可能であれば）
      if (_hasLocationPermission && _isLocationServiceEnabled) {
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 5),
            ),
          ).timeout(const Duration(seconds: 6));
          _currentAccuracy = position.accuracy;
        } catch (e) {
          // 位置取得に失敗してもエラーにはしない
          _currentAccuracy = null;
        }
      }
      
    } catch (e) {
      _errorMessage = 'GPS状態確認に失敗しました: $e';
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }
  
  Future<void> _requestPermissions() async {
    try {
      final permissionService = PermissionHandler();
      final granted = await permissionService.requestLocationPermission();
      
      setState(() {
        _hasLocationPermission = granted;
        if (!granted) {
          _errorMessage = '位置情報の権限が拒否されました';
        } else {
          _errorMessage = null;
        }
      });
      
      if (granted) {
        _checkGPSStatus(); // 権限が取得できたら再確認
      }
      
    } catch (e) {
      setState(() {
        _errorMessage = '権限要求に失敗しました: $e';
      });
    }
  }
  
  void _selectManualMode() {
    Navigator.of(context).pop();
    widget.onResult?.call(false);
  }
  
  void _selectGPSMode() {
    Navigator.of(context).pop();
    widget.onResult?.call(true);
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return AlertDialog(
        title: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('GPS確認中...'),
          ],
        ),
        content: const Text('GPS設定とアクセス権限を確認しています。'),
      );
    }
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _hasLocationPermission && _isLocationServiceEnabled
                ? Icons.gps_fixed
                : Icons.gps_off,
            color: _hasLocationPermission && _isLocationServiceEnabled
                ? Colors.green
                : Colors.orange,
          ),
          const SizedBox(width: 8),
          const Text('GPS走行距離記録'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.startMileage != null) ...[
              Text(
                '開始メーター値: ${widget.startMileage!.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} km',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            const Text(
              'GPS追跡を使用しますか？',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            
            // GPS状態表示
            _buildStatusCard(
              'GPS権限',
              _hasLocationPermission ? '許可済み' : '未許可',
              _hasLocationPermission ? Colors.green : Colors.red,
              _hasLocationPermission ? Icons.check_circle : Icons.cancel,
            ),
            const SizedBox(height: 8),
            
            _buildStatusCard(
              '位置サービス',
              _isLocationServiceEnabled ? '有効' : '無効',
              _isLocationServiceEnabled ? Colors.green : Colors.orange,
              _isLocationServiceEnabled ? Icons.location_on : Icons.location_off,
            ),
            
            if (_currentAccuracy != null) ...[
              const SizedBox(height: 8),
              _buildStatusCard(
                'GPS精度',
                '±${_currentAccuracy!.toStringAsFixed(0)}m',
                _currentAccuracy! <= 20 ? Colors.green : Colors.orange,
                Icons.my_location,
              ),
            ],
            
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // 機能説明
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'GPS記録の特徴',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('✓ バックグラウンドで自動記録', style: TextStyle(fontSize: 13)),
                  Text('✓ 正確な走行距離測定', style: TextStyle(fontSize: 13)),
                  Text('✓ 経路の詳細記録', style: TextStyle(fontSize: 13)),
                  Text('⚠ バッテリー消費増加', style: TextStyle(fontSize: 13, color: Colors.orange)),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        // 手動入力ボタン
        TextButton(
          onPressed: _selectManualMode,
          child: const Text('手動入力'),
        ),
        
        // 権限要求ボタン（必要時のみ）
        if (!_hasLocationPermission)
          TextButton(
            onPressed: _requestPermissions,
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
            ),
            child: const Text('権限を許可'),
          ),
        
        // GPS使用ボタン
        ElevatedButton(
          onPressed: (_hasLocationPermission && _isLocationServiceEnabled)
              ? _selectGPSMode
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: const Text('GPS使用'),
        ),
      ],
    );
  }
  
  Widget _buildStatusCard(
    String title,
    String status,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          Text(
            status,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 権限処理ヘルパークラス
class PermissionHandler {
  Future<bool> hasLocationPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission != LocationPermission.denied && 
             permission != LocationPermission.deniedForever;
    } catch (e) {
      return false;
    }
  }
  
  Future<bool> requestLocationPermission() async {
    try {
      final permission = await Geolocator.requestPermission();
      return permission != LocationPermission.denied && 
             permission != LocationPermission.deniedForever;
    } catch (e) {
      return false;
    }
  }
}

/// GPS品質表示ウィジェット
/// 
/// GPS追跡中の品質情報をリアルタイムで表示
class GPSQualityWidget extends StatelessWidget {
  final GPSQualityMetrics? qualityMetrics;
  final bool isTracking;
  final double currentDistance;
  final VoidCallback? onRefresh;
  
  const GPSQualityWidget({
    super.key,
    this.qualityMetrics,
    this.isTracking = false,
    this.currentDistance = 0.0,
    this.onRefresh,
  });
  
  @override
  Widget build(BuildContext context) {
    if (!isTracking) {
      return const SizedBox.shrink();
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border.all(color: Colors.green.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gps_fixed, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              const Text(
                'GPS追跡中',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
              const Spacer(),
              if (onRefresh != null)
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // 現在の距離
          Row(
            children: [
              const Icon(Icons.straighten, color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              Text(
                '現在の距離: ${currentDistance.toStringAsFixed(1)} km',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          
          if (qualityMetrics != null) ...[
            const SizedBox(height: 8),
            
            // GPS品質情報
            Row(
              children: [
                Expanded(
                  child: _buildQualityIndicator(
                    '精度',
                    '精度: ${qualityMetrics!.accuracyPercentage.toStringAsFixed(1)}%',
                    _getAccuracyColor(qualityMetrics!.accuracyPercentage),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildQualityIndicator(
                    'サンプル',
                    '${qualityMetrics!.totalLocationPoints}',
                    Colors.blue,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  child: _buildQualityIndicator(
                    '良好率',
                    '${_getGoodRate().toStringAsFixed(0)}%',
                    _getQualityRateColor(_getGoodRate()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildQualityIndicator(
                    'エラー',
                    '${qualityMetrics!.totalLocationPoints - qualityMetrics!.validLocationPoints}',
                    (qualityMetrics!.totalLocationPoints - qualityMetrics!.validLocationPoints) > 0 ? Colors.orange : Colors.green,
                  ),
                ),
              ],
            ),
          ],
          
          // 品質評価
          if (qualityMetrics != null) ...[
            const SizedBox(height: 12),
            _buildQualityAssessment(),
          ],
        ],
      ),
    );
  }
  
  Widget _buildQualityIndicator(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildQualityAssessment() {
    final accuracyPercentage = qualityMetrics!.accuracyPercentage;
    final validityRate = qualityMetrics!.validityRate * 100;
    
    String assessment;
    Color assessmentColor;
    IconData assessmentIcon;
    
    if (accuracyPercentage >= 80 && validityRate >= 90) {
      assessment = '優秀な GPS 品質';
      assessmentColor = Colors.green;
      assessmentIcon = Icons.check_circle;
    } else if (accuracyPercentage >= 60 && validityRate >= 75) {
      assessment = '良好な GPS 品質';
      assessmentColor = Colors.blue;
      assessmentIcon = Icons.info;
    } else if (accuracyPercentage >= 40 && validityRate >= 60) {
      assessment = '普通の GPS 品質';
      assessmentColor = Colors.orange;
      assessmentIcon = Icons.warning;
    } else {
      assessment = 'GPS 品質に注意';
      assessmentColor = Colors.red;
      assessmentIcon = Icons.error;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: assessmentColor.withOpacity(0.1),
        border: Border.all(color: assessmentColor.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(assessmentIcon, color: assessmentColor, size: 16),
          const SizedBox(width: 6),
          Text(
            assessment,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: assessmentColor,
            ),
          ),
        ],
      ),
    );
  }
  
  double _getGoodRate() {
    if (qualityMetrics == null) return 0.0;
    return qualityMetrics!.accuracyPercentage;
  }
  
  Color _getAccuracyColor(double percentage) {
    if (percentage >= 80) return Colors.green;
    if (percentage >= 60) return Colors.blue;
    if (percentage >= 40) return Colors.orange;
    return Colors.red;
  }
  
  Color _getQualityRateColor(double rate) {
    if (rate >= 80) return Colors.green;
    if (rate >= 60) return Colors.blue;
    if (rate >= 40) return Colors.orange;
    return Colors.red;
  }
}