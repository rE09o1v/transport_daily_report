import 'package:flutter/material.dart';
import 'package:transport_daily_report/models/roll_call_record.dart';
import 'package:transport_daily_report/screens/roll_call_screen.dart';
import 'package:transport_daily_report/services/storage_service.dart';
import 'package:transport_daily_report/services/pdf_service.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

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
      print('Error loading roll call records: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('点呼記録'),
        actions: [
          // PDF出力ボタン
          IconButton(
            onPressed: _isGeneratingPdf ? null : _generateAllRollCallPdf,
            icon: _isGeneratingPdf
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.picture_as_pdf),
            tooltip: 'PDF出力',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groupedRecords.isEmpty
              ? const Center(child: Text('点呼記録がありません'))
              : ListView.builder(
                  itemCount: _groupedRecords.length,
                  itemBuilder: (context, index) {
                    final date = _groupedRecords.keys.elementAt(index);
                    final records = _groupedRecords[date]!;
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                            DateFormat('yyyy年MM月dd日').format(date),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf, size: 20),
                                tooltip: 'この日の点呼記録をPDF出力',
                                onPressed: _isGeneratingPdf 
                                  ? null 
                                  : () => _generatePdfForDate(date),
                              ),
                            ],
                          ),
                        ),
                        ...records.map((record) => Dismissible(
                          key: Key(record.id),
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16.0),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (direction) async {
                            return await showDialog<bool>(
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
                          },
                          onDismissed: (direction) async {
                            await _storageService.deleteRollCallRecord(record.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('点呼記録を削除しました')),
                            );
                          },
                          child: ListTile(
                            leading: Icon(
                              record.type == 'start' ? Icons.play_arrow : Icons.stop,
                              color: record.type == 'start' ? Colors.green : Colors.red,
                            ),
                            title: Text(
                              record.type == 'start' ? '始業点呼' : '終業点呼',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              '時刻: ${DateFormat('HH:mm').format(record.datetime)}\n'
                              '点呼執行者: ${record.inspectorName}\n'
                              '点呼方法: ${record.method}${record.method == 'その他' && record.otherMethodDetail != null ? ' (${record.otherMethodDetail})' : ''}\n'
                              '酒気帯び: ${record.hasDrunkAlcohol ? '有' : '無'}${record.alcoholValue != null ? ' (検出値: ${record.alcoholValue!.toStringAsFixed(2)} mg/L)' : ''}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => RollCallScreen(type: record.type),
                                ),
                              ).then((_) => _loadRollCallRecords());
                            },
                          ),
                        )),
                        const Divider(),
                      ],
                    );
                  },
                ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'startRollCall',
            backgroundColor: Colors.green,
            onPressed: () async {
              final hasExisting = await _checkTodayRollCallExists('start');
              if (hasExisting) {
                // すでに本日の始業点呼がある場合は警告
                if (!mounted) return;
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('警告'),
                    content: const Text('本日の始業点呼はすでに記録されています。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('キャンセル'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RollCallScreen(type: 'start'),
                            ),
                          ).then((_) => _loadRollCallRecords());
                        },
                        child: const Text('編集する'),
                      ),
                    ],
                  ),
                );
              } else {
                // 新規作成
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RollCallScreen(type: 'start'),
                  ),
                ).then((_) => _loadRollCallRecords());
              }
            },
            child: const Icon(Icons.play_arrow),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'endRollCall',
            backgroundColor: Colors.red,
            onPressed: () async {
              final hasExisting = await _checkTodayRollCallExists('end');
              if (hasExisting) {
                // すでに本日の終業点呼がある場合は警告
                if (!mounted) return;
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('警告'),
                    content: const Text('本日の終業点呼はすでに記録されています。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('キャンセル'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RollCallScreen(type: 'end'),
                            ),
                          ).then((_) => _loadRollCallRecords());
                        },
                        child: const Text('編集する'),
                      ),
                    ],
                  ),
                );
              } else {
                // 新規作成
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RollCallScreen(type: 'end'),
                  ),
                ).then((_) => _loadRollCallRecords());
              }
            },
            child: const Icon(Icons.stop),
          ),
        ],
      ),
    );
  }
} 