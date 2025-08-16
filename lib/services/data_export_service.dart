import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'storage_service.dart';
import '../models/visit_record.dart';
import '../models/client.dart';
import '../models/daily_record.dart';
import '../models/roll_call_record.dart';

/// データエクスポート/インポートサービス
class DataExportService {
  final StorageService _storageService;
  
  DataExportService(this._storageService);
  
  /// 全データをJSONでエクスポート
  Future<File?> exportAllDataAsJson() async {
    try {
      final data = await _collectAllData();
      final jsonString = JsonEncoder.withIndent('  ').convert(data);
      
      return _saveToFile(jsonString, 'transport_data_export', 'json');
    } catch (e) {
      print('JSONエクスポートエラー: $e');
      return null;
    }
  }
  
  /// 訪問記録をCSVでエクスポート
  Future<File?> exportVisitRecordsAsCsv({DateTime? startDate, DateTime? endDate}) async {
    try {
      final records = await _storageService.loadVisitRecords();
      final filteredRecords = _filterRecordsByDate(records, startDate, endDate);
      
      final csvData = _convertVisitRecordsToCsv(filteredRecords);
      final csvString = const ListToCsvConverter().convert(csvData);
      
      return _saveToFile(csvString, 'visit_records_export', 'csv');
    } catch (e) {
      print('訪問記録CSVエクスポートエラー: $e');
      return null;
    }
  }
  
  /// 点呼記録をCSVでエクスポート
  Future<File?> exportRollCallRecordsAsCsv({DateTime? startDate, DateTime? endDate}) async {
    try {
      final records = await _storageService.loadRollCallRecords();
      final filteredRecords = _filterRollCallRecordsByDate(records, startDate, endDate);
      
      final csvData = _convertRollCallRecordsToCsv(filteredRecords);
      final csvString = const ListToCsvConverter().convert(csvData);
      
      return _saveToFile(csvString, 'roll_call_records_export', 'csv');
    } catch (e) {
      print('点呼記録CSVエクスポートエラー: $e');
      return null;
    }
  }
  
  /// 顧客データをCSVでエクスポート
  Future<File?> exportClientsAsCsv() async {
    try {
      final clients = await _storageService.loadClients();
      
      final csvData = _convertClientsToCsv(clients);
      final csvString = const ListToCsvConverter().convert(csvData);
      
      return _saveToFile(csvString, 'clients_export', 'csv');
    } catch (e) {
      print('顧客データCSVエクスポートエラー: $e');
      return null;
    }
  }
  
  /// JSONデータからインポート
  Future<bool> importFromJson(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('インポートファイルが存在しません: $filePath');
        return false;
      }
      
      final jsonString = await file.readAsString();
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      
      return await _importAllData(data);
    } catch (e) {
      print('JSONインポートエラー: $e');
      return false;
    }
  }
  
  /// 全データを収集
  Future<Map<String, dynamic>> _collectAllData() async {
    final visitRecords = await _storageService.loadVisitRecords();
    final clients = await _storageService.loadClients();
    final dailyRecords = await _storageService.loadDailyRecords();
    final rollCallRecords = await _storageService.loadRollCallRecords();
    
    return {
      'exportInfo': {
        'version': '1.0.0',
        'exportedAt': DateTime.now().toIso8601String(),
        'appName': 'Transport Daily Report',
      },
      'visitRecords': visitRecords.map((r) => r.toJson()).toList(),
      'clients': clients.map((c) => c.toJson()).toList(),
      'dailyRecords': dailyRecords.map((d) => d.toJson()).toList(),
      'rollCallRecords': rollCallRecords.map((r) => r.toJson()).toList(),
    };
  }
  
  /// 全データをインポート
  Future<bool> _importAllData(Map<String, dynamic> data) async {
    try {
      // バージョン確認
      final exportInfo = data['exportInfo'] as Map<String, dynamic>?;
      if (exportInfo != null) {
        final version = exportInfo['version'] as String?;
        print('インポートデータバージョン: $version');
      }
      
      // 訪問記録のインポート
      if (data['visitRecords'] != null) {
        final visitRecords = (data['visitRecords'] as List)
            .map((json) => VisitRecord.fromJson(json as Map<String, dynamic>))
            .toList();
        await _storageService.saveVisitRecords(visitRecords);
        print('訪問記録をインポートしました: ${visitRecords.length}件');
      }
      
      // 顧客データのインポート
      if (data['clients'] != null) {
        final clients = (data['clients'] as List)
            .map((json) => Client.fromJson(json as Map<String, dynamic>))
            .toList();
        await _storageService.saveClients(clients);
        print('顧客データをインポートしました: ${clients.length}件');
      }
      
      // 日次記録のインポート
      if (data['dailyRecords'] != null) {
        final dailyRecords = (data['dailyRecords'] as List)
            .map((json) => DailyRecord.fromJson(json as Map<String, dynamic>))
            .toList();
        for (final record in dailyRecords) {
          await _storageService.saveDailyRecordObject(record);
        }
        print('日次記録をインポートしました: ${dailyRecords.length}件');
      }
      
      // 点呼記録のインポート
      if (data['rollCallRecords'] != null) {
        final rollCallRecords = (data['rollCallRecords'] as List)
            .map((json) => RollCallRecord.fromJson(json as Map<String, dynamic>))
            .toList();
        await _storageService.saveRollCallRecords(rollCallRecords);
        print('点呼記録をインポートしました: ${rollCallRecords.length}件');
      }
      
      return true;
    } catch (e) {
      print('データインポートエラー: $e');
      return false;
    }
  }
  
  /// 訪問記録を日付でフィルタ
  List<VisitRecord> _filterRecordsByDate(List<VisitRecord> records, DateTime? startDate, DateTime? endDate) {
    if (startDate == null && endDate == null) return records;
    
    return records.where((record) {
      final recordDate = record.arrivalTime;
      
      if (startDate != null && recordDate.isBefore(startDate)) return false;
      if (endDate != null && recordDate.isAfter(endDate.add(const Duration(days: 1)))) return false;
      
      return true;
    }).toList();
  }
  
  /// 点呼記録を日付でフィルタ
  List<RollCallRecord> _filterRollCallRecordsByDate(List<RollCallRecord> records, DateTime? startDate, DateTime? endDate) {
    if (startDate == null && endDate == null) return records;
    
    return records.where((record) {
      final recordDate = record.datetime;
      
      if (startDate != null && recordDate.isBefore(startDate)) return false;
      if (endDate != null && recordDate.isAfter(endDate.add(const Duration(days: 1)))) return false;
      
      return true;
    }).toList();
  }
  
  /// 訪問記録をCSV形式に変換
  List<List<String>> _convertVisitRecordsToCsv(List<VisitRecord> records) {
    final csvData = <List<String>>[];
    
    // ヘッダー行
    csvData.add([
      'ID',
      '顧客ID',
      '顧客名',
      '到着日時',
      'メモ',
    ]);
    
    // データ行
    for (final record in records) {
      csvData.add([
        record.id,
        record.clientId,
        record.clientName,
        DateFormat('yyyy/MM/dd HH:mm:ss').format(record.arrivalTime),
        record.notes ?? '',
      ]);
    }
    
    return csvData;
  }
  
  /// 点呼記録をCSV形式に変換
  List<List<String>> _convertRollCallRecordsToCsv(List<RollCallRecord> records) {
    final csvData = <List<String>>[];
    
    // ヘッダー行
    csvData.add([
      'ID',
      '日時',
      'タイプ',
      '点呼方法',
      '点呼執行者',
      'アルコール検知器使用',
      '酒気帯びの有無',
      'アルコール検出量',
      '備考',
    ]);
    
    // データ行
    for (final record in records) {
      csvData.add([
        record.id,
        DateFormat('yyyy/MM/dd HH:mm:ss').format(record.datetime),
        record.type,
        record.method,
        record.inspectorName,
        record.isAlcoholTestUsed ? 'はい' : 'いいえ',
        record.hasDrunkAlcohol ? 'あり' : 'なし',
        record.alcoholValue?.toString() ?? '',
        record.remarks ?? '',
      ]);
    }
    
    return csvData;
  }
  
  /// 顧客データをCSV形式に変換
  List<List<String>> _convertClientsToCsv(List<Client> clients) {
    final csvData = <List<String>>[];
    
    // ヘッダー行
    csvData.add([
      'ID',
      '顧客名',
      '住所',
      '電話番号',
      '緯度',
      '経度',
    ]);
    
    // データ行
    for (final client in clients) {
      csvData.add([
        client.id,
        client.name,
        client.address ?? '',
        client.phoneNumber ?? '',
        client.latitude?.toString() ?? '',
        client.longitude?.toString() ?? '',
      ]);
    }
    
    return csvData;
  }
  
  /// ファイルに保存
  Future<File> _saveToFile(String content, String baseName, String extension) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = '${baseName}_$timestamp.$extension';
    
    if (kIsWeb) {
      // Webの場合はダウンロードとして処理
      throw UnimplementedError('Web版でのファイル保存は未実装です');
    } else {
      // ネイティブアプリの場合
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(content, encoding: utf8);
      
      print('ファイルを保存しました: ${file.path}');
      return file;
    }
  }
  
  /// エクスポートしたファイルを共有
  Future<void> shareExportedFile(File file) async {
    try {
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Transport Daily Report データエクスポート',
        subject: 'データエクスポート - ${file.path.split('/').last}',
      );
    } catch (e) {
      print('ファイル共有エラー: $e');
    }
  }
  
  /// エクスポート可能な形式の一覧
  static const List<ExportFormat> supportedFormats = [
    ExportFormat(
      id: 'json_all',
      name: '全データ (JSON)',
      description: '全てのデータを含むJSON形式でのエクスポート',
      extension: 'json',
    ),
    ExportFormat(
      id: 'csv_visits',
      name: '訪問記録 (CSV)',
      description: '訪問記録のみをCSV形式でエクスポート',
      extension: 'csv',
    ),
    ExportFormat(
      id: 'csv_rollcall',
      name: '点呼記録 (CSV)',
      description: '点呼記録のみをCSV形式でエクスポート',
      extension: 'csv',
    ),
    ExportFormat(
      id: 'csv_clients',
      name: '顧客データ (CSV)',
      description: '顧客データのみをCSV形式でエクスポート',
      extension: 'csv',
    ),
  ];
}

/// エクスポート形式の定義
class ExportFormat {
  final String id;
  final String name;
  final String description;
  final String extension;
  
  const ExportFormat({
    required this.id,
    required this.name,
    required this.description,
    required this.extension,
  });
}