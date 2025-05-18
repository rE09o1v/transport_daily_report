import 'package:flutter/material.dart';
import 'package:transport_daily_report/models/client.dart';
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

  void _selectClient(Client client) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VisitEntryScreen(selectedClient: client),
      ),
    ).then((value) {
      if (value == true) {
        Navigator.pop(context); // 訪問記録が作成されたら、この画面も閉じる
      }
    });
  }

  void _showAddClientDialog() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final phoneController = TextEditingController();

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

              final newClient = Client(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: name,
                address: addressController.text.isEmpty ? null : addressController.text,
                phoneNumber: phoneController.text.isEmpty ? null : phoneController.text,
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
                              subtitle: client.address != null
                                  ? Text(client.address!)
                                  : null,
                              trailing: IconButton(
                                icon: const Icon(Icons.add_circle),
                                onPressed: () => _selectClient(client),
                                tooltip: 'この得意先で訪問記録を登録',
                              ),
                              onTap: () => _selectClient(client),
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