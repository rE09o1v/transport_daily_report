import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:transport_daily_report/models/visit_record.dart';
import 'package:transport_daily_report/models/client.dart';
import 'package:transport_daily_report/models/daily_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _visitRecordsFileName = 'visit_records.json';
  static const String _clientsFileName = 'clients.json';
  static const String _dailyRecordsFileName = 'daily_records.json';
  
  // SharedPreferencesのキー
  static const String _startMileageKey = 'start_mileage';
  static const String _endMileageKey = 'end_mileage';
  static const String _lastUpdateDateKey = 'last_mileage_update_date';
  static const String _morningAlcoholValueKey = 'morning_alcohol_value';
  static const String _eveningAlcoholValueKey = 'evening_alcohol_value';
  static const String _alcoholCheckDateKey = 'alcohol_check_date';

  // SharedPreferencesのインスタンスを取得
  Future<SharedPreferences> getPrefs() async {
    return SharedPreferences.getInstance();
  }

  // 訪問記録の保存
  Future<void> saveVisitRecords(List<VisitRecord> records) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$_visitRecordsFileName');
    
    final jsonData = records.map((record) => record.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonData));
  }

  // 訪問記録の読み込み
  Future<List<VisitRecord>> loadVisitRecords() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_visitRecordsFileName');
      
      if (!await file.exists()) {
        return [];
      }
      
      final jsonString = await file.readAsString();
      final List<dynamic> jsonData = jsonDecode(jsonString);
      
      return jsonData.map((data) => VisitRecord.fromJson(data)).toList();
    } catch (e) {
      print('Error loading visit records: $e');
      return [];
    }
  }

  // 顧客情報の保存
  Future<void> saveClients(List<Client> clients) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$_clientsFileName');
    
    final jsonData = clients.map((client) => client.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonData));
  }

  // 顧客情報の読み込み
  Future<List<Client>> loadClients() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_clientsFileName');
      
      if (!await file.exists()) {
        return [];
      }
      
      final jsonString = await file.readAsString();
      final List<dynamic> jsonData = jsonDecode(jsonString);
      
      return jsonData.map((data) => Client.fromJson(data)).toList();
    } catch (e) {
      print('Error loading clients: $e');
      return [];
    }
  }

  // 単一の訪問記録の追加
  Future<void> addVisitRecord(VisitRecord record) async {
    final records = await loadVisitRecords();
    records.add(record);
    await saveVisitRecords(records);
  }

  // 単一の顧客情報の追加
  Future<void> addClient(Client client) async {
    final clients = await loadClients();
    clients.add(client);
    await saveClients(clients);
  }

  // 指定した日付の訪問記録を取得
  Future<List<VisitRecord>> getVisitRecordsForDate(DateTime date) async {
    final allRecords = await loadVisitRecords();
    return allRecords.where((record) {
      final recordDate = record.arrivalTime;
      return recordDate.year == date.year && 
             recordDate.month == date.month && 
             recordDate.day == date.day;
    }).toList()
      ..sort((a, b) => a.arrivalTime.compareTo(b.arrivalTime));
  }

  // 訪問記録を日付でグループ化
  Future<Map<DateTime, List<VisitRecord>>> getVisitRecordsGroupedByDate() async {
    final allRecords = await loadVisitRecords();
    final Map<DateTime, List<VisitRecord>> groupedRecords = {};
    
    for (final record in allRecords) {
      final recordDate = DateTime(
        record.arrivalTime.year,
        record.arrivalTime.month,
        record.arrivalTime.day,
      );
      
      if (!groupedRecords.containsKey(recordDate)) {
        groupedRecords[recordDate] = [];
      }
      
      groupedRecords[recordDate]!.add(record);
    }
    
    // 各日付内で時間順にソート
    groupedRecords.forEach((date, records) {
      records.sort((a, b) => a.arrivalTime.compareTo(b.arrivalTime));
    });
    
    return groupedRecords;
  }

  // 訪問記録を削除
  Future<void> deleteVisitRecord(String id) async {
    final records = await loadVisitRecords();
    records.removeWhere((record) => record.id == id);
    await saveVisitRecords(records);
  }

  // 訪問記録を更新
  Future<void> updateVisitRecord(VisitRecord updatedRecord) async {
    final records = await loadVisitRecords();
    final index = records.indexWhere((record) => record.id == updatedRecord.id);
    
    if (index != -1) {
      records[index] = updatedRecord;
      await saveVisitRecords(records);
    } else {
      throw Exception('訪問記録が見つかりません: ${updatedRecord.id}');
    }
  }

  // 顧客情報を削除
  Future<void> deleteClient(String id) async {
    final clients = await loadClients();
    clients.removeWhere((client) => client.id == id);
    await saveClients(clients);
  }

  // 走行距離データを保存
  Future<void> saveMileageData(double? startMileage, double? endMileage) async {
    final prefs = await getPrefs();
    
    // 現在の日付を文字列として保存
    final now = DateTime.now();
    final dateStr = DailyRecord.normalizeDate(now);
    
    if (startMileage != null) {
      await prefs.setDouble(_startMileageKey, startMileage);
    }
    
    if (endMileage != null) {
      await prefs.setDouble(_endMileageKey, endMileage);
    }
    
    await prefs.setString(_lastUpdateDateKey, dateStr);
    
    // 日ごとのデータも保存
    await saveDailyRecord(
      dateStr,
      startMileage: startMileage,
      endMileage: endMileage,
    );
  }
  
  // 走行距離データを取得
  Future<Map<String, dynamic>> getMileageData() async {
    final prefs = await getPrefs();
    
    final startMileage = prefs.getDouble(_startMileageKey);
    final endMileage = prefs.getDouble(_endMileageKey);
    final lastUpdateDate = prefs.getString(_lastUpdateDateKey);
    
    return {
      'startMileage': startMileage,
      'endMileage': endMileage,
      'lastUpdateDate': lastUpdateDate,
    };
  }
  
  // 走行距離データをリセット
  Future<void> resetMileageData() async {
    final prefs = await getPrefs();
    await prefs.remove(_startMileageKey);
    await prefs.remove(_endMileageKey);
    await prefs.remove(_lastUpdateDateKey);
  }

  // アルコールチェック値を保存
  Future<void> saveAlcoholValue(bool isMorning, double value) async {
    final prefs = await getPrefs();
    
    // 現在の日付を文字列として保存
    final now = DateTime.now();
    final dateStr = DailyRecord.normalizeDate(now);
    
    if (isMorning) {
      await prefs.setDouble(_morningAlcoholValueKey, value);
    } else {
      await prefs.setDouble(_eveningAlcoholValueKey, value);
    }
    
    await prefs.setString(_alcoholCheckDateKey, dateStr);
    
    // 日ごとのデータも保存
    await saveDailyRecord(
      dateStr,
      morningAlcoholValue: isMorning ? value : null,
      eveningAlcoholValue: isMorning ? null : value,
    );
  }
  
  // アルコールチェック値を取得
  Future<Map<String, dynamic>> getAlcoholValues() async {
    final prefs = await getPrefs();
    
    final morningValue = prefs.getDouble(_morningAlcoholValueKey);
    final eveningValue = prefs.getDouble(_eveningAlcoholValueKey);
    final lastCheckDate = prefs.getString(_alcoholCheckDateKey);
    
    // 日付が変わっていたらリセット
    if (lastCheckDate != null) {
      final now = DateTime.now();
      final currentDateStr = DailyRecord.normalizeDate(now);
      
      if (lastCheckDate != currentDateStr) {
        await resetAlcoholValues();
        return {
          'morningValue': null,
          'eveningValue': null,
          'lastCheckDate': currentDateStr,
        };
      }
    }
    
    return {
      'morningValue': morningValue,
      'eveningValue': eveningValue,
      'lastCheckDate': lastCheckDate,
    };
  }
  
  // アルコールチェック値をリセット
  Future<void> resetAlcoholValues() async {
    final prefs = await getPrefs();
    await prefs.remove(_morningAlcoholValueKey);
    await prefs.remove(_eveningAlcoholValueKey);
    
    // 現在の日付で更新
    final now = DateTime.now();
    final dateStr = DailyRecord.normalizeDate(now);
    await prefs.setString(_alcoholCheckDateKey, dateStr);
  }

  // 日ごとの記録を保存
  Future<void> saveDailyRecord(
    String dateStr, {
    double? startMileage,
    double? endMileage,
    double? morningAlcoholValue,
    double? eveningAlcoholValue,
  }) async {
    // 既存のデータを読み込む
    final allRecords = await loadDailyRecords();
    
    // 指定された日付のレコードを探す
    int existingIndex = allRecords.indexWhere((record) => record.date == dateStr);
    
    if (existingIndex != -1) {
      // 既存のレコードを更新
      DailyRecord existing = allRecords[existingIndex];
      allRecords[existingIndex] = DailyRecord(
        date: dateStr,
        startMileage: startMileage ?? existing.startMileage,
        endMileage: endMileage ?? existing.endMileage,
        morningAlcoholValue: morningAlcoholValue ?? existing.morningAlcoholValue,
        eveningAlcoholValue: eveningAlcoholValue ?? existing.eveningAlcoholValue,
      );
    } else {
      // 新しいレコードを追加
      allRecords.add(DailyRecord(
        date: dateStr,
        startMileage: startMileage,
        endMileage: endMileage,
        morningAlcoholValue: morningAlcoholValue,
        eveningAlcoholValue: eveningAlcoholValue,
      ));
    }
    
    // すべてのレコードを保存
    await _saveDailyRecordsToFile(allRecords);
  }
  
  // 日ごとの記録をファイルに保存
  Future<void> _saveDailyRecordsToFile(List<DailyRecord> records) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_dailyRecordsFileName');
      
      final jsonData = records.map((record) => record.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonData));
    } catch (e) {
      print('Error saving daily records: $e');
      rethrow;
    }
  }
  
  // 日ごとの記録をすべて読み込む
  Future<List<DailyRecord>> loadDailyRecords() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_dailyRecordsFileName');
      
      if (!await file.exists()) {
        return [];
      }
      
      final jsonString = await file.readAsString();
      final List<dynamic> jsonData = jsonDecode(jsonString);
      
      return jsonData.map((data) => DailyRecord.fromJson(data)).toList();
    } catch (e) {
      print('Error loading daily records: $e');
      return [];
    }
  }
  
  // 特定の日付の記録を取得
  Future<DailyRecord?> getDailyRecord(String dateStr) async {
    final allRecords = await loadDailyRecords();
    try {
      return allRecords.firstWhere((record) => record.date == dateStr);
    } catch (e) {
      return null; // 該当する日付のレコードが見つからない場合
    }
  }
  
  // 指定された日付の記録を取得（DateTime形式）
  Future<DailyRecord?> getDailyRecordForDate(DateTime date) async {
    final dateStr = DailyRecord.normalizeDate(date);
    return getDailyRecord(dateStr);
  }
  
  // 今日の記録を取得
  Future<DailyRecord?> getTodayRecord() async {
    final now = DateTime.now();
    final dateStr = DailyRecord.normalizeDate(now);
    return getDailyRecord(dateStr);
  }
} 