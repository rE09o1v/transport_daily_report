import 'package:flutter/material.dart';
import 'package:transport_daily_report/screens/visit_list_screen.dart';
import 'package:transport_daily_report/screens/visit_entry_screen.dart';
import 'package:transport_daily_report/screens/client_list_screen.dart';
import 'package:transport_daily_report/screens/history_screen.dart';
import 'package:transport_daily_report/screens/roll_call_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  
  // 各画面のホームボタンを表示/非表示にするためのフラグ
  final List<bool> _showFloatingActionButton = [false, false, false, false];
  
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
      HistoryScreen(key: _screenKeys[3]),
    ];
    
    void onItemTapped(int index) {
      setState(() {
        _selectedIndex = index;
      });
    }
    
    return Scaffold(
      body: screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: '訪問記録',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.business),
            label: '得意先',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: '点呼',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: '履歴',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
      floatingActionButton: _selectedIndex < 2 ? FloatingActionButton(
        heroTag: 'homeScreenFAB',
        onPressed: () async {
          // 新規訪問記録画面に遷移し、結果を待機
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const VisitEntryScreen()),
          );
          
          // 訪問記録が登録された場合（result=true）
          if (result == true && _selectedIndex == 0) {
            // VisitListScreen の更新メソッドを呼び出す
            final visitListState = _screenKeys[0].currentState;
            if (visitListState != null && visitListState is VisitListScreenState) {
              visitListState.refreshData();
            }
          }
        },
        child: const Icon(Icons.add),
      ) : null,
    );
  }
} 