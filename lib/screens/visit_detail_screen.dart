import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:transport_daily_report/models/visit_record.dart';
import 'package:transport_daily_report/services/storage_service.dart';
import 'package:transport_daily_report/screens/location_map_picker_screen.dart';

class VisitDetailScreen extends StatefulWidget {
  final VisitRecord visitRecord;

  const VisitDetailScreen({super.key, required this.visitRecord});

  @override
  _VisitDetailScreenState createState() => _VisitDetailScreenState();
}

class _VisitDetailScreenState extends State<VisitDetailScreen> {
  final StorageService _storageService = StorageService();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  bool _isDeleting = false;
  bool _isEditingLocation = false;
  bool _isSaving = false;
  
  @override
  void initState() {
    super.initState();
    // 位置情報の初期値を設定
    if (widget.visitRecord.latitude != null && widget.visitRecord.longitude != null) {
      _latitudeController.text = widget.visitRecord.latitude!.toStringAsFixed(6);
      _longitudeController.text = widget.visitRecord.longitude!.toStringAsFixed(6);
    }
  }

  @override
  void dispose() {
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }
  
  Future<void> _deleteRecord() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除の確認'),
        content: const Text('この訪問記録を削除してもよろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // ダイアログを閉じる
              setState(() {
                _isDeleting = true;
              });
              
              try {
                await _storageService.deleteVisitRecord(widget.visitRecord.id);
                if (mounted) {
                  Navigator.pop(context, true); // 前の画面に戻る
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('訪問記録を削除しました')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  setState(() {
                    _isDeleting = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('削除中にエラーが発生しました: $e')),
                  );
                }
              }
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 位置情報更新機能
  Future<void> _updateLocationInfo() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updatedLatitude = double.tryParse(_latitudeController.text);
      final updatedLongitude = double.tryParse(_longitudeController.text);

      final updatedRecord = VisitRecord(
        id: widget.visitRecord.id,
        clientName: widget.visitRecord.clientName,
        arrivalTime: widget.visitRecord.arrivalTime,
        notes: widget.visitRecord.notes,
        latitude: updatedLatitude,
        longitude: updatedLongitude,
      );

      await _storageService.updateVisitRecord(updatedRecord);

      if (mounted) {
        setState(() {
          _isEditingLocation = false;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('位置情報を更新しました')),
        );
        // 前の画面に結果を返す
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新に失敗しました: $e')),
        );
      }
    }
  }

  // 緯度バリデーション
  String? _validateLatitude(String? value) {
    if (value == null || value.isEmpty) {
      return '緯度を入力してください';
    }
    final lat = double.tryParse(value);
    if (lat == null) {
      return '有効な数値を入力してください';
    }
    if (lat < -90 || lat > 90) {
      return '緯度は-90から90の範囲で入力してください';
    }
    return null;
  }

  // 経度バリデーション
  String? _validateLongitude(String? value) {
    if (value == null || value.isEmpty) {
      return '経度を入力してください';
    }
    final lng = double.tryParse(value);
    if (lng == null) {
      return '有効な数値を入力してください';
    }
    if (lng < -180 || lng > 180) {
      return '経度は-180から180の範囲で入力してください';
    }
    return null;
  }

  // マップピッカーを開く
  Future<void> _openMapPicker() async {
    final currentLat = widget.visitRecord.latitude;
    final currentLng = widget.visitRecord.longitude;
    
    final initialPosition = (currentLat != null && currentLng != null)
        ? LatLng(currentLat, currentLng)
        : null;

    final selectedPosition = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (context) => LocationMapPickerScreen(
          initialPosition: initialPosition,
        ),
      ),
    );

    if (selectedPosition != null && mounted) {
      // 選択された座標を入力フィールドに反映
      setState(() {
        _latitudeController.text = selectedPosition.latitude.toStringAsFixed(6);
        _longitudeController.text = selectedPosition.longitude.toStringAsFixed(6);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy年MM月dd日(E)', 'ja_JP');
    final timeFormat = DateFormat('HH:mm');
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('訪問詳細'),
        actions: [
          if (widget.visitRecord.latitude != null && widget.visitRecord.longitude != null)
            IconButton(
              icon: Icon(_isEditingLocation ? Icons.close : Icons.edit_location),
              onPressed: _isSaving || _isDeleting ? null : () {
                setState(() {
                  _isEditingLocation = !_isEditingLocation;
                });
              },
              tooltip: _isEditingLocation ? '編集をキャンセル' : '位置情報を編集',
            ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _isDeleting ? null : _deleteRecord,
          ),
        ],
      ),
      body: _isDeleting
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    margin: const EdgeInsets.only(bottom: 16.0),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '訪問日時',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                dateFormat.format(widget.visitRecord.arrivalTime),
                                style: const TextStyle(fontSize: 18),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.access_time, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '訪問時刻: ${timeFormat.format(widget.visitRecord.arrivalTime)}',
                                style: const TextStyle(fontSize: 18),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  Card(
                    margin: const EdgeInsets.only(bottom: 16.0),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '得意先情報',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.business, size: 20),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  widget.visitRecord.clientName,
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  if (widget.visitRecord.notes != null && widget.visitRecord.notes!.isNotEmpty)
                    Card(
                      margin: const EdgeInsets.only(bottom: 16.0),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'メモ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.visitRecord.notes!,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  if (widget.visitRecord.latitude != null && widget.visitRecord.longitude != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '位置情報',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                                const Spacer(),
                                if (_isEditingLocation && !_isSaving)
                                  Row(
                                    children: [
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _isEditingLocation = false;
                                            // 元の値にリセット
                                            _latitudeController.text = widget.visitRecord.latitude!.toStringAsFixed(6);
                                            _longitudeController.text = widget.visitRecord.longitude!.toStringAsFixed(6);
                                          });
                                        },
                                        child: const Text('キャンセル'),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: _updateLocationInfo,
                                        child: const Text('保存'),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_isSaving)
                              const Center(child: CircularProgressIndicator())
                            else if (_isEditingLocation)
                              Form(
                                key: _formKey,
                                child: Column(
                                  children: [
                                    TextFormField(
                                      controller: _latitudeController,
                                      decoration: const InputDecoration(
                                        labelText: '緯度',
                                        hintText: '例: 35.681236',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.location_on),
                                      ),
                                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                                      validator: _validateLatitude,
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _longitudeController,
                                      decoration: const InputDecoration(
                                        labelText: '経度',
                                        hintText: '例: 139.767125',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.location_on),
                                      ),
                                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                                      validator: _validateLongitude,
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _openMapPicker,
                                        icon: const Icon(Icons.map),
                                        label: const Text('地図で選択'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Row(
                                children: [
                                  const Icon(Icons.location_on, size: 20),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      '緯度: ${widget.visitRecord.latitude!.toStringAsFixed(6)}\n経度: ${widget.visitRecord.longitude!.toStringAsFixed(6)}',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
} 