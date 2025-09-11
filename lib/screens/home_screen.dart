import 'package:flutter/material.dart';
import 'package:transport_daily_report/screens/visit_list_screen.dart';
import 'package:transport_daily_report/screens/visit_entry_screen.dart';
import 'package:transport_daily_report/screens/client_list_screen.dart';
import 'package:transport_daily_report/screens/roll_call_list_screen.dart';
import 'package:transport_daily_report/screens/roll_call_screen.dart';
import 'package:transport_daily_report/screens/backup_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  
  // 各画面の参照を保持
  final List<GlobalKey<State>> _screenKeys = [
    GlobalKey<VisitListScreenState>(),
    GlobalKey<State>(),
    GlobalKey<State>(),
    GlobalKey<State>(),
  ];
  
  @override
  Widget build(BuildContext context) {
    // タブに応じて表示する画面
    final List<Widget> screens = [
      VisitListScreen(key: _screenKeys[0]),
      ClientListScreen(key: _screenKeys[1]),
      RollCallListScreen(key: _screenKeys[2]),
      BackupSettingsScreen(key: _screenKeys[3]),
    ];
    
    void onItemTapped(int index) {
      setState(() {
        _selectedIndex = index;
      });
    }
    
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: onItemTapped,
        elevation: 8,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: '訪問記録',
          ),
          NavigationDestination(
            icon: Icon(Icons.business_outlined),
            selectedIcon: Icon(Icons.business),
            label: '得意先',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: '点呼',
          ),
          NavigationDestination(
            icon: Icon(Icons.backup_outlined),
            selectedIcon: Icon(Icons.backup),
            label: 'バックアップ',
          ),
        ],
      ),
      // FloatingActionButtonはタブに応じて表示を切り替え
      floatingActionButton: _selectedIndex == 0 
        ? FloatingActionButton.extended(
            heroTag: null,
            onPressed: () async {
              // 新規訪問記録画面に遷移し、結果を待機
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const VisitEntryScreen()),
              );
              
              // データは自動更新されるため追加処理不要
            },
            icon: const Icon(Icons.add),
            label: const Text('新規記録'),
          )
        : _selectedIndex == 2 
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () async {
                // 点呼記録画面に遷移
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RollCallScreen()),
                );
                
                // データは自動更新されるため追加処理不要
              },
              icon: const Icon(Icons.mic),
              label: const Text('点呼記録'),
            )
          : null,
    );
  }
}