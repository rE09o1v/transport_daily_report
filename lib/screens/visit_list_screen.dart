import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:transport_daily_report/models/visit_record.dart';
import 'package:transport_daily_report/screens/visit_detail_screen.dart';
import 'package:transport_daily_report/services/storage_service.dart';
import 'package:transport_daily_report/services/pdf_service.dart';
import 'package:transport_daily_report/utils/ui_components.dart';
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
          ? const ModernLoadingIndicator(message: '訪問記録を読み込み中...')
          : Column(
              children: [
                // 走行距離記録カード
                _buildMileageCard(),
                
                // 訪問記録リスト
                Expanded(
                  child: _isGroupByDate
                      ? _buildGroupedView(dateFormat, timeFormat)
                      : _buildSingleDateView(filteredRecords, dateFormat, timeFormat),
                ),
              ],
            ),
    );
  }

  Widget _buildSingleDateView(List<VisitRecord> records, DateFormat dateFormat, DateFormat timeFormat) {
    return Column(
      children: [
        // 日付ヘッダーカード
        ModernInfoCard(
          title: dateFormat.format(_selectedDate),
          subtitle: '訪問件数: ${records.length}件',
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.event,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        
        // 訪問記録リスト
        Expanded(
          child: records.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.event_busy,
                  title: 'この日の訪問記録はありません',
                  subtitle: '新しい訪問記録を追加してください',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return AnimatedListItem(
                      index: index,
                      child: ActionListCard(
                        title: record.clientName,
                        subtitle: record.notes?.isNotEmpty == true 
                            ? record.notes! 
                            : '到着: ${timeFormat.format(record.arrivalTime)}',
                        leading: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                timeFormat.format(record.arrivalTime).split(':')[0],
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                timeFormat.format(record.arrivalTime).split(':')[1],
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.location_on),
                            onPressed: () {
                              // 位置情報を表示する機能
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '位置情報機能は今後実装予定です'
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
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
    final sortedDates = _groupedRecords.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    
    if (sortedDates.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.event_busy,
        title: '訪問記録がありません',
        subtitle: '新しい訪問記録を追加してください',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: sortedDates.length,
      itemBuilder: (context, dateIndex) {
        final date = sortedDates[dateIndex];
        final recordsForDate = _groupedRecords[date]!;
        
        return AnimatedListItem(
          index: dateIndex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 日付ヘッダーカード
              ModernInfoCard(
                title: dateFormat.format(date),
                subtitle: '${recordsForDate.length}件の訪問記録',
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.calendar_today,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
              
              // 訪問記録リスト
              ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: recordsForDate.length,
                itemBuilder: (context, recordIndex) {
                  final record = recordsForDate[recordIndex];
                  return AnimatedListItem(
                    index: recordIndex,
                    delay: const Duration(milliseconds: 50),
                    child: ActionListCard(
                      title: record.clientName,
                      subtitle: record.notes?.isNotEmpty == true 
                          ? record.notes! 
                          : '到着: ${timeFormat.format(record.arrivalTime)}',
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              timeFormat.format(record.arrivalTime).split(':')[0],
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              timeFormat.format(record.arrivalTime).split(':')[1],
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                      onTap: () => _viewRecordDetail(record),
                    ),
                  );
                },
              ),
            if (dateIndex < sortedDates.length - 1)
              const Divider(height: 32, thickness: 1),
            ],
          ),
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

  /// 走行距離記録用の現代的なカード
  Widget _buildMileageCard() {
    final hasData = _startMileageController.text.isNotEmpty || _endMileageController.text.isNotEmpty;
    
    return Column(
      children: [
        // ヘッダーカード
        ModernInfoCard(
          title: '走行距離記録',
          subtitle: hasData ? '記録済み • ${_distanceDifference.isNotEmpty ? _distanceDifference : '計算中...'}' : '未入力',
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: hasData 
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.directions_car,
              color: hasData 
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: IconButton(
            icon: Icon(_mileagePanelExpanded ? Icons.expand_less : Icons.expand_more),
            onPressed: () {
              setState(() {
                _mileagePanelExpanded = !_mileagePanelExpanded;
                _savePanelState();
              });
            },
          ),
          onTap: () {
            setState(() {
              _mileagePanelExpanded = !_mileagePanelExpanded;
              _savePanelState();
            });
          },
        ),
        
        // 拡張可能な入力フォーム
        if (_mileagePanelExpanded)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 出発時走行距離
                    ModernTextField(
                      label: '出発時走行距離',
                      hint: '車両メーターの値',
                      controller: _startMileageController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      suffixIcon: const Text('km'),
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
                          Future.delayed(const Duration(milliseconds: 500), () {
                            if (_formKey.currentState?.validate() ?? false) {
                              _saveMileageData();
                            }
                          });
                        }
                      },
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // 帰社時走行距離
                    ModernTextField(
                      label: '帰社時走行距離',
                      hint: '車両メーターの値',
                      controller: _endMileageController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      suffixIcon: const Text('km'),
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
                          Future.delayed(const Duration(milliseconds: 500), () {
                            if (_formKey.currentState?.validate() ?? false) {
                              _saveMileageData();
                            }
                          });
                        }
                      },
                    ),
                    
                    // 走行距離の差分表示
                    if (_distanceDifference.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calculate,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _distanceDifference,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    // 説明文とアクション
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '入力すると自動で保存されます',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        SecondaryActionButton(
                          text: 'リセット',
                          icon: Icons.refresh,
                          onPressed: _resetMileageData,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
} 