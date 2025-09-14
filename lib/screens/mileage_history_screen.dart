import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/mileage_record.dart';
import '../services/mileage_service.dart';
import '../utils/logger.dart';

/// メーター値履歴画面
/// 
/// 過去のメーター値と走行距離を表示する画面
/// カレンダー形式での表示、日別詳細表示、月間集計表示、グラフ表示、異常値検索機能を提供
class MileageHistoryScreen extends StatefulWidget {
  const MileageHistoryScreen({super.key});

  @override
  State<MileageHistoryScreen> createState() => _MileageHistoryScreenState();
}

class _MileageHistoryScreenState extends State<MileageHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MileageService _mileageService = MileageService();
  
  // カレンダー関連
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  
  // データ関連
  List<MileageRecord> _mileageRecords = [];
  Map<DateTime, List<MileageRecord>> _groupedRecords = {};
  bool _isLoading = false;
  String? _errorMessage;
  
  // 表示期間
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _selectedDay = DateTime.now();
    _loadMileageData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mileageService.dispose();
    super.dispose();
  }

  /// メーター値データを読み込み
  Future<void> _loadMileageData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      AppLogger.info('メーター値履歴データ読み込み開始', 'MileageHistoryScreen');
      
      final records = await _mileageService.getMileageHistory(_startDate, _endDate);
      
      if (mounted) {
        setState(() {
          _mileageRecords = records;
          _groupedRecords = _groupRecordsByDate(records);
          _isLoading = false;
        });
      }
      
      AppLogger.info('メーター値履歴データ読み込み完了: ${records.length}件', 'MileageHistoryScreen');
    } catch (e) {
      AppLogger.error('メーター値履歴データ読み込みエラー', 'MileageHistoryScreen', e);
      
      if (mounted) {
        setState(() {
          _errorMessage = 'データの読み込みに失敗しました: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// 記録を日付別にグループ化
  Map<DateTime, List<MileageRecord>> _groupRecordsByDate(List<MileageRecord> records) {
    final Map<DateTime, List<MileageRecord>> grouped = {};
    
    for (final record in records) {
      final dateKey = DateTime(record.date.year, record.date.month, record.date.day);
      grouped.putIfAbsent(dateKey, () => []).add(record);
    }
    
    return grouped;
  }

  /// 指定日の記録を取得
  List<MileageRecord> _getRecordsForDay(DateTime day) {
    return _groupedRecords[DateTime(day.year, day.month, day.day)] ?? [];
  }

  /// 期間選択ダイアログ
  Future<void> _showDateRangePickerDialog() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      locale: const Locale('ja', 'JP'),
    );

    if (picked != null && picked.start != _startDate || picked?.end != _endDate) {
      setState(() {
        _startDate = picked!.start;
        _endDate = picked.end;
      });
      await _loadMileageData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('メーター値履歴'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.calendar_today), text: 'カレンダー'),
            Tab(icon: Icon(Icons.show_chart), text: 'グラフ'),
            Tab(icon: Icon(Icons.list), text: '一覧'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _showDateRangePickerDialog,
            tooltip: '期間選択',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMileageData,
            tooltip: '更新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorWidget()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCalendarTab(),
                    _buildGraphTab(),
                    _buildListTab(),
                  ],
                ),
    );
  }

  /// エラー表示ウィジェット
  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadMileageData,
            child: const Text('再試行'),
          ),
        ],
      ),
    );
  }

  /// カレンダータブ
  Widget _buildCalendarTab() {
    return Column(
      children: [
        // 期間表示
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '期間: ${DateFormat('yyyy/MM/dd').format(_startDate)} - ${DateFormat('yyyy/MM/dd').format(_endDate)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              Text(
                '記録: ${_mileageRecords.length}件',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
        // カレンダー
        Expanded(
          child: TableCalendar<MileageRecord>(
            firstDay: DateTime.now().subtract(const Duration(days: 365)),
            lastDay: DateTime.now(),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            eventLoader: _getRecordsForDay,
            startingDayOfWeek: StartingDayOfWeek.sunday,
            locale: 'ja_JP',
            selectedDayPredicate: (day) {
              return isSameDay(_selectedDay, day);
            },
            onDaySelected: (selectedDay, focusedDay) {
              if (!isSameDay(_selectedDay, selectedDay)) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                _showDayDetailDialog(selectedDay);
              }
            },
            onFormatChanged: (format) {
              if (_calendarFormat != format) {
                setState(() {
                  _calendarFormat = format;
                });
              }
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, events) {
                if (events.isNotEmpty) {
                  return Positioned(
                    right: 1,
                    bottom: 1,
                    child: _buildEventMarker(events.cast<MileageRecord>()),
                  );
                }
                return null;
              },
            ),
          ),
        ),
      ],
    );
  }

  /// イベントマーカー
  Widget _buildEventMarker(List<MileageRecord> records) {
    final hasAnomalies = records.any((r) => r.hasAnomalies);
    
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hasAnomalies ? Colors.red : Colors.blue,
      ),
      width: 16,
      height: 16,
      child: Center(
        child: Text(
          '${records.length}',
          style: const TextStyle().copyWith(
            color: Colors.white,
            fontSize: 12.0,
          ),
        ),
      ),
    );
  }

  /// 日別詳細ダイアログ
  void _showDayDetailDialog(DateTime day) {
    final records = _getRecordsForDay(day);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${DateFormat('yyyy年MM月dd日').format(day)}の記録'),
        content: SizedBox(
          width: double.maxFinite,
          child: records.isEmpty
              ? const Text('この日の記録はありません')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return _buildRecordListTile(record);
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  /// グラフタブ
  Widget _buildGraphTab() {
    if (_mileageRecords.isEmpty) {
      return const Center(
        child: Text('表示するデータがありません'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 月間集計
          _buildMonthlySummary(),
          const SizedBox(height: 24),
          // 走行距離推移グラフ
          Expanded(
            child: _buildDistanceChart(),
          ),
        ],
      ),
    );
  }

  /// 月間集計表示
  Widget _buildMonthlySummary() {
    final totalDistance = _mileageRecords
        .where((r) => r.calculatedDistance != null)
        .fold(0.0, (sum, r) => sum + r.calculatedDistance!);
    
    final averageDistance = _mileageRecords.isNotEmpty
        ? totalDistance / _mileageRecords.length
        : 0.0;
    
    final anomaliesCount = _mileageRecords.where((r) => r.hasAnomalies).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '期間集計',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem('総走行距離', '${totalDistance.toStringAsFixed(1)} km'),
                ),
                Expanded(
                  child: _buildSummaryItem('平均走行距離', '${averageDistance.toStringAsFixed(1)} km'),
                ),
                Expanded(
                  child: _buildSummaryItem('異常値件数', '$anomaliesCount 件'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 集計項目ウィジェット
  Widget _buildSummaryItem(String title, String value) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  /// 走行距離推移グラフ
  Widget _buildDistanceChart() {
    final chartData = _mileageRecords
        .where((r) => r.calculatedDistance != null)
        .map((r) => FlSpot(
              r.date.millisecondsSinceEpoch.toDouble(),
              r.calculatedDistance!,
            ))
        .toList();

    if (chartData.isEmpty) {
      return const Center(
        child: Text('グラフに表示するデータがありません'),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '走行距離推移',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text('${value.toInt()}km');
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                          return Text(DateFormat('MM/dd').format(date));
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: chartData,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一覧タブ
  Widget _buildListTab() {
    if (_mileageRecords.isEmpty) {
      return const Center(
        child: Text('表示するデータがありません'),
      );
    }

    return ListView.builder(
      itemCount: _mileageRecords.length,
      itemBuilder: (context, index) {
        final record = _mileageRecords[index];
        return _buildRecordListTile(record);
      },
    );
  }

  /// 記録リストタイル
  Widget _buildRecordListTile(MileageRecord record) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: record.hasAnomalies ? Colors.red : Colors.green,
          child: Icon(
            record.hasAnomalies ? Icons.warning : Icons.check,
            color: Colors.white,
          ),
        ),
        title: Text(
          DateFormat('yyyy年MM月dd日').format(record.date),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('開始: ${record.startMileage.toStringAsFixed(1)} km'),
            if (record.endMileage != null)
              Text('終了: ${record.endMileage!.toStringAsFixed(1)} km'),
            if (record.calculatedDistance != null)
              Text('走行距離: ${record.calculatedDistance!.toStringAsFixed(1)} km'),
            Text('記録方法: ${_getSourceLabel(record.source)}'),
          ],
        ),
        trailing: record.hasAnomalies
            ? const Icon(Icons.error, color: Colors.red)
            : null,
        onTap: () => _showRecordDetailDialog(record),
      ),
    );
  }

  /// 記録方法のラベル取得
  String _getSourceLabel(MileageSource source) {
    switch (source) {
      case MileageSource.manual:
        return '手動入力';
      case MileageSource.gps:
        return 'GPS記録';
      case MileageSource.hybrid:
        return 'GPS+手動修正';
    }
  }

  /// 記録詳細ダイアログ
  void _showRecordDetailDialog(MileageRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${DateFormat('yyyy年MM月dd日').format(record.date)}の詳細'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('開始メーター値', '${record.startMileage.toStringAsFixed(1)} km'),
            if (record.endMileage != null)
              _buildDetailRow('終了メーター値', '${record.endMileage!.toStringAsFixed(1)} km'),
            if (record.calculatedDistance != null)
              _buildDetailRow('走行距離', '${record.calculatedDistance!.toStringAsFixed(1)} km'),
            _buildDetailRow('記録方法', _getSourceLabel(record.source)),
            _buildDetailRow('作成日時', DateFormat('yyyy/MM/dd HH:mm:ss').format(record.createdAt)),
            _buildDetailRow('更新日時', DateFormat('yyyy/MM/dd HH:mm:ss').format(record.updatedAt)),
            if (record.hasAnomalies)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '⚠️ この記録には異常値が検出されています',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  /// 詳細行
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}