import 'package:flutter/material.dart';
import 'dart:io';
import 'package:transport_daily_report/models/roll_call_record.dart';
import 'package:transport_daily_report/screens/roll_call_screen.dart';
import 'package:transport_daily_report/services/storage_service.dart';
import 'package:transport_daily_report/services/pdf_service.dart';
import 'package:transport_daily_report/utils/ui_components.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/period_selector_dialog.dart';
import '../utils/logger.dart';

class RollCallListScreen extends StatefulWidget {
  const RollCallListScreen({super.key});

  @override
  _RollCallListScreenState createState() => _RollCallListScreenState();
}

class _RollCallListScreenState extends State<RollCallListScreen> {
  final _storageService = StorageService();
  final _pdfService = PdfService();
  Map<DateTime, List<RollCallRecord>> _groupedRecords = {};
  bool _isLoading = true;
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    _loadRollCallRecords();
  }

  // 点呼記録を読み込み、日付でグループ化
  Future<void> _loadRollCallRecords() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final allRecords = await _storageService.loadRollCallRecords();
      
      // 日付でグループ化
      final Map<DateTime, List<RollCallRecord>> grouped = {};
      
      for (final record in allRecords) {
        final date = DateTime(
          record.datetime.year,
          record.datetime.month,
          record.datetime.day,
        );
        
        if (!grouped.containsKey(date)) {
          grouped[date] = [];
        }
        
        grouped[date]!.add(record);
      }
      
      // 各日付内で開始時間順にソート
      grouped.forEach((date, records) {
        records.sort((a, b) => a.datetime.compareTo(b.datetime));
      });
      
      // 日付順（降順）にソート
      final sortedDates = grouped.keys.toList()
        ..sort((a, b) => b.compareTo(a));
      
      final sortedGrouped = <DateTime, List<RollCallRecord>>{};
      for (final date in sortedDates) {
        sortedGrouped[date] = grouped[date]!;
      }
      
      if (!mounted) return;
      setState(() {
        _groupedRecords = sortedGrouped;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('点呼記録の読み込み中にエラーが発生しました', 'RollCallListScreen', e);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 今日の日付に始業点呼または終業点呼がすでに存在するかチェック
  Future<bool> _checkTodayRollCallExists(String type) async {
    final now = DateTime.now();
    final record = await _storageService.getRollCallRecordByDateAndType(now, type);
    return record != null;
  }

  // 点呼記録を削除
  Future<void> _deleteRollCallRecord(RollCallRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認'),
        content: Text('この点呼記録を削除しますか？\n\n日時: ${DateFormat('yyyy/MM/dd HH:mm').format(record.datetime)}\n種類: ${record.type == 'start' ? '始業点呼' : '終業点呼'}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _storageService.deleteRollCallRecord(record.id);
      await _loadRollCallRecords();
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('点呼記録を削除しました')),
      );
    }
  }

  // 選択した日付の点呼記録をPDFに出力
  Future<void> _generatePdfForDate(DateTime date) async {
    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      final records = await _storageService.getRollCallRecordsForDate(date);
      if (records.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('この日の点呼記録はありません')),
        );
        setState(() {
          _isGeneratingPdf = false;
        });
        return;
      }

      // 点呼シート形式でPDFを生成
      final pdfFile = await _pdfService.generateCombinedRollCallReport({date: records});
      
      if (!mounted) return;
      setState(() {
        _isGeneratingPdf = false;
      });
      
      // PDFファイルを共有する
      await Share.shareXFiles(
        [XFile(pdfFile.path)],
        subject: '点呼記録シート ${DateFormat('yyyy-MM-dd').format(date)}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGeneratingPdf = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDFの生成に失敗しました: $e')),
      );
    }
  }

  // すべての点呼記録をPDFに出力
  Future<void> _generateAllRollCallPdf() async {
    if (_groupedRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('点呼記録がありません')),
      );
      return;
    }

    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      final pdfFile = await _pdfService.generateCombinedRollCallReport(_groupedRecords);
      
      if (!mounted) return;
      setState(() {
        _isGeneratingPdf = false;
      });
      
      // PDFファイルを共有する
      await Share.shareXFiles(
        [XFile(pdfFile.path)],
        subject: '点呼記録シート',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGeneratingPdf = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDFの生成に失敗しました: $e')),
      );
    }
  }

  // 期間指定PDF出力
  Future<void> _generatePeriodPdf() async {
    if (_groupedRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('点呼記録がありません')),
      );
      return;
    }

    final selection = await showPeriodSelectorDialog(
      context: context,
      title: '点呼記録出力期間選択',
    );

    if (selection == null) return;

    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      File pdfFile;
      String subject;

      switch (selection.type) {
        case PeriodType.daily:
          pdfFile = await _pdfService.generateDailyRollCallReport(
            _groupedRecords,
            selection.startDate!,
          );
          subject = '点呼記録 ${DateFormat('yyyy/MM/dd').format(selection.startDate!)}';
          break;
        case PeriodType.monthly:
          pdfFile = await _pdfService.generateMonthlyRollCallReport(
            _groupedRecords,
            selection.startDate!,
          );
          subject = '点呼記録 ${DateFormat('yyyy年MM月').format(selection.startDate!)}';
          break;
        case PeriodType.range:
          pdfFile = await _pdfService.generatePeriodRollCallReport(
            _groupedRecords,
            selection.startDate!,
            selection.endDate!,
          );
          subject = '点呼記録 ${selection.displayText}';
          break;
      }

      if (!mounted) return;
      setState(() {
        _isGeneratingPdf = false;
      });

      // PDFファイルを共有する
      await Share.shareXFiles(
        [XFile(pdfFile.path)],
        subject: subject,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGeneratingPdf = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDFの生成に失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('点呼記録'),
        actions: [
          PopupMenuButton<String>(
            enabled: !_isGeneratingPdf,
            onSelected: (value) {
              switch (value) {
                case 'all':
                  _generateAllRollCallPdf();
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
            child: _isGeneratingPdf
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.picture_as_pdf),
          ),
        ],
      ),
      body: _isLoading
          ? const ModernLoadingIndicator(message: '点呼記録を読み込み中...')
          : _groupedRecords.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.assignment_outlined,
                  title: '点呼記録がありません',
                  subtitle: '新しい点呼記録を登録してください',
                  action: PrimaryActionButton(
                    text: '点呼記録作成',
                    icon: Icons.add,
                    onPressed: () => _navigateToRollCallScreen(),
                  ),
                )
              : _buildRecordList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToRollCallScreen(),
        icon: const Icon(Icons.add),
        label: const Text('新規記録'),
      ),
    );
  }

  /// 点呼記録画面への遷移
  void _navigateToRollCallScreen() async {
    // 今日の始業・終業点呼の存在チェック
    final hasStartRollCall = await _checkTodayRollCallExists('start');
    final hasEndRollCall = await _checkTodayRollCallExists('end');

    if (!mounted) return;

    // 点呼種別選択ダイアログを表示
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('点呼種別選択'),
        content: const Text('作成する点呼記録の種別を選択してください'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          ElevatedButton.icon(
            onPressed: hasStartRollCall ? null : () {
              Navigator.of(context).pop();
              _navigateToRollCall('start');
            },
            icon: const Icon(Icons.play_arrow),
            label: Text(hasStartRollCall ? '始業点呼（済）' : '始業点呼'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: hasEndRollCall ? null : () {
              Navigator.of(context).pop();
              _navigateToRollCall('end');
            },
            icon: const Icon(Icons.stop),
            label: Text(hasEndRollCall ? '終業点呼（済）' : '終業点呼'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// 特定の点呼種別での画面遷移
  void _navigateToRollCall(String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RollCallScreen(type: type),
      ),
    ).then((_) => _loadRollCallRecords());
  }

  /// 点呼記録リストの構築
  Widget _buildRecordList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _groupedRecords.length,
      itemBuilder: (context, index) {
        final date = _groupedRecords.keys.elementAt(index);
        final records = _groupedRecords[date]!;
        
        return AnimatedListItem(
          index: index,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 日付ヘッダーカード
              ModernInfoCard(
                title: DateFormat('yyyy年MM月dd日(E)', 'ja_JP').format(date),
                subtitle: '${records.length}件の点呼記録',
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.assignment,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.picture_as_pdf),
                  tooltip: 'この日のPDF出力',
                  onPressed: _isGeneratingPdf 
                      ? null 
                      : () => _generatePdfForDate(date),
                ),
              ),
              
              // 点呼記録リスト
              ...records.map((record) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: ActionListCard(
                  title: record.type == 'start' ? '始業点呼' : '終業点呼',
                  subtitle: _buildRollCallSubtitle(record),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: record.type == 'start' 
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: record.type == 'start' ? Colors.green : Colors.red,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      record.type == 'start' ? Icons.play_arrow : Icons.stop,
                      color: record.type == 'start' ? Colors.green : Colors.red,
                      size: 24,
                    ),
                  ),
                  dismissible: true,
                  onDismissed: () => _deleteRollCallRecord(record),
                  onTap: () => _navigateToRollCall(record.type),
                ),
              )),
              
              if (index < _groupedRecords.length - 1)
                const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  /// 点呼記録のサブタイトル構築
  String _buildRollCallSubtitle(RollCallRecord record) {
    final parts = <String>[
      '時刻: ${DateFormat('HH:mm').format(record.datetime)}',
      '点呼執行者: ${record.inspectorName}',
      '点呼方法: ${record.method}${record.method == 'その他' && record.otherMethodDetail != null ? ' (${record.otherMethodDetail})' : ''}',
      '酒気帯び: ${record.hasDrunkAlcohol ? '有' : '無'}${record.alcoholValue != null ? ' (${record.alcoholValue!.toStringAsFixed(2)} mg/L)' : ''}',
    ];
    
    return parts.join('\n');
  }
} 