import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:transport_daily_report/models/visit_record.dart';
import 'package:transport_daily_report/screens/visit_detail_screen.dart';
import 'package:transport_daily_report/screens/visit_entry_screen.dart';
import 'package:transport_daily_report/screens/history_screen.dart';
import 'package:transport_daily_report/services/storage_service.dart';
import 'package:transport_daily_report/services/pdf_service.dart';
import 'package:share_plus/share_plus.dart';

class VisitListScreen extends StatefulWidget {
  const VisitListScreen({super.key});

  @override
  VisitListScreenState createState() => VisitListScreenState();
}

// StateクラスをpublicにしてHomeScreenからアクセスできるようにする
class VisitListScreenState extends State<VisitListScreen> {
  final StorageService _storageService = StorageService();
  final PdfService _pdfService = PdfService();
  
  // 走行距離入力用コントローラー
  final _startMileageController = TextEditingController();
  final _endMileageController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  List<VisitRecord> _visitRecords = [];
  Map<DateTime, List<VisitRecord>> _groupedRecords = {};
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _isGroupByDate = true; // 日付別グループ表示モードフラグ
  
  String _distanceDifference = ''; // 走行距離の差分
  bool _isSavingMileage = false; // 走行距離保存中フラグ
  String? _lastUpdateDate; // 最終更新日
  
  // 折りたたみ状態
  bool _mileagePanelExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadVisitRecords();
    _loadMileageData();
    _loadPanelState();
    
    // 走行距離の変更を監視するリスナーを追加
    _startMileageController.addListener(_updateDistanceDifference);
    _endMileageController.addListener(_updateDistanceDifference);
  }
  
  @override
  void dispose() {
    _startMileageController.removeListener(_updateDistanceDifference);
    _endMileageController.removeListener(_updateDistanceDifference);
    _startMileageController.dispose();
    _endMileageController.dispose();
    super.dispose();
  }
  
  // 外部から呼び出せるようにデータを更新するメソッド
  void refreshData() {
    _loadVisitRecords();
  }
  
  // 走行距離の差分を更新
  void _updateDistanceDifference() {
    setState(() {
      if (_startMileageController.text.isNotEmpty && _endMileageController.text.isNotEmpty) {
        try {
          final startMileage = double.parse(_startMileageController.text);
          final endMileage = double.parse(_endMileageController.text);
          
          if (endMileage >= startMileage) {
            final difference = endMileage - startMileage;
            _distanceDifference = '走行距離: ${difference.toStringAsFixed(1)} km';
          } else {
            _distanceDifference = '走行距離: - km';
          }
        } catch (e) {
          _distanceDifference = '';
        }
      } else {
        _distanceDifference = '';
      }
    });
  }
  
  // 保存済みの走行距離データを読み込む
  Future<void> _loadMileageData() async {
    try {
      final mileageData = await _storageService.getMileageData();
      
      setState(() {
        _startMileageController.text = mileageData['startMileage']?.toString() ?? '';
        _endMileageController.text = mileageData['endMileage']?.toString() ?? '';
        _lastUpdateDate = mileageData['lastUpdateDate'];
      });
      
      // 値が変更されると自動的に差分が更新される
      _updateDistanceDifference();
    } catch (e) {
      print('走行距離データの読み込みに失敗しました: $e');
    }
  }
  
  // 走行距離データを保存
  Future<void> _saveMileageData() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    setState(() {
      _isSavingMileage = true;
    });
    
    try {
      final startMileage = _startMileageController.text.isNotEmpty 
          ? double.parse(_startMileageController.text) 
          : null;
      final endMileage = _endMileageController.text.isNotEmpty 
          ? double.parse(_endMileageController.text) 
          : null;
      
      await _storageService.saveMileageData(startMileage, endMileage);
      
      // 最終更新日を更新
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month}-${now.day}';
      
      setState(() {
        _lastUpdateDate = dateStr;
      });
      
      // スナックバーの代わりに、静かに保存完了とする（自動保存時には明示的な通知は不要）
    } catch (e) {
      // エラー時だけスナックバーを表示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
      );
    } finally {
      setState(() {
        _isSavingMileage = false;
      });
    }
  }
  
  // 走行距離データをリセット
  Future<void> _resetMileageData() async {
    try {
      await _storageService.resetMileageData();
      
      setState(() {
        _startMileageController.text = '';
        _endMileageController.text = '';
        _lastUpdateDate = null;
        _distanceDifference = '';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('走行距離をリセットしました')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('リセットに失敗しました: $e')),
      );
    }
  }

  Future<void> _loadVisitRecords() async {
    print('訪問記録データの読み込みを開始します');
    
    setState(() {
      _isLoading = true;
    });

    try {
      if (_isGroupByDate) {
        // 日付別グループ化モード
        print('グループ化モードで訪問記録を読み込み中...');
        final groupedRecords = await _storageService.getVisitRecordsGroupedByDate();
        final allRecords = await _storageService.loadVisitRecords();
        
        if (mounted) {
          setState(() {
            _groupedRecords = groupedRecords;
            _visitRecords = allRecords;
            _isLoading = false;
          });
          print('訪問記録の読み込みが完了しました: ${allRecords.length}件');
        }
      } else {
        // 単一日付フィルターモード
        print('単一日付フィルターモードで訪問記録を読み込み中...');
        final records = await _storageService.getVisitRecordsForDate(_selectedDate);
        
        if (mounted) {
          setState(() {
            _visitRecords = records;
            _isLoading = false;
          });
          print('訪問記録の読み込みが完了しました: ${records.length}件');
        }
      }
    } catch (e) {
      print('訪問記録の読み込み中にエラーが発生しました: $e');
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('訪問記録の読み込みに失敗しました: $e')),
        );
      }
    }
  }

  List<VisitRecord> _getFilteredRecords() {
    if (_isGroupByDate) {
      return _visitRecords;
    }
    
    return _visitRecords.where((record) {
      final recordDate = record.arrivalTime;
      return recordDate.year == _selectedDate.year &&
          recordDate.month == _selectedDate.month &&
          recordDate.day == _selectedDate.day;
    }).toList()
      ..sort((a, b) => a.arrivalTime.compareTo(b.arrivalTime));
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ja', 'JP'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _isGroupByDate = false; // 日付選択したら単一日付モードに切り替え
      });
      _loadVisitRecords();
    }
  }

  Future<void> _generateAndSharePdf() async {
    try {
      // インジケータを表示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDFを生成中...')),
      );

      File pdfFile;

      if (_isGroupByDate) {
        // 全期間のグループ化されたデータでPDFを生成
        pdfFile = await _pdfService.generateMultiDayReport(_groupedRecords);
      } else {
        // 単一日付のデータでPDFを生成
        pdfFile = await _pdfService.generateDailyReport(
          _visitRecords,
          _selectedDate,
        );
      }

      // ファイルが存在するか確認
      if (!await pdfFile.exists()) {
        throw Exception('PDFファイルが正常に生成されませんでした');
      }

      // 成功メッセージとファイルパスを表示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDFファイルを生成しました: ${pdfFile.path}'),
          duration: const Duration(seconds: 3),
        ),
      );

      // 共有するか確認
      final shouldShare = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('PDFの共有'),
          content: const Text('PDFファイルを他のアプリで共有しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('共有する'),
            ),
          ],
        ),
      ) ?? false;

      if (shouldShare) {
        // PDFを共有
        await Share.shareXFiles(
          [XFile(pdfFile.path)],
          subject: _isGroupByDate 
              ? '訪問記録レポート' 
              : '日報 ${DateFormat('yyyy/MM/dd').format(_selectedDate)}',
        );
      }
    } catch (e) {
      // エラーが発生したときの詳細なメッセージ
      final errorMessage = 'PDFの生成・共有に失敗しました: $e';
      print(errorMessage); // デバッグ用にログ出力
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  void _toggleViewMode() {
    setState(() {
      _isGroupByDate = !_isGroupByDate;
    });
    _loadVisitRecords();
  }

  void _viewRecordDetail(VisitRecord record) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VisitDetailScreen(visitRecord: record),
      ),
    ).then((result) {
      // 削除や変更があった場合は再読み込み
      if (result == true) {
        _loadVisitRecords();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy年MM月dd日(E)', 'ja_JP');
    final timeFormat = DateFormat('HH:mm');
    final filteredRecords = _getFilteredRecords();

    return Scaffold(
      appBar: AppBar(
        title: const Text('訪問記録'),
        actions: _buildAppBarActions(),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 折りたたみ可能なパネルリスト
                ExpansionPanelList(
                  elevation: 1,
                  expandedHeaderPadding: EdgeInsets.zero,
                  dividerColor: Colors.grey.shade300,
                  animationDuration: const Duration(milliseconds: 300),
                  expansionCallback: (panelIndex, isExpanded) {
                    setState(() {
                      if (panelIndex == 0) {
                        _mileagePanelExpanded = !_mileagePanelExpanded;
                      }
                      // パネル状態を保存
                      _savePanelState();
                    });
                  },
                  children: [
                    // 走行距離入力パネル（2番目に表示）
                    ExpansionPanel(
                      headerBuilder: (context, isExpanded) {
                        return ListTile(
                          title: Row(
                            children: [
                              const Icon(Icons.directions_car),
                              const SizedBox(width: 8),
                              const Text(
                                '走行距離記録',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 値が入力されていることを示すインジケータ
                              if (_startMileageController.text.isNotEmpty || _endMileageController.text.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '記録あり',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                      body: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), // 上部パディングを追加
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 走行距離入力（横並び）
                              Row(
                                children: [
                                  // 出発時走行距離
                                  Expanded(
                                    child: TextFormField(
                                      controller: _startMileageController,
                                      decoration: const InputDecoration(
                                        labelText: '出発時走行距離',
                                        hintText: '車両メーターの値',
                                        suffixText: 'km',
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16), // パディングを調整
                                      ),
                                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                                      validator: (value) {
                                        if (value != null && value.isNotEmpty) {
                                          final mileage = double.tryParse(value);
                                          if (mileage == null) {
                                            return '有効な数値を入力してください';
                                          }
                                          if (mileage < 0) {
                                            return '0以上の値を入力してください';
                                          }
                                        }
                                        return null;
                                      },
                                      onChanged: (value) {
                                        if (value.isNotEmpty && double.tryParse(value) != null) {
                                          // 入力が有効な数値の場合、遅延をもって自動保存
                                          Future.delayed(const Duration(milliseconds: 500), () {
                                            if (_formKey.currentState?.validate() ?? false) {
                                              _saveMileageData();
                                            }
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // 帰社時走行距離
                                  Expanded(
                                    child: TextFormField(
                                      controller: _endMileageController,
                                      decoration: const InputDecoration(
                                        labelText: '帰社時走行距離',
                                        hintText: '車両メーターの値',
                                        suffixText: 'km',
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16), // パディングを調整
                                      ),
                                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                                      validator: (value) {
                                        if (value != null && value.isNotEmpty) {
                                          final endMileage = double.tryParse(value);
                                          if (endMileage == null) {
                                            return '有効な数値を入力してください';
                                          }
                                          if (endMileage < 0) {
                                            return '0以上の値を入力してください';
                                          }
                                          
                                          // 出発時走行距離が入力されている場合は比較
                                          if (_startMileageController.text.isNotEmpty) {
                                            final startMileage = double.tryParse(_startMileageController.text);
                                            if (startMileage != null && endMileage < startMileage) {
                                              return '出発時より大きな値を入力してください';
                                            }
                                          }
                                        }
                                        return null;
                                      },
                                      onChanged: (value) {
                                        if (value.isNotEmpty && double.tryParse(value) != null) {
                                          // 入力が有効な数値の場合、遅延をもって自動保存
                                          Future.delayed(const Duration(milliseconds: 500), () {
                                            if (_formKey.currentState?.validate() ?? false) {
                                              _saveMileageData();
                                            }
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              // 走行距離の差分表示
                              if (_distanceDifference.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
                                  child: Text(
                                    _distanceDifference,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ),
                              // 自動保存の説明
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                                child: Text(
                                  '※ 入力すると自動で保存されます',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                              // ボタン行
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: _resetMileageData,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('リセット'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      isExpanded: _mileagePanelExpanded,
                    ),
                  ],
                ),
                
                // 訪問記録リスト
                Expanded(
                  child: _isGroupByDate
                      ? _buildGroupedView(dateFormat, timeFormat)
                      : _buildSingleDateView(filteredRecords, dateFormat, timeFormat),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          print('訪問記録登録画面を開きます');
          
          try {
            // 訪問記録登録画面を表示
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const VisitEntryScreen(),
              ),
            );
            
            print('訪問記録登録画面から戻りました: result=$result');
            
            // 新しい訪問記録が登録された場合（resultがtrue）
            if (result == true) {
              print('訪問記録が追加されたため、データを再読み込みします');
              
              // いったんローディング状態に戻して、古いデータを表示しないようにする
              if (mounted) {
                setState(() {
                  _isLoading = true;
                });
              }
              
              // 500msの遅延を設定して、確実にストレージへの書き込みが完了するのを待つ
              await Future.delayed(const Duration(milliseconds: 500));
              
              // データを最新化
              if (mounted) {
                try {
                  if (_isGroupByDate) {
                    // グループ化モードの場合、両方のデータを取得
                    final groupedRecords = await _storageService.getVisitRecordsGroupedByDate();
                    final allRecords = await _storageService.loadVisitRecords();
                    
                    if (mounted) {
                      setState(() {
                        _groupedRecords = groupedRecords;
                        _visitRecords = allRecords;
                        _isLoading = false;
                        print('グループ化モードでのUI更新完了: ${allRecords.length}件のレコード');
                      });
                    }
                  } else {
                    // 単一日付モードの場合
                    final records = await _storageService.getVisitRecordsForDate(_selectedDate);
                    
                    if (mounted) {
                      setState(() {
                        _visitRecords = records;
                        _isLoading = false;
                        print('単一日付モードでのUI更新完了: ${records.length}件のレコード');
                      });
                    }
                  }
                } catch (e) {
                  print('データ再読み込み中にエラーが発生しました: $e');
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('データの更新に失敗しました: $e')),
                    );
                  }
                }
              }
            }
          } catch (e) {
            print('訪問記録登録中にエラーが発生しました: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('エラーが発生しました: $e')),
              );
            }
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSingleDateView(List<VisitRecord> records, DateFormat dateFormat, DateFormat timeFormat) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateFormat.format(_selectedDate),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '訪問件数: ${records.length}',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
        Expanded(
          child: records.isEmpty
              ? const Center(child: Text('この日の訪問記録はありません'))
              : ListView.builder(
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(timeFormat.format(record.arrivalTime)),
                        ),
                        title: Text(record.clientName),
                        subtitle: record.notes != null && record.notes!.isNotEmpty
                            ? Text(record.notes!, maxLines: 1, overflow: TextOverflow.ellipsis)
                            : null,
                        trailing: const Icon(Icons.arrow_forward_ios),
                        onTap: () => _viewRecordDetail(record),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildGroupedView(DateFormat dateFormat, DateFormat timeFormat) {
    // 日付を新しい順に並べる
    final sortedDates = _groupedRecords.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    
    if (sortedDates.isEmpty) {
      return const Center(child: Text('訪問記録がありません'));
    }
    
    return ListView.builder(
      itemCount: sortedDates.length,
      itemBuilder: (context, dateIndex) {
        final date = sortedDates[dateIndex];
        final recordsForDate = _groupedRecords[date]!;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: 16.0, 
                right: 16.0,
                top: 16.0,
                bottom: 8.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateFormat.format(date),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${recordsForDate.length}件',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: recordsForDate.length,
              itemBuilder: (context, recordIndex) {
                final record = recordsForDate[recordIndex];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4.0,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(timeFormat.format(record.arrivalTime)),
                    ),
                    title: Text(record.clientName),
                    subtitle: record.notes != null && record.notes!.isNotEmpty
                        ? Text(record.notes!, maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () => _viewRecordDetail(record),
                  ),
                );
              },
            ),
            if (dateIndex < sortedDates.length - 1)
              const Divider(height: 32, thickness: 1),
          ],
        );
      },
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      IconButton(
        icon: const Icon(Icons.view_list),
        onPressed: () {
          setState(() {
            _isGroupByDate = !_isGroupByDate;
          });
          _loadVisitRecords();
        },
      ),
      IconButton(
        icon: const Icon(Icons.picture_as_pdf),
        onPressed: _generateAndSharePdf,
      ),
      IconButton(
        icon: const Icon(Icons.history),
        tooltip: '履歴データ',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const HistoryScreen()),
          );
        },
      ),
    ];
  }

  // パネルの状態を読み込む
  Future<void> _loadPanelState() async {
    try {
      final prefs = await _storageService.getPrefs();
      setState(() {
        _mileagePanelExpanded = prefs.getBool('mileagePanelExpanded') ?? false;
      });
    } catch (e) {
      print('パネル状態の読み込みに失敗しました: $e');
    }
  }
  
  // パネルの状態を保存
  Future<void> _savePanelState() async {
    try {
      final prefs = await _storageService.getPrefs();
      await prefs.setBool('mileagePanelExpanded', _mileagePanelExpanded);
    } catch (e) {
      print('パネル状態の保存に失敗しました: $e');
    }
  }
} 