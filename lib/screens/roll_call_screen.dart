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

  @override
  void initState() {
    super.initState();
    _loadExistingRecord();
    // No longer need listeners here, we will use ValueListenableBuilder in the build method
  }

  @override
  void dispose() {
    _inspectorNameController.dispose();
    _otherMethodDetailController.dispose();
    _remarksController.dispose();
    _alcoholValueController.dispose();
    super.dispose();
  }
  
  Future<void> _loadExistingRecord() async {
    final now = DateTime.now();
    final startRecord = await _storageService.getRollCallRecordByDateAndType(now, 'start');
    final endRecord = await _storageService.getRollCallRecordByDateAndType(now, 'end');
    final isTracking = await _gpsService.isTracking;

    if (!mounted) return;

    // Use a local variable for currentGpsDistance to avoid calling setState here
    double currentGpsDistance = 0.0;

    if(isTracking) {
        final prefs = await SharedPreferences.getInstance();
        _startMileage = prefs.getDouble(GPSTrackingService.startMileageKey);
        currentGpsDistance = prefs.getDouble(GPSTrackingService.distanceKey) ?? 0.0;
    }

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

      if(isTracking) {
          _gpsTrackingEnabled = true;
          _updateEndMileage(currentGpsDistance);
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
      _calculatedDistance = _endMileage! - _startMileage!;
    }
  }

  void _updateEndMileage(double currentGpsDistance) {
      if(_startMileage != null) {
          _endMileage = _startMileage! + currentGpsDistance;
          _calculatedDistance = currentGpsDistance;
      }
  }

  Future<void> _showGpsConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GPS追跡の確認'),
        content: const Text('GPSによる走行距離の自動記録を有効にしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('いいえ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('はい、有効にします'),
          ),
        ],
      ),
    );
    if (result == true) {
      setState(() => _gpsTrackingEnabled = true);
    }
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
        await Future.delayed(const Duration(milliseconds: 500));
        final prefs = await SharedPreferences.getInstance();
        final finalDistance = prefs.getDouble(GPSTrackingService.distanceKey) ?? _gpsService.currentDistance.value;
        _updateEndMileage(finalDistance);
      }

      final record = _createRollCallRecord('end');
      await _storageService.addRollCallRecord(record);

      // GPS追跡が有効だった場合、移動距離をDailyRecordに保存
      if (_gpsTrackingEnabled && _calculatedDistance != null) {
        await _storageService.saveTotalDistance(_calculatedDistance! * 1000); // キロメートルをメートルに変換
      }

      if (!mounted) return;
      setState(() {
        _hasEndRecord = true;
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_gpsTrackingEnabled 
            ? '終業点呼を記録しました（移動距離: ${_calculatedDistance?.toStringAsFixed(2)}km）' 
            : '終業点呼を記録しました'),
          backgroundColor: Colors.green,
        ),
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
      gpsTrackingId: null,
      mileageValidationFlags: [],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('点呼記録'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _gpsService.isTrackingNotifier,
            builder: (context, isTracking, child) {
              if (!isTracking) return const SizedBox.shrink();
              return const _GpsIndicator();
            },
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
              _RollCallActions(
                hasStartRecord: _hasStartRecord,
                hasEndRecord: _hasEndRecord,
                isProcessing: _isProcessing,
                onStart: _saveStartRecord,
                onEnd: _saveEndRecord,
              ),
              if (_isProcessing)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
              const SizedBox(height: 24),
              _MileageSection(
                hasStartRecord: _hasStartRecord,
                hasEndRecord: _hasEndRecord,
                startMileage: _startMileage,
                endMileage: _endMileage,
                calculatedDistance: _calculatedDistance,
                gpsTrackingEnabled: _gpsTrackingEnabled,
                mileageErrorText: _mileageErrorText,
                onStartMileageChanged: _onStartMileageChanged,
                onEndMileageChanged: _onEndMileageChanged,
                onGpsEnableChanged: (value) {
                  if (value) {
                    _showGpsConfirmDialog();
                  } else {
                    setState(() => _gpsTrackingEnabled = false);
                  }
                },
              ),
              const SizedBox(height: 16),
              _MethodSection(
                method: _method,
                otherMethodDetailController: _otherMethodDetailController,
                onChanged: (value) => setState(() => _method = value),
              ),
              const SizedBox(height: 16),
              _InspectorSection(controller: _inspectorNameController),
              const SizedBox(height: 16),
              _AlcoholSection(
                  isAlcoholTestUsed: _isAlcoholTestUsed,
                  hasDrunkAlcohol: _hasDrunkAlcohol,
                  alcoholValueController: _alcoholValueController,
                  onAlcoholTestUsedChanged: (value) => setState(() => _isAlcoholTestUsed = value),
                  onHasDrunkAlcoholChanged: (value) => setState(() => _hasDrunkAlcohol = value),
              ),
              const SizedBox(height: 16),
              _RemarksSection(controller: _remarksController),
              SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Extracted Widgets for Performance ---

class _GpsIndicator extends StatelessWidget {
  const _GpsIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(right: 16.0),
      child: Row(
        children: [
          Icon(Icons.gps_fixed, color: Colors.green, size: 20),
          SizedBox(width: 4),
          Text('GPS', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _RollCallActions extends StatelessWidget {
  final bool hasStartRecord;
  final bool hasEndRecord;
  final bool isProcessing;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  const _RollCallActions({
    required this.hasStartRecord,
    required this.hasEndRecord,
    required this.isProcessing,
    required this.onStart,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: hasStartRecord || isProcessing ? null : onStart,
            icon: Icon(hasStartRecord ? Icons.check : Icons.play_arrow),
            label: const Text('始業点呼'),
            style: ElevatedButton.styleFrom(
              backgroundColor: hasStartRecord ? Colors.green.shade100 : Theme.of(context).primaryColor,
              foregroundColor: hasStartRecord ? Colors.green.shade700 : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: !hasStartRecord || hasEndRecord || isProcessing ? null : onEnd,
            icon: Icon(hasEndRecord ? Icons.check : Icons.stop),
            label: const Text('終業点呼'),
            style: ElevatedButton.styleFrom(
              backgroundColor: hasEndRecord ? Colors.green.shade100 : Colors.red.shade600,
              foregroundColor: hasEndRecord ? Colors.green.shade700 : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}

class _MileageSection extends StatelessWidget {
    final bool hasStartRecord;
    final bool hasEndRecord;
    final double? startMileage;
    final double? endMileage;
    final double? calculatedDistance;
    final bool gpsTrackingEnabled;
    final String? mileageErrorText;
    final ValueChanged<double?> onStartMileageChanged;
    final ValueChanged<double?> onEndMileageChanged;
    final ValueChanged<bool> onGpsEnableChanged;

    const _MileageSection({
        required this.hasStartRecord,
        required this.hasEndRecord,
        this.startMileage,
        this.endMileage,
        this.calculatedDistance,
        required this.gpsTrackingEnabled,
        this.mileageErrorText,
        required this.onStartMileageChanged,
        required this.onEndMileageChanged,
        required this.onGpsEnableChanged,
    });

    @override
    Widget build(BuildContext context) {
        final gpsService = GPSTrackingService();
        return Card(
            child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        const Text('メーター値記録', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        if (!hasStartRecord) ...[
                            MileageInputWidget(
                                label: '開始時メーター値',
                                hintText: '例: 45,230',
                                initialValue: startMileage,
                                isRequired: true,
                                onChanged: onStartMileageChanged,
                                errorText: mileageErrorText,
                            ),
                            const SizedBox(height: 16),
                            Row(
                                children: [
                                    Checkbox(value: gpsTrackingEnabled, onChanged: (v) => onGpsEnableChanged(v ?? false)),
                                    const Text('GPS距離測定を有効にする'),
                                ],
                            ),
                        ] else if (!hasEndRecord) ...[
                            MileageInputWidget(label: '開始時メーター値', initialValue: startMileage, isReadOnly: true),
                            const SizedBox(height: 16),
                            if (gpsTrackingEnabled)
                                ValueListenableBuilder<double>(
                                    valueListenable: gpsService.currentDistance,
                                    builder: (context, currentGpsDistance, child) {
                                        final calculatedEndMileage = (startMileage ?? 0) + currentGpsDistance;
                                        return Column(
                                            children: [
                                                _GpsDistanceDisplay(currentGpsDistance: currentGpsDistance),
                                                const SizedBox(height: 16),
                                                MileageInputWidget(label: '終了時メーター値（自動算出）', initialValue: calculatedEndMileage, isReadOnly: true),
                                            ],
                                        );
                                    },
                                )
                            else
                                _ManualEndMileageInput(
                                    endMileage: endMileage,
                                    calculatedDistance: calculatedDistance,
                                    onEndMileageChanged: onEndMileageChanged,
                                    mileageErrorText: mileageErrorText,
                                ),
                        ] else
                            const Text('本日の点呼記録は完了しました。'),
                    ],
                ),
            ),
        );
    }
}

class _GpsDistanceDisplay extends StatelessWidget {
  final double currentGpsDistance;
  const _GpsDistanceDisplay({required this.currentGpsDistance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          const Icon(Icons.gps_fixed, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GPS測定走行距離', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('${currentGpsDistance.toStringAsFixed(2)} km', style: TextStyle(fontSize: 18, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualEndMileageInput extends StatelessWidget {
    final double? endMileage;
    final double? calculatedDistance;
    final ValueChanged<double?> onEndMileageChanged;
    final String? mileageErrorText;

    const _ManualEndMileageInput({this.endMileage, this.calculatedDistance, required this.onEndMileageChanged, this.mileageErrorText});

    @override
    Widget build(BuildContext context) {
        return Column(
            children: [
                MileageInputWidget(
                    label: '終了時メーター値',
                    hintText: '例: 45,476',
                    initialValue: endMileage,
                    isRequired: true,
                    onChanged: onEndMileageChanged,
                    errorText: mileageErrorText,
                ),
                if (calculatedDistance != null) ... [
                    const SizedBox(height: 12),
                    Text('走行距離: ${calculatedDistance!.toStringAsFixed(1)} km', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                ]
            ],
        );
    }
}

class _MethodSection extends StatelessWidget {
  final String method;
  final TextEditingController otherMethodDetailController;
  final ValueChanged<String> onChanged;

  const _MethodSection({required this.method, required this.otherMethodDetailController, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ const Text('点呼方法', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16), Row(children: [ Radio<String>(value: '対面', groupValue: method, onChanged: (v) => onChanged(v!)), const Text('対面'), const SizedBox(width: 16), Radio<String>(value: 'その他', groupValue: method, onChanged: (v) => onChanged(v!)), const Text('その他'), ]), if (method == 'その他') ...[ const SizedBox(height: 16), TextFormField(controller: otherMethodDetailController, decoration: const InputDecoration(labelText: '点呼方法の詳細'), validator: (v) => v==null||v.isEmpty?'詳細を入力':null), ], ],),),);
  }
}

class _InspectorSection extends StatelessWidget {
  final TextEditingController controller;
  const _InspectorSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ const Text('点呼執行者', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16), TextFormField(controller: controller, decoration: const InputDecoration(labelText: '点呼執行者名'), validator: (v) => v==null||v.isEmpty?'執行者名を入力':null), ],),),);
  }
}

class _AlcoholSection extends StatelessWidget {
    final bool isAlcoholTestUsed;
    final bool hasDrunkAlcohol;
    final TextEditingController alcoholValueController;
    final ValueChanged<bool> onAlcoholTestUsedChanged;
    final ValueChanged<bool> onHasDrunkAlcoholChanged;

    const _AlcoholSection({required this.isAlcoholTestUsed, required this.hasDrunkAlcohol, required this.alcoholValueController, required this.onAlcoholTestUsedChanged, required this.onHasDrunkAlcoholChanged});

    @override
    Widget build(BuildContext context) {
        return Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ const Text('アルコールチェック', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16), Row(children: [const Text("検知器使用:"), Radio<bool>(value: true, groupValue: isAlcoholTestUsed, onChanged: (v) => onAlcoholTestUsedChanged(v!)), const Text('有'), Radio<bool>(value: false, groupValue: isAlcoholTestUsed, onChanged: (v) => onAlcoholTestUsedChanged(v!)), const Text('無')]), const SizedBox(height: 16), Row(children: [const Text("酒気帯び:"), Radio<bool>(value: false, groupValue: hasDrunkAlcohol, onChanged: (v) => onHasDrunkAlcoholChanged(v!)), const Text('無'), Radio<bool>(value: true, groupValue: hasDrunkAlcohol, onChanged: (v) => onHasDrunkAlcoholChanged(v!)), const Text('有')]), if (isAlcoholTestUsed) ...[const SizedBox(height: 16), TextFormField(controller: alcoholValueController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'アルコール検出値 (mg/L)'), validator: (v) { if(v!=null&&v.isNotEmpty&&double.tryParse(v)==null) return '数値を入力'; return null;})]]),),);
    }
}

class _RemarksSection extends StatelessWidget {
  final TextEditingController controller;
  const _RemarksSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ const Text('備考', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16), TextFormField(controller: controller, decoration: const InputDecoration(labelText: '特記事項など'), maxLines: 3,), ],),),);
  }
}