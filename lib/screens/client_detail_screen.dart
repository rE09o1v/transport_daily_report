import 'package:flutter/material.dart';
import 'package:transport_daily_report/models/client.dart';
import 'package:transport_daily_report/services/storage_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ClientDetailScreen extends StatefulWidget {
  final Client client;

  const ClientDetailScreen({Key? key, required this.client}) : super(key: key);

  @override
  _ClientDetailScreenState createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  late Client _client;
  final StorageService _storageService = StorageService();

  @override
  void initState() {
    super.initState();
    _client = widget.client;
  }

  // Google Mapで住所を検索
  Future<void> _openMap(String address) async {
    final encodedAddress = Uri.encodeComponent(address);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedAddress');
    
    try {
      await launchUrl(
        uri, 
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('マップを開けませんでした: $e')),
        );
      }
    }
  }

  // 電話をかける
  Future<void> _makePhoneCall(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    
    try {
      await launchUrl(uri);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('電話をかけられませんでした: $e')),
        );
      }
    }
  }

  // 得意先情報を編集するダイアログを表示
  void _showEditClientDialog() {
    final nameController = TextEditingController(text: _client.name);
    final addressController = TextEditingController(text: _client.address ?? '');
    final phoneController = TextEditingController(text: _client.phoneNumber ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('得意先情報編集'),
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

              final updatedClient = Client(
                id: _client.id,
                name: name,
                address: addressController.text.isEmpty ? null : addressController.text,
                phoneNumber: phoneController.text.isEmpty ? null : phoneController.text,
                latitude: _client.latitude,
                longitude: _client.longitude,
              );

              await _updateClient(updatedClient);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // 得意先情報を更新
  Future<void> _updateClient(Client updatedClient) async {
    try {
      // 得意先リストを取得
      final clients = await _storageService.loadClients();
      
      // 更新対象の得意先を検索して更新
      final index = clients.indexWhere((c) => c.id == updatedClient.id);
      if (index != -1) {
        clients[index] = updatedClient;
        
        // 更新した得意先リストを保存
        await _storageService.saveClients(clients);
        
        // 画面の表示を更新
        setState(() {
          _client = updatedClient;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('得意先情報を更新しました')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('得意先情報の更新に失敗しました: $e')),
      );
    }
  }

  // 得意先の削除確認ダイアログを表示
  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('得意先を削除'),
        content: Text('${_client.name}を削除してもよろしいですか？この操作は元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _deleteClient();
            },
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }

  // 得意先の削除
  Future<void> _deleteClient() async {
    try {
      await _storageService.deleteClient(_client.id);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('得意先を削除しました')),
      );
      
      // 得意先一覧画面に戻る（更新フラグをtrueに設定）
      Navigator.of(context).pop(true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('得意先の削除に失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('得意先詳細'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _showEditClientDialog,
            tooltip: '編集',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _showDeleteConfirmation,
            tooltip: '削除',
            color: Colors.red,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 得意先名
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '得意先名',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _client.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 住所
            if (_client.address != null && _client.address!.isNotEmpty)
              Card(
                child: InkWell(
                  onTap: () => _openMap(_client.address!),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on, color: Colors.red),
                            const SizedBox(width: 8),
                            const Text(
                              '住所',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.map,
                              color: Colors.blue,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'マップで開く',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _client.address!,
                          style: const TextStyle(
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            
            const SizedBox(height: 16),
            
            // 電話番号
            if (_client.phoneNumber != null && _client.phoneNumber!.isNotEmpty)
              Card(
                child: InkWell(
                  onTap: () => _makePhoneCall(_client.phoneNumber!),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.phone, color: Colors.green),
                            const SizedBox(width: 8),
                            const Text(
                              '電話番号',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.call,
                              color: Colors.green,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              '電話をかける',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _client.phoneNumber!,
                          style: const TextStyle(
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            
            const SizedBox(height: 16),
            
            // 位置情報
            if (_client.latitude != null && _client.longitude != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.gps_fixed, color: Colors.blue),
                          const SizedBox(width: 8),
                          const Text(
                            '位置情報',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '緯度: ${_client.latitude!.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '経度: ${_client.longitude!.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
              
            const SizedBox(height: 32),
              
            // 削除ボタン
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showDeleteConfirmation,
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('得意先を削除', style: TextStyle(color: Colors.red)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 