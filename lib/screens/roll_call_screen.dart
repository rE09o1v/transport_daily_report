import 'package:flutter/material.dart';
import 'package:transport_daily_report/models/roll_call_record.dart';
import 'package:transport_daily_report/services/storage_service.dart';

class RollCallScreen extends StatefulWidget {
  const RollCallScreen({super.key});

  @override
  _RollCallScreenState createState() => _RollCallScreenState();
}

class _RollCallScreenState extends State<RollCallScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storageService = StorageService();

  // Form field controllers
  final _inspectorNameController = TextEditingController();
  final _otherMethodDetailController = TextEditingController();
  final _remarksController = TextEditingController();
  final _alcoholValueController = TextEditingController();

  // Form state
  String _method = '対面';
  bool _isAlcoholTestUsed = true;
  bool _hasDrunkAlcohol = false;

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
      }
    });
  }


  Future<void> _saveStartRecord() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isProcessing = true);

    try {
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

    setState(() => _isProcessing = true);

    try {
      final record = _createRollCallRecord('end');
      await _storageService.addRollCallRecord(record);

      if (!mounted) return;
      setState(() {
        _hasEndRecord = true;
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('終業点呼を記録しました'),
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
      startMileage: null,
      endMileage: null,
      calculatedDistance: null,
      gpsTrackingEnabled: false,
      gpsTrackingId: null,
      mileageValidationFlags: [],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('点呼記録'),
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