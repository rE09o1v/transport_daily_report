import 'package:flutter/material.dart';
import 'package:transport_daily_report/screens/visit_list_screen.dart';
import 'package:transport_daily_report/screens/visit_entry_screen.dart';
import 'package:transport_daily_report/screens/client_list_screen.dart';
import 'package:transport_daily_report/screens/history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  
  // 各画面のホームボタンを表示/非表示にするためのフラグ
  final List<bool> _showFloatingActionButton = [false, false, false];
  
  @override
  Widget build(BuildContext context) {
    // タブに応じて表示する画面
    final List<Widget> screens = [
      const VisitListScreen(),
      const ClientListScreen(),
      const HistoryScreen(),
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
            icon: Icon(Icons.history),
            label: '履歴',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: onItemTapped,
      ),
      floatingActionButton: _selectedIndex < 2 ? FloatingActionButton(
        heroTag: 'homeScreenFAB',
        onPressed: () {
          // 新規訪問記録画面に遷移
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const VisitEntryScreen()),
          );
        },
        child: const Icon(Icons.add),
      ) : null,
    );
  }
} 