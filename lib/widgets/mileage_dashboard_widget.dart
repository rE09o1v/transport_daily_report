import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/mileage_record.dart';
import '../services/mileage_service.dart';

/// メーター値ダッシュボードウィジェット
/// 
/// 統計情報、トレンド分析、異常値検知結果を表示
class MileageDashboardWidget extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  
  const MileageDashboardWidget({
    super.key,
    required this.startDate,
    required this.endDate,
  });
  
  @override
  State<MileageDashboardWidget> createState() => _MileageDashboardWidgetState();
}

class _MileageDashboardWidgetState extends State<MileageDashboardWidget> {
  final MileageService _mileageService = MileageService();
  
  List<MileageRecord> _records = [];
  List<MileageAnomalyReport> _anomalies = [];
  bool _isLoading = false;
  String? _errorMessage;
  
  // 統計データ
  MileageStatistics? _statistics;
  
  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }
  
  @override
  void dispose() {
    _mileageService.dispose();
    super.dispose();
  }
  
  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final startDate = widget.startDate;
      final endDate = widget.endDate;
      
      // データを並行取得
      final results = await Future.wait([
        _mileageService.getMileageHistory(startDate, endDate),
        _mileageService.detectAnomalies(startDate, endDate),
      ]);
      
      final records = results[0] as List<MileageRecord>;
      final anomalies = results[1] as List<MileageAnomalyReport>;
      
      final statistics = _calculateStatistics(records);
      
      setState(() {
        _records = records;
        _anomalies = anomalies;
        _statistics = statistics;
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _errorMessage = 'データの読み込みに失敗しました: $e';
        _isLoading = false;
      });
    }
  }
  
  MileageStatistics _calculateStatistics(List<MileageRecord> records) {
    if (records.isEmpty) {
      return MileageStatistics.empty();
    }
    
    final completedRecords = records.where((r) => r.isComplete).toList();
    final distances = completedRecords
        .where((r) => r.calculatedDistance != null && r.calculatedDistance! >= 0)
        .map((r) => r.calculatedDistance!)
        .toList();
    
    if (distances.isEmpty) {
      return MileageStatistics.empty();
    }
    
    // 基本統計
    final totalDistance = distances.reduce((a, b) => a + b);
    final averageDistance = totalDistance / distances.length;
    final maxDistance = distances.reduce(math.max);
    final minDistance = distances.reduce(math.min);
    
    // GPS使用率
    final gpsRecords = completedRecords.where((r) => r.source == MileageSource.gps).length;
    final gpsUsageRate = completedRecords.isNotEmpty ? gpsRecords / completedRecords.length : 0.0;
    
    // 完了率
    final completionRate = records.isNotEmpty ? completedRecords.length / records.length : 0.0;
    
    // 週別平均（直近7日間）
    final now = DateTime.now();
    final lastWeek = now.subtract(const Duration(days: 7));
    final recentRecords = completedRecords.where((r) => r.date.isAfter(lastWeek)).toList();
    final recentDistances = recentRecords
        .where((r) => r.calculatedDistance != null && r.calculatedDistance! >= 0)
        .map((r) => r.calculatedDistance!)
        .toList();
    final weeklyAverage = recentDistances.isNotEmpty ? 
        recentDistances.reduce((a, b) => a + b) / recentDistances.length : 0.0;
    
    // トレンド分析
    final trendDirection = _analyzeTrend(distances);
    
    return MileageStatistics(
      totalRecords: records.length,
      completedRecords: completedRecords.length,
      totalDistance: totalDistance,
      averageDistance: averageDistance,
      maxDistance: maxDistance,
      minDistance: minDistance,
      gpsUsageRate: gpsUsageRate,
      completionRate: completionRate,
      weeklyAverage: weeklyAverage,
      trendDirection: trendDirection,
      anomalyCount: _anomalies.length,
    );
  }
  
  TrendDirection _analyzeTrend(List<double> distances) {
    if (distances.length < 3) return TrendDirection.stable;
    
    // 直近3つのデータで傾向を判定
    final recent = distances.skip(distances.length - 3).toList();
    final slope = (recent.last - recent.first) / (recent.length - 1);
    
    if (slope > 5) return TrendDirection.increasing;
    if (slope < -5) return TrendDirection.decreasing;
    return TrendDirection.stable;
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('ダッシュボードデータを読み込み中...'),
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
              onPressed: _loadDashboardData,
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー
          _buildHeader(),
          
          const SizedBox(height: 16),
          
          // 主要統計カード
          _buildStatsOverview(),
          
          const SizedBox(height: 16),
          
          // 詳細統計
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildDistanceStats()),
              const SizedBox(width: 16),
              Expanded(child: _buildUsageStats()),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // トレンドと異常値
          _buildTrendAndAnomalies(),
          
          const SizedBox(height: 16),
          
          // 最近の記録
          _buildRecentRecords(),
        ],
      ),
    );
  }
  
  Widget _buildHeader() {
    final startDate = widget.startDate;
    final endDate = widget.endDate;
    
    return Row(
      children: [
        const Icon(Icons.dashboard, color: Colors.blue, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'メーター値ダッシュボード',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              Text(
                '期間: ${_formatDate(startDate)} ～ ${_formatDate(endDate)}',
                style: TextStyle(
                  fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        ),
        const Spacer(),
        IconButton(
          onPressed: _loadDashboardData,
          icon: const Icon(Icons.refresh),
          tooltip: '更新',
        ),
      ],
    );
  }
  
  Widget _buildStatsOverview() {
    if (_statistics == null) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.blue.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMainStatCard(
                  '総走行距離',
                  '${_statistics!.totalDistance.toStringAsFixed(1)} km',
                  Icons.straighten,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMainStatCard(
                  '平均距離',
                  '${_statistics!.averageDistance.toStringAsFixed(1)} km',
                  Icons.trending_up,
                  Colors.green,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: _buildMainStatCard(
                  '記録完了率',
                  '${(_statistics!.completionRate * 100).toStringAsFixed(1)}%',
                  Icons.check_circle,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMainStatCard(
                  'GPS使用率',
                  '${(_statistics!.gpsUsageRate * 100).toStringAsFixed(1)}%',
                  Icons.gps_fixed,
                  Colors.purple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildMainStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDistanceStats() {
    if (_statistics == null) return const SizedBox.shrink();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bar_chart, color: Colors.blue, size: 20),
                SizedBox(width: 8),
                Text(
                  '統計',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            _buildStatRow('最大距離', '${_statistics!.maxDistance.toStringAsFixed(1)} km'),
            _buildStatRow('最小距離', '${_statistics!.minDistance.toStringAsFixed(1)} km'),
            _buildStatRow('週平均', '${_statistics!.weeklyAverage.toStringAsFixed(1)} km'),
            
            const SizedBox(height: 12),
            
            // トレンド表示
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getTrendColor(_statistics!.trendDirection).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getTrendIcon(_statistics!.trendDirection),
                    color: _getTrendColor(_statistics!.trendDirection),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getTrendText(_statistics!.trendDirection),
                    style: TextStyle(
                      fontSize: 12,
                      color: _getTrendColor(_statistics!.trendDirection),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildUsageStats() {
    if (_statistics == null) return const SizedBox.shrink();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.pie_chart, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text(
                  '使用状況',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            _buildStatRow('総記録数', '${_statistics!.totalRecords} 件'),
            _buildStatRow('完了記録数', '${_statistics!.completedRecords} 件'),
            _buildStatRow('異常値検出', '${_statistics!.anomalyCount} 件'),
            
            const SizedBox(height: 12),
            
            // 完了率プログレスバー
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '記録完了率',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: _statistics!.completionRate,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _statistics!.completionRate >= 0.8 ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(_statistics!.completionRate * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // GPS使用率プログレスバー
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GPS使用率',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: _statistics!.gpsUsageRate,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _statistics!.gpsUsageRate >= 0.5 ? Colors.blue : Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(_statistics!.gpsUsageRate * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTrendAndAnomalies() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_anomalies.isNotEmpty) ...[
          Expanded(child: _buildAnomaliesCard()),
          const SizedBox(width: 16),
        ],
        Expanded(child: _buildQuickActions()),
      ],
    );
  }
  
  Widget _buildAnomaliesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '異常値検出',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_anomalies.length}件',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            ..._anomalies.take(3).map((anomaly) => _buildAnomalyItem(anomaly)),
            
            if (_anomalies.length > 3) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => _showAllAnomalies(),
                  child: Text('他${_anomalies.length - 3}件を表示'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildAnomalyItem(MileageAnomalyReport anomaly) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(
            _getSeverityIcon(anomaly.severity),
            color: _getSeverityColor(anomaly.severity),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(anomaly.record.date),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _getAnomalyDescription(anomaly),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildQuickActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.flash_on, color: Colors.blue, size: 20),
                SizedBox(width: 8),
                Text(
                  'クイックアクション',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            _buildActionButton(
              '詳細履歴を表示',
              Icons.history,
              Colors.blue,
              () => _showDetailedHistory(),
            ),
            
            const SizedBox(height: 8),
            
            _buildActionButton(
              'データエクスポート',
              Icons.download,
              Colors.green,
              () => _exportData(),
            ),
            
            const SizedBox(height: 8),
            
            _buildActionButton(
              'レポート生成',
              Icons.assessment,
              Colors.purple,
              () => _generateReport(),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRecentRecords() {
    final recentRecords = _records.take(5).toList();
    
    if (recentRecords.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.access_time, color: Colors.grey, size: 20),
                SizedBox(width: 8),
                Text(
                  '最近の記録',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            ...recentRecords.map((record) => _buildRecentRecordItem(record)),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRecentRecordItem(MileageRecord record) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            record.source == MileageSource.gps ? Icons.gps_fixed : Icons.edit,
            color: record.source == MileageSource.gps ? Colors.green : Colors.blue,
            size: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(record.date),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (record.calculatedDistance != null)
                  Text(
                    '走行距離: ${record.calculatedDistance!.toStringAsFixed(1)} km',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: record.isComplete ? Colors.green.shade100 : Colors.orange.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              record.isComplete ? '完了' : '未完了',
              style: TextStyle(
                fontSize: 10,
                color: record.isComplete ? Colors.green.shade700 : Colors.orange.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActionButton(String text, IconData icon, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: color),
        label: Text(text),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
  
  // ヘルパーメソッド
  IconData _getTrendIcon(TrendDirection direction) {
    switch (direction) {
      case TrendDirection.increasing:
        return Icons.trending_up;
      case TrendDirection.decreasing:
        return Icons.trending_down;
      case TrendDirection.stable:
        return Icons.trending_flat;
    }
  }
  
  Color _getTrendColor(TrendDirection direction) {
    switch (direction) {
      case TrendDirection.increasing:
        return Colors.green;
      case TrendDirection.decreasing:
        return Colors.red;
      case TrendDirection.stable:
        return Colors.blue;
    }
  }
  
  String _getTrendText(TrendDirection direction) {
    switch (direction) {
      case TrendDirection.increasing:
        return '増加傾向';
      case TrendDirection.decreasing:
        return '減少傾向';
      case TrendDirection.stable:
        return '安定';
    }
  }
  
  IconData _getSeverityIcon(AnomalySeverity severity) {
    switch (severity) {
      case AnomalySeverity.high:
        return Icons.error;
      case AnomalySeverity.medium:
        return Icons.warning;
      case AnomalySeverity.low:
        return Icons.info;
    }
  }
  
  Color _getSeverityColor(AnomalySeverity severity) {
    switch (severity) {
      case AnomalySeverity.high:
        return Colors.red;
      case AnomalySeverity.medium:
        return Colors.orange;
      case AnomalySeverity.low:
        return Colors.blue;
    }
  }
  
  String _getAnomalyDescription(MileageAnomalyReport anomaly) {
    final types = anomaly.anomalyTypes.map((type) {
      switch (type) {
        case AnomalyType.excessiveDistance:
          return '異常な走行距離';
        case AnomalyType.meterReversal:
          return 'メーター逆転';
        case AnomalyType.gpsMismatch:
          return 'GPS値不一致';
        case AnomalyType.dataInconsistency:
          return 'データ不整合';
      }
    }).join(', ');
    
    return types;
  }
  
  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
  
  // アクションメソッド
  void _showAllAnomalies() {
    // 異常値詳細ダイアログを表示
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('異常値一覧'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _anomalies.length,
            itemBuilder: (context, index) {
              return _buildAnomalyItem(_anomalies[index]);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }
  
  void _showDetailedHistory() {
    // 詳細履歴画面への遷移（実装はプロジェクトに応じて調整）
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('詳細履歴画面を表示')),
    );
  }
  
  void _exportData() {
    // データエクスポート機能（実装はプロジェクトに応じて調整）
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('データエクスポート機能')),
    );
  }
  
  void _generateReport() {
    // レポート生成機能（実装はプロジェクトに応じて調整）
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('レポート生成機能')),
    );
  }
}

/// メーター値統計データクラス
class MileageStatistics {
  final int totalRecords;
  final int completedRecords;
  final double totalDistance;
  final double averageDistance;
  final double maxDistance;
  final double minDistance;
  final double gpsUsageRate;
  final double completionRate;
  final double weeklyAverage;
  final TrendDirection trendDirection;
  final int anomalyCount;
  
  MileageStatistics({
    required this.totalRecords,
    required this.completedRecords,
    required this.totalDistance,
    required this.averageDistance,
    required this.maxDistance,
    required this.minDistance,
    required this.gpsUsageRate,
    required this.completionRate,
    required this.weeklyAverage,
    required this.trendDirection,
    required this.anomalyCount,
  });
  
  factory MileageStatistics.empty() {
    return MileageStatistics(
      totalRecords: 0,
      completedRecords: 0,
      totalDistance: 0.0,
      averageDistance: 0.0,
      maxDistance: 0.0,
      minDistance: 0.0,
      gpsUsageRate: 0.0,
      completionRate: 0.0,
      weeklyAverage: 0.0,
      trendDirection: TrendDirection.stable,
      anomalyCount: 0,
    );
  }
}

/// トレンド方向
enum TrendDirection {
  increasing,  // 増加
  decreasing,  // 減少
  stable,      // 安定
}