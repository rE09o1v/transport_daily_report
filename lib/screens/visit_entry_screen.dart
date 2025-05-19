import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:transport_daily_report/models/client.dart';
import 'package:transport_daily_report/models/visit_record.dart';
import 'package:transport_daily_report/services/location_service.dart';
import 'package:transport_daily_report/services/storage_service.dart';

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
    try {
      final position = await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      print('位置情報の取得に失敗しました: $e');
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
      print('顧客リストの読み込みに失敗しました: $e');
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

  Future<void> _saveVisitRecord() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 新しい訪問記録を作成
      final newRecord = VisitRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        clientName: _clientNameController.text,
        arrivalTime: _selectedTime,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
      );

      // 訪問記録を保存
      await _storageService.addVisitRecord(newRecord);
      
      // 顧客情報が存在しない場合、新規登録
      await _saveClientIfNeeded();

      // 保存が完了したら前の画面に戻る - 更新フラグをtrueに設定
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('訪問記録を保存しました')),
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

  Future<void> _saveClientIfNeeded() async {
    try {
      final clients = await _storageService.loadClients();
      final clientName = _clientNameController.text;
      
      // 同じ名前の顧客が存在するかチェック
      final existingClient = clients.any((client) => client.name == clientName);
      
      if (!existingClient) {
        // 新規顧客を登録
        final newClient = Client(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: clientName,
          latitude: _currentPosition?.latitude,
          longitude: _currentPosition?.longitude,
        );
        
        await _storageService.addClient(newClient);
      }
    } catch (e) {
      print('顧客情報の保存に失敗しました: $e');
    }
  }

  void _selectClient(Client client) {
    setState(() {
      _clientNameController.text = client.name;
    });
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