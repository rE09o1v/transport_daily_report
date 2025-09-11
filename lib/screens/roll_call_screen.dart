import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_daily_report/models/roll_call_record.dart';
import 'package:transport_daily_report/services/storage_service.dart';
import 'package:transport_daily_report/services/gps_tracking_service.dart';
import 'package:transport_daily_report/services/background_service.dart'; // For keys
import 'package:transport_daily_report/widgets/mileage_input_widget.dart';

class RollCallScreen extends StatefulWidget {
  const RollCallScreen({super.key});

  @override
  _RollCallScreenState createState() => _RollCallScreenState();
}

class _RollCallScreenState extends State<RollCallScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storageService = StorageService();
  final _gpsService = GPSTrackingService();

  // Form field controllers
  final _inspectorNameController = TextEditingController();
  final _otherMethodDetailController = TextEditingController();
  final _remarksController = TextEditingController();
  final _alcoholValueController = TextEditingController();

  // Form state
  String _method = '対面';
  bool _isAlcoholTestUsed = true;
  bool _hasDrunkAlcohol = false;

  // Mileage state
  double? _startMileage;
  double? _endMileage;
  double? _calculatedDistance;
  bool _gpsTrackingEnabled = false;
  String? _mileageErrorText;

  // Roll call record state
  bool _hasStartRecord = false;
  bool _hasEndRecord = false;
  bool _isProcessing = false;

  // GPS state from service
  bool _isGpsTracking = false;
  double _currentGpsDistance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadExistingRecord();
    _gpsService.isTrackingNotifier.addListener(_onGpsTrackingChanged);
    _gpsService.currentDistance.addListener(_onGpsDistanceChanged);
  }

  @override
  void dispose() {
    _inspectorNameController.dispose();
    _otherMethodDetailController.dispose();
    _remarksController.dispose();
    _alcoholValueController.dispose();
    _gpsService.isTrackingNotifier.removeListener(_onGpsTrackingChanged);
    _gpsService.currentDistance.removeListener(_onGpsDistanceChanged);
    super.dispose();
  }

  void _onGpsTrackingChanged() {
    if (mounted) {
      setState(() {
        _isGpsTracking = _gpsService.isTrackingNotifier.value;
      });
    }
  }

  void _onGpsDistanceChanged() {
    if (mounted) {
      setState(() {
        _currentGpsDistance = _gpsService.currentDistance.value;
        if (_gpsTrackingEnabled) {
          _updateEndMileage();
        }
      });
    }
  }
  
  Future<void> _loadExistingRecord() async {
    final now = DateTime.now();
    final startRecord = await _storageService.getRollCallRecordByDateAndType(now, 'start');
    final endRecord = await _storageService.getRollCallRecordByDateAndType(now, 'end');

    final prefs = await SharedPreferences.getInstance();
    final isTracking = await _gpsService.isTracking;

    if (!mounted) return;

    setState(() {
      _hasStartRecord = startRecord != null;
      _hasEndRecord = endRecord != null;

      final latestRecord = endRecord ?? startRecord;
      if (latestRecord != null) {
        _method = latestRecord.method;
        _inspectorNameController.text = latestRecord.inspectorName;
        _otherMethodDetailController.text = latestRecord.otherMethodDetail ?? '';
        _isAlcoholTestUsed = latestRecord.isAlcoholTestUsed;
        _hasDrunkAlcohol = latestRecord.hasDrunkAlcohol;
        _alcoholValueController.text = latestRecord.alcoholValue?.toString() ?? '';
        _remarksController.text = latestRecord.remarks ?? '';

        _startMileage = latestRecord.startMileage;
        _endMileage = latestRecord.endMileage;
        _calculatedDistance = latestRecord.calculatedDistance;
        _gpsTrackingEnabled = latestRecord.gpsTrackingEnabled;
      }

      // If tracking is active, ensure UI reflects this
      if(isTracking) {
          _gpsTrackingEnabled = true;
          _isGpsTracking = true;
          _startMileage = prefs.getDouble(startMileageKey);
          _currentGpsDistance = prefs.getDouble(distanceKey) ?? 0.0;
          _updateEndMileage();
      }
    });
  }

  void _onStartMileageChanged(double? value) {
    setState(() => _startMileage = value);
  }

  void _onEndMileageChanged(double? value) {
    setState(() {
      _endMileage = value;
      _updateCalculatedDistance();
    });
  }

  void _updateCalculatedDistance() {
    if (_startMileage != null && _endMileage != null && !_gpsTrackingEnabled) {
      setState(() {
        _calculatedDistance = _endMileage! - _startMileage!;
      });
    }
  }

  void _updateEndMileage() {
      if(_startMileage != null) {
          _endMileage = _startMileage! + _currentGpsDistance;
          _calculatedDistance = _currentGpsDistance;
      }
  }

  Future<void> _showGpsConfirmDialog() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GPS追跡の確認'),
        content: const Text('GPSによる走行距離の自動記録を有効にしますか？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _gpsTrackingEnabled = false);
            },
            child: const Text('いいえ'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _gpsTrackingEnabled = true);
            },
            child: const Text('はい、有効にします'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveStartRecord() async {
    if (!_formKey.currentState!.validate()) return;

    if (_startMileage == null) {
        setState(() => _mileageErrorText = '開始時メーター値を入力してください。');
        return;
    }

    setState(() => _isProcessing = true);

    try {
      if (_gpsTrackingEnabled) {
        await _gpsService.startTracking(startMileage: _startMileage!);
      }

      final record = _createRollCallRecord('start');
      await _storageService.addRollCallRecord(record);

      if (!mounted) return;
      setState(() {
        _hasStartRecord = true;
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('始業点呼を記録しました'), backgroundColor: Colors.green),
      );
    } catch (e) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e')),
      );
    }
  }

  Future<void> _saveEndRecord() async {
    if (!_formKey.currentState!.validate()) return;

    if (_endMileage == null && !_gpsTrackingEnabled) {
        setState(() => _mileageErrorText = '終了時メーター値を入力してください。');
        return;
    }

    setState(() => _isProcessing = true);

    try {
      if (_gpsTrackingEnabled) {
        await _gpsService.stopTracking();
        // Give a moment for the service to write the final value
        await Future.delayed(const Duration(milliseconds: 500));
        final prefs = await SharedPreferences.getInstance();
        _currentGpsDistance = prefs.getDouble(distanceKey) ?? _currentGpsDistance;
        _updateEndMileage();
      }

      final record = _createRollCallRecord('end');
      await _storageService.addRollCallRecord(record);

      if (!mounted) return;
      setState(() {
        _hasEndRecord = true;
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('終業点呼を記録しました'), backgroundColor: Colors.green),
      );
    } catch (e) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e')),
      );
    }
  }

  RollCallRecord _createRollCallRecord(String type) {
    double? alcoholValue;
    if (_alcoholValueController.text.isNotEmpty) {
      alcoholValue = double.tryParse(_alcoholValueController.text);
    }
    return RollCallRecord(
      id: RollCallRecord.generateId(),
      datetime: DateTime.now(),
      type: type,
      method: _method,
      otherMethodDetail: _method == 'その他' ? _otherMethodDetailController.text : null,
      inspectorName: _inspectorNameController.text,
      isAlcoholTestUsed: _isAlcoholTestUsed,
      hasDrunkAlcohol: _hasDrunkAlcohol,
      alcoholValue: alcoholValue,
      remarks: _remarksController.text.isEmpty ? null : _remarksController.text,
      startMileage: _startMileage,
      endMileage: type == 'end' ? _endMileage : null,
      calculatedDistance: type == 'end' ? _calculatedDistance : null,
      gpsTrackingEnabled: _gpsTrackingEnabled,
      gpsTrackingId: null, // This can be removed or handled differently
      mileageValidationFlags: [],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('点呼記録'),
        actions: [
          if (_isGpsTracking)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                children: [
                  Icon(Icons.gps_fixed, color: Colors.green, size: 20),
                  const SizedBox(width: 4),
                  Text('GPS', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
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
              if (_isGpsTracking) ...[
                // GPS status display
              ],
              Row(
                children: [
                  Expanded(child: _buildStartButton()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildEndButton()),
                ],
              ),
              if (_isProcessing) const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
              ),
              const SizedBox(height: 24),
              _buildMileageSection(),
              const SizedBox(height: 16),
              _buildMethodSection(),
              const SizedBox(height: 16),
              _buildInspectorSection(),
              const SizedBox(height: 16),
              _buildAlcoholSection(),
              const SizedBox(height: 16),
              _buildRemarksSection(),
              SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStartButton() => ElevatedButton.icon(
    onPressed: _hasStartRecord || _isProcessing ? null : _saveStartRecord,
    icon: Icon(_hasStartRecord ? Icons.check : Icons.play_arrow),
    label: Text(_hasStartRecord ? '始業点呼完了' : '始業点呼'),
    style: ElevatedButton.styleFrom(
      backgroundColor: _hasStartRecord ? Colors.green.shade100 : Theme.of(context).primaryColor,
      foregroundColor: _hasStartRecord ? Colors.green.shade700 : Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16),
    ),
  );

  Widget _buildEndButton() => ElevatedButton.icon(
    onPressed: !_hasStartRecord || _hasEndRecord || _isProcessing ? null : _saveEndRecord,
    icon: Icon(_hasEndRecord ? Icons.check : Icons.stop),
    label: Text(_hasEndRecord ? '終業点呼完了' : '終業点呼'),
    style: ElevatedButton.styleFrom(
      backgroundColor: _hasEndRecord ? Colors.green.shade100 : Colors.red.shade600,
      foregroundColor: _hasEndRecord ? Colors.green.shade700 : Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16),
    ),
  );

  Widget _buildMileageSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('メーター値記録', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (!_hasStartRecord) ...[
              // Start of day
              MileageInputWidget(
                label: '開始時メーター値',
                hintText: '例: 45,230',
                initialValue: _startMileage,
                isRequired: true,
                onChanged: _onStartMileageChanged,
                errorText: _mileageErrorText,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: _gpsTrackingEnabled,
                    onChanged: (value) {
                      if (value == true) {
                        _showGpsConfirmDialog();
                      } else {
                        setState(() => _gpsTrackingEnabled = false);
                      }
                    },
                  ),
                  const Text('GPS距離測定を有効にする'),
                ],
              ),
            ] else if (!_hasEndRecord) ...[
              // During work day
              MileageInputWidget(label: '開始時メーター値', initialValue: _startMileage, isReadOnly: true),
              const SizedBox(height: 16),
              if (_gpsTrackingEnabled) ...[
                // GPS Mode
                _buildGpsDistanceDisplay(),
                const SizedBox(height: 16),
                MileageInputWidget(label: '終了時メーター値（自動算出）', initialValue: _endMileage, isReadOnly: true),
              ] else ...[
                // Manual Mode
                MileageInputWidget(
                  label: '終了時メーター値',
                  hintText: '例: 45,476',
                  initialValue: _endMileage,
                  isRequired: true,
                  onChanged: _onEndMileageChanged,
                  errorText: _mileageErrorText,
                ),
                if (_calculatedDistance != null) ... [
                    const SizedBox(height: 12),
                    Text('走行距離: ${_calculatedDistance!.toStringAsFixed(1)} km', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                ]
              ],
            ] else ...[
              // End of day
              const Text('本日の点呼記録は完了しました。'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGpsDistanceDisplay() {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Icon(Icons.gps_fixed, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('GPS測定走行距離', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${_currentGpsDistance.toStringAsFixed(2)} km', style: TextStyle(fontSize: 18, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      );
  }

  // Other form sections (method, inspector, alcohol, remarks) are omitted for brevity
  // but would be included here as separate builder methods.
  Widget _buildMethodSection() { return Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ const Text('点呼方法', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16), Row(children: [ Radio<String>(value: '対面', groupValue: _method, onChanged: (v) => setState(()=>_method=v!)), const Text('対面'), const SizedBox(width: 16), Radio<String>(value: 'その他', groupValue: _method, onChanged: (v) => setState(()=>_method=v!)), const Text('その他'), ]), if (_method == 'その他') ...[ const SizedBox(height: 16), TextFormField(controller: _otherMethodDetailController, decoration: const InputDecoration(labelText: '点呼方法の詳細'), validator: (v) => v==null||v.isEmpty?'詳細を入力':null), ], ],),),); }
  Widget _buildInspectorSection() { return Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ const Text('点呼執行者', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16), TextFormField(controller: _inspectorNameController, decoration: const InputDecoration(labelText: '点呼執行者名'), validator: (v) => v==null||v.isEmpty?'執行者名を入力':null), ],),),); }
  Widget _buildAlcoholSection() { return Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ const Text('アルコールチェック', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16), Row(children: [const Text("検知器使用:"), Radio<bool>(value: true, groupValue: _isAlcoholTestUsed, onChanged: (v) => setState(()=>_isAlcoholTestUsed=v!)), const Text('有'), Radio<bool>(value: false, groupValue: _isAlcoholTestUsed, onChanged: (v) => setState(()=>_isAlcoholTestUsed=v!)), const Text('無')]), const SizedBox(height: 16), Row(children: [const Text("酒気帯び:"), Radio<bool>(value: false, groupValue: _hasDrunkAlcohol, onChanged: (v) => setState(()=>_hasDrunkAlcohol=v!)), const Text('無'), Radio<bool>(value: true, groupValue: _hasDrunkAlcohol, onChanged: (v) => setState(()=>_hasDrunkAlcohol=v!)), const Text('有')]), if (_isAlcoholTestUsed) ...[const SizedBox(height: 16), TextFormField(controller: _alcoholValueController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'アルコール検出値 (mg/L)'), validator: (v) { if(v!=null&&v.isNotEmpty&&double.tryParse(v)==null) return '数値を入力'; return null;})]]),),); }
  Widget _buildRemarksSection() { return Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ const Text('備考', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16), TextFormField(controller: _remarksController, decoration: const InputDecoration(labelText: '特記事項など'), maxLines: 3,), ],),),); }
}