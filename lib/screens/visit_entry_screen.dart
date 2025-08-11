import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:transport_daily_report/models/client.dart';
import 'package:transport_daily_report/models/visit_record.dart';
import 'package:transport_daily_report/services/location_service.dart';
import 'package:transport_daily_report/services/storage_service.dart';

// 位置情報取得状態を管理するenum
enum LocationStatus {
  unknown,      // 取得前
  loading,      // 取得中
  success,      // 取得成功
  failed,       // 取得失敗
  permissionDenied, // 権限拒否
}

class VisitEntryScreen extends StatefulWidget {
  final Client? selectedClient;

  const VisitEntryScreen({super.key, this.selectedClient});

  @override
  _VisitEntryScreenState createState() => _VisitEntryScreenState();
}

class _VisitEntryScreenState extends State<VisitEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clientNameController = TextEditingController();
  final _notesController = TextEditingController();
  final LocationService _locationService = LocationService();
  final StorageService _storageService = StorageService();

  DateTime _selectedTime = DateTime.now();
  Position? _currentPosition;
  LocationStatus _locationStatus = LocationStatus.unknown;
  bool _isLoading = false;
  List<Client> _recentClients = [];
  List<Client> _nearbyClients = [];

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  Future<void> _initScreen() async {
    // クライアントが選択されている場合は、そのクライアント情報をセット
    if (widget.selectedClient != null) {
      _clientNameController.text = widget.selectedClient!.name;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 現在位置の取得
      await _getCurrentLocation();

      // 顧客リストの読み込み
      await _loadClients();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('初期化中にエラーが発生しました: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;
    setState(() {
      _locationStatus = LocationStatus.loading;
    });

    try {
      final position = await _locationService.getCurrentLocation();
      if (!mounted) return;
      
      setState(() {
        _currentPosition = position;
        _locationStatus = position != null ? LocationStatus.success : LocationStatus.failed;
      });
    } catch (e) {
      debugPrint('位置情報の取得に失敗しました: $e');
      if (!mounted) return;
      
      setState(() {
        _currentPosition = null;
        // 権限拒否かその他のエラーかを判別
        if (e.toString().contains('permission') || e.toString().contains('Permission')) {
          _locationStatus = LocationStatus.permissionDenied;
        } else {
          _locationStatus = LocationStatus.failed;
        }
      });
    }
  }

  Future<void> _loadClients() async {
    try {
      final allClients = await _storageService.loadClients();
      
      // 近くの顧客を検索
      final nearbyClients = _currentPosition != null
          ? await _locationService.findNearbyClients(allClients)
          : <Client>[];
      
      // 最近の顧客（最大5件）
      final recentClients = allClients.take(5).toList();
      
      if (!mounted) return;
      setState(() {
        _nearbyClients = nearbyClients;
        _recentClients = recentClients;
      });
    } catch (e) {
      debugPrint('顧客リストの読み込みに失敗しました: $e');
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedTime),
    );
    if (picked != null) {
      setState(() {
        _selectedTime = DateTime(
          _selectedTime.year,
          _selectedTime.month,
          _selectedTime.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  // 保存前の位置情報確認ダイアログ
  Future<bool> _showLocationConfirmDialog(Position? position) async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('位置情報の確認'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('以下の位置情報で記録を保存しますか？'),
              const SizedBox(height: 12),
              if (position != null) ...[
                Row(
                  children: [
                    const Icon(Icons.gps_fixed, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    const Text('位置情報:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('緯度: ${position.latitude.toStringAsFixed(6)}'),
                Text('経度: ${position.longitude.toStringAsFixed(6)}'),
              ] else ...[
                Row(
                  children: [
                    const Icon(Icons.gps_off, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    const Text('位置情報なし', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('位置情報が取得できませんでした。\nこのまま保存しますか？'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  Future<void> _saveVisitRecord() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 保存前に位置情報を再取得
    Position? saveTimePosition;
    setState(() => _isLoading = true);

    try {
      saveTimePosition = await _locationService.getCurrentLocation();
      debugPrint('保存時の位置取得成功: ${saveTimePosition?.latitude}, ${saveTimePosition?.longitude}');
    } catch (locationError) {
      debugPrint('保存時の位置取得に失敗、初期位置を使用: $locationError');
      saveTimePosition = _currentPosition;
    }

    if (mounted) {
      setState(() => _isLoading = false);
      
      // 位置情報確認ダイアログを表示
      final shouldSave = await _showLocationConfirmDialog(saveTimePosition);
      if (!shouldSave) {
        return; // ユーザーがキャンセルした場合
      }
    }

    setState(() => _isLoading = true);

    try {
      // 既に取得済みのsaveTimePositionを使用

      // 新しい訪問記録を作成（保存時の位置情報を使用）
      final newRecord = VisitRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        clientName: _clientNameController.text,
        arrivalTime: _selectedTime,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        latitude: saveTimePosition?.latitude,
        longitude: saveTimePosition?.longitude,
      );

      // 訪問記録を保存
      await _storageService.addVisitRecord(newRecord);
      
      // 顧客情報が存在しない場合、新規登録（同じ位置情報を使用）
      await _saveClientIfNeeded(saveTimePosition);

      // 保存が完了したら前の画面に戻る - 更新フラグをtrueに設定
      if (mounted) {
        final positionText = saveTimePosition != null 
            ? '位置情報付きで' 
            : '位置情報なしで';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('訪問記録を$positionText保存しました')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('訪問記録の保存に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveClientIfNeeded(Position? saveTimePosition) async {
    try {
      final clients = await _storageService.loadClients();
      final clientName = _clientNameController.text;
      
      // 同じ名前の顧客が存在するかチェック
      final existingClient = clients.any((client) => client.name == clientName);
      
      if (!existingClient) {
        // 新規顧客を登録（保存時の位置情報を使用）
        final newClient = Client(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: clientName,
          latitude: saveTimePosition?.latitude,
          longitude: saveTimePosition?.longitude,
        );
        
        await _storageService.addClient(newClient);
        debugPrint('新規顧客を登録しました: $clientName (${saveTimePosition?.latitude}, ${saveTimePosition?.longitude})');
      }
    } catch (e) {
      debugPrint('顧客情報の保存に失敗しました: $e');
    }
  }

  void _selectClient(Client client) {
    setState(() {
      _clientNameController.text = client.name;
    });
  }

  // 位置情報ステータス表示ウィジェット
  Widget _buildLocationStatusWidget() {
    IconData statusIcon;
    String statusText;
    Color statusColor;
    
    switch (_locationStatus) {
      case LocationStatus.loading:
        statusIcon = Icons.gps_not_fixed;
        statusText = '位置情報取得中...';
        statusColor = Colors.orange;
        break;
      case LocationStatus.success:
        statusIcon = Icons.gps_fixed;
        statusText = '位置情報取得済み';
        statusColor = Colors.green;
        break;
      case LocationStatus.failed:
        statusIcon = Icons.gps_off;
        statusText = '位置情報取得失敗';
        statusColor = Colors.red;
        break;
      case LocationStatus.permissionDenied:
        statusIcon = Icons.location_disabled;
        statusText = '位置情報権限が拒否されています';
        statusColor = Colors.red;
        break;
      case LocationStatus.unknown:
        statusIcon = Icons.gps_not_fixed;
        statusText = '位置情報未取得';
        statusColor = Colors.grey;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (_currentPosition != null)
                    Text(
                      '緯度: ${_currentPosition!.latitude.toStringAsFixed(6)}\n経度: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
            if (_locationStatus != LocationStatus.loading)
              TextButton.icon(
                onPressed: _getCurrentLocation,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('更新', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  minimumSize: const Size(60, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('訪問記録登録'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 位置情報ステータス表示
                    _buildLocationStatusWidget(),
                    
                    // 顧客名入力
                    TextFormField(
                      controller: _clientNameController,
                      decoration: const InputDecoration(
                        labelText: '得意先名 *',
                        hintText: '得意先名を入力',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '得意先名は必須です';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // 到着時間選択
                    InkWell(
                      onTap: () => _selectTime(context),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '到着時間 *',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(timeFormat.format(_selectedTime)),
                            const Icon(Icons.access_time),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // メモ入力
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'メモ',
                        hintText: '任意のメモを入力',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    
                    if (_nearbyClients.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text(
                        '近くの得意先:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 50,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _nearbyClients.length,
                          itemBuilder: (context, index) {
                            final client = _nearbyClients[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ElevatedButton(
                                onPressed: () => _selectClient(client),
                                child: Text(client.name),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    
                    if (_recentClients.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text(
                        '最近の得意先:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 50,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _recentClients.length,
                          itemBuilder: (context, index) {
                            final client = _recentClients[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ElevatedButton(
                                onPressed: () => _selectClient(client),
                                child: Text(client.name),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveVisitRecord,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.0),
                          child: Text(
                            '保存',
                            style: TextStyle(fontSize: 18),
                          ),
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