import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:transport_daily_report/models/client.dart';
import 'package:transport_daily_report/screens/client_detail_screen.dart';
import 'package:transport_daily_report/screens/location_map_picker_screen.dart';
import 'package:transport_daily_report/screens/visit_entry_screen.dart';
import 'package:transport_daily_report/services/storage_service.dart';
import 'package:transport_daily_report/utils/ui_components.dart';
import 'package:transport_daily_report/services/data_notifier_service.dart';

class ClientListScreen extends StatefulWidget {
  const ClientListScreen({super.key});

  @override
  _ClientListScreenState createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> with DataNotifierMixin {
  final StorageService _storageService = StorageService();
  List<Client> _clients = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void onDataNotification() {
    if (dataNotifier.consumeClientsChanged()) {
      if (mounted) {
        _loadClients();
      }
    }
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
      // 詳細画面から戻ってきたらリスト更新（念のため）
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
              // addClient内で自動通知されるため、手動でのリロードは不要
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
            tooltip: '新規得意先登録',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadClients,
            tooltip: 'リスト更新',
          ),
        ],
      ),
      body: Column(
        children: [
          // 検索バー
          Container(
            padding: const EdgeInsets.all(16),
            child: ModernTextField(
              label: '得意先を検索',
              hint: '得意先名または住所を入力してください',
              prefixIcon: Icons.search,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          
          // 検索結果サマリー
          if (_searchQuery.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '検索結果: ${filteredClients.length}件',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          
          // 得意先リスト
          Expanded(
            child: _isLoading
                ? const ModernLoadingIndicator(message: '得意先リストを読み込み中...')
                : filteredClients.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: filteredClients.length,
                        itemBuilder: (context, index) {
                          final client = filteredClients[index];
                          return ActionListCard(
                            title: client.name,
                            subtitle: _buildClientSubtitle(client),
                            leading: _buildClientAvatar(client),
                            actions: [
                              IconButton(
                                icon: const Icon(Icons.add_location),
                                tooltip: '訪問記録作成',
                                onPressed: () => _createVisitRecord(client),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'detail') {
                                    _viewClientDetail(client);
                                  } else if (value == 'visit') {
                                    _createVisitRecord(client);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'detail',
                                    child: Row(
                                      children: [
                                        Icon(Icons.info_outline),
                                        SizedBox(width: 8),
                                        Text('詳細を見る'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'visit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.add_location),
                                        SizedBox(width: 8),
                                        Text('訪問記録作成'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            onTap: () => _viewClientDetail(client),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  /// 空の状態表示
  Widget _buildEmptyState() {
    if (_searchQuery.isNotEmpty) {
      return EmptyStateWidget(
        icon: Icons.search_off,
        title: '検索結果がありません',
        subtitle: '「$_searchQuery」に一致する得意先が見つかりません',
        action: SecondaryActionButton(
          text: '検索をクリア',
          onPressed: () {
            setState(() {
              _searchQuery = '';
            });
          },
        ),
      );
    } else {
      return EmptyStateWidget(
        icon: Icons.business_center,
        title: '得意先が登録されていません',
        subtitle: '最初の得意先を登録してください',
        action: PrimaryActionButton(
          text: '新規登録',
          icon: Icons.add,
          onPressed: _showAddClientDialog,
        ),
      );
    }
  }

  /// 得意先のサブタイトル文字列を構築
  String _buildClientSubtitle(Client client) {
    final parts = <String>[];
    
    if (client.address != null) {
      parts.add(client.address!);
    }
    
    if (client.phoneNumber != null) {
      parts.add('📞 ${client.phoneNumber!}');
    }
    
    if (client.latitude != null && client.longitude != null) {
      parts.add('📍 座標情報あり');
    }
    
    return parts.isNotEmpty ? parts.join('\n') : '詳細情報なし';
  }

  /// 得意先のアバターを構築
  Widget _buildClientAvatar(Client client) {
    final hasLocation = client.latitude != null && client.longitude != null;
    
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: hasLocation 
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        hasLocation ? Icons.location_on : Icons.business,
        color: hasLocation 
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}