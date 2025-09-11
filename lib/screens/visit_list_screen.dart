import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:async';
import 'package:transport_daily_report/models/visit_record.dart';
import 'package:transport_daily_report/screens/visit_detail_screen.dart';
import 'package:transport_daily_report/services/storage_service.dart';
import 'package:transport_daily_report/services/pdf_service.dart';
import 'package:transport_daily_report/services/data_notifier_service.dart';
import 'package:transport_daily_report/utils/ui_components.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/period_selector_dialog.dart';

class VisitListScreen extends StatefulWidget {
  const VisitListScreen({super.key});

  @override
  VisitListScreenState createState() => VisitListScreenState();
}

// StateクラスをpublicにしてHomeScreenからアクセスできるようにする
class VisitListScreenState extends State<VisitListScreen> with DataNotifierMixin {
  final StorageService _storageService = StorageService();
  final PdfService _pdfService = PdfService();
  
  List<VisitRecord> _visitRecords = [];
  Map<DateTime, List<VisitRecord>> _groupedRecords = {};
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _isGroupByDate = true; // 日付別グループ表示モードフラグ

  @override
  void initState() {
    super.initState();
    _loadVisitRecords();
  }

  @override
  void onDataNotification() {
    if (dataNotifier.consumeVisitRecordsChanged()) {
      if (mounted) {
        _loadVisitRecords();
      }
    }
  }
  
  @override
  void dispose() {
    super.dispose();
  }
  
  // 外部から呼び出せるようにデータを更新するメソッド
  void refreshData() {
    _loadVisitRecords();
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
        pdfFile = await _pdfService.generateDailyReport(_visitRecords, _selectedDate);
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

  // 期間指定PDF出力
  Future<void> _generatePeriodPdf() async {
    if (_groupedRecords.isEmpty && _visitRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('訪問記録がありません')),
      );
      return;
    }

    final selection = await showPeriodSelectorDialog(
      context: context,
      title: '訪問記録出力期間選択',
    );

    if (selection == null) return;

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDFを生成中...')),
      );

      File pdfFile;
      String subject;

      // データの準備
      final workingData = _groupedRecords.isNotEmpty ? _groupedRecords : _convertToGrouped(_visitRecords);

      switch (selection.type) {
        case PeriodType.daily:
          pdfFile = await _pdfService.generateDailyVisitReport(workingData, selection.startDate!);
          subject = '訪問記録 ${DateFormat('yyyy/MM/dd').format(selection.startDate!)}';
          break;
        case PeriodType.monthly:
          pdfFile = await _pdfService.generateMonthlyVisitReport(workingData, selection.startDate!);
          subject = '訪問記録 ${DateFormat('yyyy年MM月').format(selection.startDate!)}';
          break;
        case PeriodType.range:
          pdfFile = await _pdfService.generatePeriodVisitReport(workingData, selection.startDate!, selection.endDate!);
          subject = '訪問記録 ${selection.displayText}';
          break;
      }

      // ファイルが存在するか確認
      if (!await pdfFile.exists()) {
        throw Exception('PDFファイルが正常に生成されませんでした');
      }

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
        await Share.shareXFiles([XFile(pdfFile.path)], subject: subject);
      }
    } catch (e) {
      final errorMessage = 'PDFの生成・共有に失敗しました: $e';
      print(errorMessage);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  // 単一リストを日付別グループ化に変換するヘルパーメソッド
  Map<DateTime, List<VisitRecord>> _convertToGrouped(List<VisitRecord> records) {
    final Map<DateTime, List<VisitRecord>> grouped = {};
    
    for (final record in records) {
      final date = DateTime(record.arrivalTime.year, record.arrivalTime.month, record.arrivalTime.day);
      
      if (!grouped.containsKey(date)) {
        grouped[date] = [];
      }
      
      grouped[date]!.add(record);
    }
    
    return grouped;
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
                    return ActionListCard(
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
        
        return Column(
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
                  return ActionListCard(
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
      PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'all':
              _generateAndSharePdf();
              break;
            case 'period':
              _generatePeriodPdf();
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'all',
            child: Row(
              children: [
                Icon(Icons.picture_as_pdf, size: 20),
                SizedBox(width: 8),
                Text('全記録出力'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'period',
            child: Row(
              children: [
                Icon(Icons.date_range, size: 20),
                SizedBox(width: 8),
                Text('期間指定出力'),
              ],
            ),
          ),
        ],
        child: const Icon(Icons.picture_as_pdf),
      ),
    ];
  }


} 