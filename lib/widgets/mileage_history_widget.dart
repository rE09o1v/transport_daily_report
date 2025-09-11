import 'package:flutter/material.dart';
import '../models/mileage_record.dart';
import '../services/mileage_service.dart';
import 'mileage_dashboard_widget.dart';

/// メーター値履歴表示ウィジェット
/// 
/// 過去のメーター値記録を一覧表示し、詳細確認や分析機能を提供
class MileageHistoryWidget extends StatefulWidget {
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  
  const MileageHistoryWidget({
    super.key,
    this.initialStartDate,
    this.initialEndDate,
  });
  
  @override
  State<MileageHistoryWidget> createState() => _MileageHistoryWidgetState();
}

class _MileageHistoryWidgetState extends State<MileageHistoryWidget> 
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MileageService _mileageService = MileageService();
  
  List<MileageRecord> _records = [];
  bool _isLoading = false;
  String? _errorMessage;
  
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  
  // 表示設定
  bool _showGpsOnly = false;
  bool _showIncompleteOnly = false;
  String _sortBy = 'date_desc'; // date_desc, date_asc, distance_desc, distance_asc
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.initialStartDate != null) {
      _startDate = widget.initialStartDate!;
    }
    if (widget.initialEndDate != null) {
      _endDate = widget.initialEndDate!;
    }
    _loadHistoryData();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _mileageService.dispose();
    super.dispose();
  }
  
  Future<void> _loadHistoryData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final records = await _mileageService.getMileageHistory(_startDate, _endDate);
      final filteredRecords = _applyFilters(records);
      final sortedRecords = _applySorting(filteredRecords);
      
      setState(() {
        _records = sortedRecords;
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _errorMessage = 'データの読み込みに失敗しました: $e';
        _isLoading = false;
      });
    }
  }
  
  List<MileageRecord> _applyFilters(List<MileageRecord> records) {
    return records.where((record) {
      if (_showGpsOnly && record.source != MileageSource.gps) {
        return false;
      }
      if (_showIncompleteOnly && record.isComplete) {
        return false;
      }
      return true;
    }).toList();
  }
  
  List<MileageRecord> _applySorting(List<MileageRecord> records) {
    final sortedRecords = List<MileageRecord>.from(records);
    
    switch (_sortBy) {
      case 'date_desc':
        sortedRecords.sort((a, b) => b.date.compareTo(a.date));
        break;
      case 'date_asc':
        sortedRecords.sort((a, b) => a.date.compareTo(b.date));
        break;
      case 'distance_desc':
        sortedRecords.sort((a, b) => (b.calculatedDistance ?? 0).compareTo(a.calculatedDistance ?? 0));
        break;
      case 'distance_asc':
        sortedRecords.sort((a, b) => (a.calculatedDistance ?? 0).compareTo(b.calculatedDistance ?? 0));
        break;
    }
    
    return sortedRecords;
  }
  
  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      locale: const Locale('ja'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.blue,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      await _loadHistoryData();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー
            Row(
              children: [
                const Icon(Icons.speed, color: Colors.blue, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'メーター値管理',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _loadHistoryData,
                  icon: const Icon(Icons.refresh),
                  tooltip: '更新',
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // タブバー
            TabBar(
              controller: _tabController,
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blue,
              tabs: const [
                Tab(
                  icon: Icon(Icons.history),
                  text: '履歴',
                ),
                Tab(
                  icon: Icon(Icons.dashboard),
                  text: 'ダッシュボード',
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // タブビュー
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 履歴タブ
                  Column(
                    children: [
                      // フィルター・ソート設定
                      _buildFilterAndSortSection(),
                      
                      const SizedBox(height: 16),
                      
                      // データ表示部分
                      Expanded(
                        child: _buildDataSection(),
                      ),
                    ],
                  ),
                  
                  // ダッシュボードタブ
                  MileageDashboardWidget(
                    startDate: _startDate,
                    endDate: _endDate,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFilterAndSortSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          // 期間選択
          Row(
            children: [
              const Icon(Icons.date_range, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: _selectDateRange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.white,
                    ),
                    child: Text(
                      '${_formatDate(_startDate)} ～ ${_formatDate(_endDate)}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // フィルターとソート
          Row(
            children: [
              // GPS記録のみ表示
              Expanded(
                child: CheckboxListTile(
                  title: const Text('GPS記録のみ', style: TextStyle(fontSize: 13)),
                  value: _showGpsOnly,
                  onChanged: (value) {
                    setState(() {
                      _showGpsOnly = value ?? false;
                    });
                    _loadHistoryData();
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              
              // 未完了のみ表示
              Expanded(
                child: CheckboxListTile(
                  title: const Text('未完了のみ', style: TextStyle(fontSize: 13)),
                  value: _showIncompleteOnly,
                  onChanged: (value) {
                    setState(() {
                      _showIncompleteOnly = value ?? false;
                    });
                    _loadHistoryData();
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // ソート設定
          Row(
            children: [
              const Icon(Icons.sort, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              const Text('並び順:', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  value: _sortBy,
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _sortBy = newValue;
                      });
                      _loadHistoryData();
                    }
                  },
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'date_desc', child: Text('日付（新→古）', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'date_asc', child: Text('日付（古→新）', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'distance_desc', child: Text('距離（大→小）', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'distance_asc', child: Text('距離（小→大）', style: TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildDataSection() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('データを読み込んでいます...'),
          ],
        ),
      );
    }
    
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadHistoryData,
              child: const Text('再試行'),
            ),
          ],
        ),
      );
    }
    
    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              '指定期間内にデータが見つかりませんでした',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              '期間を変更するか、フィルターを調整してください',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        // サマリー情報
        _buildSummarySection(),
        
        const SizedBox(height: 16),
        
        // データ一覧
        Expanded(
          child: _buildDataList(),
        ),
      ],
    );
  }
  
  Widget _buildSummarySection() {
    final totalRecords = _records.length;
    final completedRecords = _records.where((r) => r.isComplete).length;
    final totalDistance = _records
        .where((r) => r.calculatedDistance != null)
        .fold(0.0, (sum, r) => sum + r.calculatedDistance!);
    final avgDistance = totalRecords > 0 ? totalDistance / totalRecords : 0.0;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryItem('総件数', '$totalRecords件', Icons.list_alt),
          ),
          Expanded(
            child: _buildSummaryItem('完了済み', '$completedRecords件', Icons.check_circle),
          ),
          Expanded(
            child: _buildSummaryItem('総距離', '${totalDistance.toStringAsFixed(1)}km', Icons.straighten),
          ),
          Expanded(
            child: _buildSummaryItem('平均距離', '${avgDistance.toStringAsFixed(1)}km', Icons.trending_up),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.blue.shade700),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.blue.shade700,
          ),
        ),
      ],
    );
  }
  
  Widget _buildDataList() {
    return ListView.builder(
      itemCount: _records.length,
      itemBuilder: (context, index) {
        final record = _records[index];
        return _buildRecordCard(record);
      },
    );
  }
  
  Widget _buildRecordCard(MileageRecord record) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー行
            Row(
              children: [
                Icon(
                  _getRecordIcon(record),
                  color: _getRecordColor(record),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDate(record.date),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _buildRecordBadge(record),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // メーター値情報
            Row(
              children: [
                Expanded(
                  child: _buildMileageInfo(
                    '開始',
                    record.startMileage,
                    Icons.play_circle_outline,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMileageInfo(
                    '終了',
                    record.endMileage,
                    Icons.stop_circle_outlined,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMileageInfo(
                    '距離',
                    record.calculatedDistance,
                    Icons.straighten,
                  ),
                ),
              ],
            ),
            
            // 異常情報表示（ある場合）
            if (record.hasAnomalies || record.auditLog.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildAnomalyInfo(record),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildMileageInfo(String label, double? value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value != null ? '${value.toStringAsFixed(1)}km' : '未記録',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: value != null ? Colors.black87 : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRecordBadge(MileageRecord record) {
    String text;
    Color color;
    
    if (!record.isComplete) {
      text = '未完了';
      color = Colors.orange;
    } else if (record.source == MileageSource.gps) {
      text = 'GPS';
      color = Colors.green;
    } else if (record.source == MileageSource.hybrid) {
      text = 'GPS+手動';
      color = Colors.blue;
    } else {
      text = '手動';
      color = Colors.grey;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
  
  Widget _buildAnomalyInfo(MileageRecord record) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_outlined, color: Colors.orange.shade700, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              record.hasAnomalies ? '異常値を検出' : '監査ログあり',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _showRecordDetails(record),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: const Text('詳細', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
  
  IconData _getRecordIcon(MileageRecord record) {
    if (!record.isComplete) return Icons.schedule;
    if (record.hasAnomalies) return Icons.warning;
    if (record.source == MileageSource.gps) return Icons.gps_fixed;
    return Icons.edit;
  }
  
  Color _getRecordColor(MileageRecord record) {
    if (!record.isComplete) return Colors.orange;
    if (record.hasAnomalies) return Colors.red;
    if (record.source == MileageSource.gps) return Colors.green;
    return Colors.blue;
  }
  
  void _showRecordDetails(MileageRecord record) {
    showDialog(
      context: context,
      builder: (context) => MileageRecordDetailDialog(record: record),
    );
  }
  
  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
}

/// メーター値記録詳細ダイアログ
class MileageRecordDetailDialog extends StatelessWidget {
  final MileageRecord record;
  
  const MileageRecordDetailDialog({
    super.key,
    required this.record,
  });
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('詳細情報 - ${_formatDate(record.date)}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDetailRow('記録ID', record.id),
            _buildDetailRow('記録方法', _getSourceText(record.source)),
            _buildDetailRow('開始メーター値', '${record.startMileage.toStringAsFixed(1)} km'),
            if (record.endMileage != null)
              _buildDetailRow('終了メーター値', '${record.endMileage!.toStringAsFixed(1)} km'),
            if (record.calculatedDistance != null)
              _buildDetailRow('走行距離', '${record.calculatedDistance!.toStringAsFixed(1)} km'),
            _buildDetailRow('作成日時', _formatDateTime(record.createdAt)),
            _buildDetailRow('更新日時', _formatDateTime(record.updatedAt)),
            
            if (record.gpsTrackingData != null) ...[
              const SizedBox(height: 16),
              const Text('GPS情報', style: TextStyle(fontWeight: FontWeight.bold)),
              _buildDetailRow('追跡ID', record.gpsTrackingData!.trackingId),
            ],
            
            // GPS エラー情報は gpsTrackingData 内で管理
            // if (record.gpsError != null) ...[
            //   const SizedBox(height: 8),
            //   Container(
            //     padding: const EdgeInsets.all(8),
            //     decoration: BoxDecoration(
            //       color: Colors.red.shade50,
            //       border: Border.all(color: Colors.red.shade200),
            //       borderRadius: BorderRadius.circular(4),
            //     ),
            //     child: Text(
            //       'GPSエラー: ${record.gpsError}',
            //       style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            //     ),
            //   ),
            // ],
            
            if (record.auditLog.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('監査ログ', style: TextStyle(fontWeight: FontWeight.bold)),
              ...record.auditLog.map((entry) => _buildAuditLogEntry(entry)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
  
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
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAuditLogEntry(MileageAuditEntry entry) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDateTime(entry.timestamp),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          Text(
            '${entry.action.name}: ${entry.reason}',
            style: const TextStyle(fontSize: 12),
          ),
          if (entry.oldValue != null || entry.newValue != null)
            Text(
              '${entry.oldValue ?? "なし"} → ${entry.newValue ?? "なし"}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }
  
  String _getSourceText(MileageSource source) {
    switch (source) {
      case MileageSource.manual:
        return '手動入力';
      case MileageSource.gps:
        return 'GPS記録';
      case MileageSource.hybrid:
        return 'GPS+手動修正';
    }
  }
  
  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
  
  String _formatDateTime(DateTime dateTime) {
    return '${_formatDate(dateTime)} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}