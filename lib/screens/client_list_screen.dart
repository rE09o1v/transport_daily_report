import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:transport_daily_report/models/client.dart';
import 'package:transport_daily_report/screens/client_detail_screen.dart';
import 'package:transport_daily_report/screens/location_map_picker_screen.dart';
import 'package:transport_daily_report/screens/visit_entry_screen.dart';
import 'package:transport_daily_report/services/storage_service.dart';

class ClientListScreen extends StatefulWidget {
  const ClientListScreen({super.key});

  @override
  _ClientListScreenState createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> {
  final StorageService _storageService = StorageService();
  List<Client> _clients = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final clients = await _storageService.loadClients();
      setState(() {
        _clients = clients;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('顧客リストの読み込みに失敗しました: $e')),
      );
    }
  }

  List<Client> _getFilteredClients() {
    if (_searchQuery.isEmpty) {
      return _clients;
    }

    final query = _searchQuery.toLowerCase();
    return _clients.where((client) {
      return client.name.toLowerCase().contains(query) ||
          (client.address?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  void _viewClientDetail(Client client) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClientDetailScreen(client: client),
      ),
    ).then((_) {
      // 詳細画面から戻ってきたらリスト更新
      _loadClients();
    });
  }

  void _createVisitRecord(Client client) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VisitEntryScreen(selectedClient: client),
      ),
    ).then((value) {
      if (value == true) {
        Navigator.pop(context);
      }
    });
  }

  void _showAddClientDialog() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final phoneController = TextEditingController();
    final latitudeController = TextEditingController();
    final longitudeController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('得意先情報登録'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '得意先名 *',
                  hintText: '得意先名を入力',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: '住所',
                  hintText: '住所を入力',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: '電話番号',
                  hintText: '電話番号を入力',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              const Text(
                '位置情報（任意）',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Form(
                key: formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: latitudeController,
                      decoration: const InputDecoration(
                        labelText: '緯度',
                        hintText: '例: 35.681236',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          final lat = double.tryParse(value);
                          if (lat == null) {
                            return '有効な数値を入力してください';
                          }
                          if (lat < -90 || lat > 90) {
                            return '緯度は-90から90の範囲で入力してください';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: longitudeController,
                      decoration: const InputDecoration(
                        labelText: '経度',
                        hintText: '例: 139.767125',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          final lng = double.tryParse(value);
                          if (lng == null) {
                            return '有効な数値を入力してください';
                          }
                          if (lng < -180 || lng > 180) {
                            return '経度は-180から180の範囲で入力してください';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final selectedPosition = await Navigator.of(context).push<LatLng>(
                            MaterialPageRoute(
                              builder: (context) => const LocationMapPickerScreen(),
                            ),
                          );
                          if (selectedPosition != null) {
                            latitudeController.text = selectedPosition.latitude.toStringAsFixed(6);
                            longitudeController.text = selectedPosition.longitude.toStringAsFixed(6);
                          }
                        },
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
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('得意先名は必須です')),
                );
                return;
              }

              // 座標のバリデーション
              if (!formKey.currentState!.validate()) {
                return;
              }

              // 座標の解析
              double? latitude;
              double? longitude;
              if (latitudeController.text.isNotEmpty) {
                latitude = double.tryParse(latitudeController.text);
              }
              if (longitudeController.text.isNotEmpty) {
                longitude = double.tryParse(longitudeController.text);
              }

              final newClient = Client(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: name,
                address: addressController.text.isEmpty ? null : addressController.text,
                phoneNumber: phoneController.text.isEmpty ? null : phoneController.text,
                latitude: latitude,
                longitude: longitude,
              );

              await _storageService.addClient(newClient);
              Navigator.pop(context);
              _loadClients();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredClients = _getFilteredClients();

    return Scaffold(
      appBar: AppBar(
        title: const Text('得意先一覧'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddClientDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadClients,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: '検索',
                hintText: '得意先名または住所を入力',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredClients.isEmpty
                    ? const Center(child: Text('登録されている得意先はありません'))
                    : ListView.builder(
                        itemCount: filteredClients.length,
                        itemBuilder: (context, index) {
                          final client = filteredClients[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: ListTile(
                              title: Text(client.name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (client.address != null)
                                    Text(client.address!),
                                  if (client.latitude != null && client.longitude != null)
                                    Text(
                                      '📍 ${client.latitude!.toStringAsFixed(6)}, ${client.longitude!.toStringAsFixed(6)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.add_circle),
                                onPressed: () => _createVisitRecord(client),
                                tooltip: 'この得意先で訪問記録を登録',
                              ),
                              onTap: () => _viewClientDetail(client),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
} 