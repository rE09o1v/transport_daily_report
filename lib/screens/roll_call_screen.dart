import 'package:flutter/material.dart';
import 'package:transport_daily_report/models/roll_call_record.dart';
import 'package:transport_daily_report/services/storage_service.dart';
import 'package:intl/intl.dart';

class RollCallScreen extends StatefulWidget {
  final String type; // 'start' または 'end'（始業点呼または終業点呼）

  const RollCallScreen({super.key, required this.type});

  @override
  _RollCallScreenState createState() => _RollCallScreenState();
}

class _RollCallScreenState extends State<RollCallScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storageService = StorageService();
  
  // フォームフィールド用のコントローラー
  final _inspectorNameController = TextEditingController();
  final _otherMethodDetailController = TextEditingController();
  final _remarksController = TextEditingController();
  final _alcoholValueController = TextEditingController();
  
  // フォームの状態
  String _method = '対面'; // デフォルトは対面
  bool _isAlcoholTestUsed = true;
  bool _hasDrunkAlcohol = false;
  
  // 現在時刻
  DateTime _currentDateTime = DateTime.now();
  
  @override
  void initState() {
    super.initState();
    _loadExistingRecord();
  }
  
  @override
  void dispose() {
    // コントローラーを破棄
    _inspectorNameController.dispose();
    _otherMethodDetailController.dispose();
    _remarksController.dispose();
    _alcoholValueController.dispose();
    super.dispose();
  }
  
  // 既存の記録を読み込む
  Future<void> _loadExistingRecord() async {
    try {
      final now = DateTime.now();
      final record = await _storageService.getRollCallRecordByDateAndType(now, widget.type);
      
      if (record != null) {
        if (!mounted) return;
        setState(() {
          _currentDateTime = record.datetime;
          _method = record.method;
          _inspectorNameController.text = record.inspectorName;
          _otherMethodDetailController.text = record.otherMethodDetail ?? '';
          _isAlcoholTestUsed = record.isAlcoholTestUsed;
          _hasDrunkAlcohol = record.hasDrunkAlcohol;
          _alcoholValueController.text = record.alcoholValue?.toString() ?? '';
          _remarksController.text = record.remarks ?? '';
        });
      }
    } catch (e) {
      print('Error loading existing record: $e');
    }
  }
  
  // 点呼記録を保存
  Future<void> _saveRecord() async {
    if (_formKey.currentState!.validate()) {
      try {
        // 既存の記録を確認
        final existingRecord = await _storageService.getRollCallRecordByDateAndType(_currentDateTime, widget.type);
        
        // アルコール検出値の変換
        double? alcoholValue;
        if (_alcoholValueController.text.isNotEmpty) {
          alcoholValue = double.tryParse(_alcoholValueController.text);
        }
        
        // 記録オブジェクトを作成
        final record = RollCallRecord(
          id: existingRecord?.id ?? RollCallRecord.generateId(),
          datetime: _currentDateTime,
          type: widget.type,
          method: _method,
          otherMethodDetail: _method == 'その他' ? _otherMethodDetailController.text : null,
          inspectorName: _inspectorNameController.text,
          isAlcoholTestUsed: _isAlcoholTestUsed,
          hasDrunkAlcohol: _hasDrunkAlcohol,
          alcoholValue: alcoholValue,
          remarks: _remarksController.text.isEmpty ? null : _remarksController.text,
        );
        
        // 記録を保存
        if (existingRecord != null) {
          await _storageService.updateRollCallRecord(record);
        } else {
          await _storageService.addRollCallRecord(record);
        }
        
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('点呼記録を保存しました')),
        );
        
        Navigator.of(context).pop();
      } catch (e) {
        print('Error saving record: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存に失敗しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.type == 'start' ? '始業点呼' : '終業点呼'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 点呼日時情報
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '点呼情報',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text('実施日時:', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              DateFormat('yyyy年MM月dd日 HH時mm分').format(_currentDateTime),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_calendar),
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _currentDateTime,
                                firstDate: DateTime.now().subtract(const Duration(days: 7)),
                                lastDate: DateTime.now().add(const Duration(days: 1)),
                              );
                              if (date != null) {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.fromDateTime(_currentDateTime),
                                );
                                if (time != null && mounted) {
                                  setState(() {
                                    _currentDateTime = DateTime(
                                      date.year,
                                      date.month,
                                      date.day,
                                      time.hour,
                                      time.minute,
                                    );
                                  });
                                }
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '点呼種類: ${widget.type == 'start' ? '始業点呼' : '終業点呼'}',
                        style: const TextStyle(fontSize: 16),
                      ),
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
              
              const SizedBox(height: 24),
              
              // 保存ボタン
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveRecord,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    '保存',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 