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

      // 最近の顧客（訪問記録を基に最大5件）
      final recentClients = await _getRecentlyVisitedClients(allClients);

      if (!mounted) return;
      setState(() {
        _nearbyClients = nearbyClients;
        _recentClients = recentClients;
      });
    } catch (e) {
      debugPrint('顧客リストの読み込みに失敗しました: $e');
    }
  }

  /// 最近訪問した得意先を取得（訪問記録を基に新しい順）
  Future<List<Client>> _getRecentlyVisitedClients(List<Client> allClients) async {
    try {
      // 過去30日間の訪問記録を取得
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final visitRecords = await _storageService.getVisitRecordsByDateRange(thirtyDaysAgo, now);

      // 訪問記録を新しい順にソート
      visitRecords.sort((a, b) => b.arrivalTime.compareTo(a.arrivalTime));

      // 訪問した得意先のリストを作成（重複除去）
      final Map<String, Client> visitedClientsMap = {};

      for (final record in visitRecords) {
        if (!visitedClientsMap.containsKey(record.clientName)) {
          // 得意先名から対応するClientを見つける
          final client = allClients.firstWhere(
            (c) => c.name == record.clientName,
            orElse: () => Client(
              id: record.clientName.hashCode.toString(),
              name: record.clientName,
              phoneNumber: '',
            ),
          );
          visitedClientsMap[record.clientName] = client;
        }
      }

      // 最大5件の最近訪問した得意先を返す
      return visitedClientsMap.values.take(5).toList();
    } catch (e) {
      debugPrint('最近の訪問先の取得に失敗しました: $e');
      // エラーの場合は登録順で返す（フォールバック）
      return allClients.take(5).toList();
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

    setState(() => _isLoading = true);

    try {
      // 現在位置を取得
      Position? currentPosition;
      try {
        currentPosition = await _locationService.getCurrentLocation();
        debugPrint('保存時の位置取得成功: ${currentPosition?.latitude}, ${currentPosition?.longitude}');
      } catch (locationError) {
        debugPrint('保存時の位置取得に失敗: $locationError');
        // 位置取得に失敗してもアプリを継続
        currentPosition = null;
      }

      // 得意先を検索またはclientIdを取得
      String clientId = '';
      final clients = await _storageService.loadClients();
      final existingClient = clients.where((c) => c.name == _clientNameController.text).firstOrNull;
      
      if (existingClient != null) {
        // 既存得意先の場合：座標は更新しない
        clientId = existingClient.id;
        debugPrint('既存得意先を使用: ${_clientNameController.text}');
      } else {
        // 新規得意先を登録（現在位置の座標を保存）
        clientId = DateTime.now().millisecondsSinceEpoch.toString();
        final newClient = Client(
          id: clientId,
          name: _clientNameController.text,
          latitude: currentPosition?.latitude,
          longitude: currentPosition?.longitude,
        );
        await _storageService.addClient(newClient);
        debugPrint('新規得意先を座標付きで登録: ${_clientNameController.text} (${currentPosition?.latitude}, ${currentPosition?.longitude})');
      }

      // 新しい訪問記録を作成（座標情報なし）
      final newRecord = VisitRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        clientId: clientId,
        clientName: _clientNameController.text,
        arrivalTime: _selectedTime,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
      );

      // 訪問記録を保存
      await _storageService.addVisitRecord(newRecord);

      // 保存が完了したら前の画面に戻る
      if (mounted) {
        final positionText = currentPosition != null ? '位置情報付きで' : '';
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
                      '現在位置: ${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
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