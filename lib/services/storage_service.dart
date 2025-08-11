import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'dart:async'; // Completerのためのimport

// Webプラットフォーム対応
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:transport_daily_report/models/visit_record.dart';
import 'package:transport_daily_report/models/client.dart';
import 'package:transport_daily_report/models/daily_record.dart';
import 'package:transport_daily_report/models/roll_call_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _visitRecordsFileName = 'visit_records.json';
  static const String _clientsFileName = 'clients.json';
  static const String _dailyRecordsFileName = 'daily_records.json';
  static const String _rollCallRecordsFileName = 'roll_call_records.json';
  
  // SharedPreferencesのキー
  static const String _startMileageKey = 'start_mileage';
  static const String _endMileageKey = 'end_mileage';
  static const String _lastUpdateDateKey = 'last_mileage_update_date';
  static const String _morningAlcoholValueKey = 'morning_alcohol_value';
  static const String _eveningAlcoholValueKey = 'evening_alcohol_value';
  static const String _alcoholCheckDateKey = 'alcohol_check_date';

  // LocalStorage用のキー（Web向け）
  static const String _rollCallRecordsStorageKey = 'roll_call_records';
  static const String _visitRecordsStorageKey = 'visit_records';
  static const String _clientsStorageKey = 'clients';
  static const String _dailyRecordsStorageKey = 'daily_records';

  // SharedPreferencesのインスタンスを取得
  Future<SharedPreferences> getPrefs() async {
    return SharedPreferences.getInstance();
  }

  // プラットフォーム判定（Webかどうか）
  bool get isWeb => kIsWeb;

  // 訪問記録の保存
  Future<void> saveVisitRecords(List<VisitRecord> records) async {
    print('訪問記録の保存を開始: ${records.length}件');
    
    try {
      final jsonData = records.map((record) => record.toJson()).toList();
      final jsonString = jsonEncode(jsonData);
      
      if (isWeb) {
        // Web用の実装 - SharedPreferencesを使用
        final prefs = await getPrefs();
        await prefs.setString(_visitRecordsStorageKey, jsonString);
        print('Web: SharedPreferencesに訪問記録を保存しました');
      } else {
        // ネイティブ用の実装
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_visitRecordsFileName');
        await file.writeAsString(jsonString, flush: true);
        print('ネイティブ: ファイルに訪問記録を保存しました: ${file.path}');
        
        // 書き込みが完了したことを確認
        if (await file.exists()) {
          final fileContents = await file.readAsString();
          final savedRecords = jsonDecode(fileContents) as List;
          print('保存されたデータを確認: ${savedRecords.length}件のレコードが保存されています');
        }
      }
    } catch (e) {
      print('訪問記録の保存中にエラーが発生しました: $e');
      rethrow;
    }
  }

  // 訪問記録の読み込み
  Future<List<VisitRecord>> loadVisitRecords() async {
    print('訪問記録の読み込みを開始');
    try {
      String? jsonString;
      
      if (isWeb) {
        // Web用の実装 - SharedPreferencesを使用
        final prefs = await getPrefs();
        jsonString = prefs.getString(_visitRecordsStorageKey);
        if (jsonString == null) {
          print('Web: 保存された訪問記録がありません');
          return [];
        }
        print('Web: SharedPreferencesから訪問記録を読み込みました');
      } else {
        // ネイティブ用の実装
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_visitRecordsFileName');
        
        if (!await file.exists()) {
          print('ネイティブ: 訪問記録ファイルが存在しません: ${file.path}');
          return [];
        }
        
        jsonString = await file.readAsString();
        print('ネイティブ: ファイルから訪問記録を読み込みました: ${file.path}');
      }
      
      // 空文字列やnullの場合は空のリストを返す
      if (jsonString.isEmpty) {
        print('訪問記録のJSONデータが空です');
        return [];
      }
      
      final List<dynamic> jsonData = jsonDecode(jsonString);
      final records = jsonData.map((data) => VisitRecord.fromJson(data)).toList();
      print('訪問記録の読み込みが完了しました: ${records.length}件');
      return records;
    } catch (e) {
      print('訪問記録の読み込み中にエラーが発生しました: $e');
      return [];
    }
  }

  // 顧客情報の保存
  Future<void> saveClients(List<Client> clients) async {
    final jsonData = clients.map((client) => client.toJson()).toList();
    final jsonString = jsonEncode(jsonData);
    
    if (isWeb) {
      // Web用の実装 - SharedPreferencesを使用
      final prefs = await getPrefs();
      await prefs.setString(_clientsStorageKey, jsonString);
    } else {
      // ネイティブ用の実装
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_clientsFileName');
      await file.writeAsString(jsonString);
    }
  }

  // 顧客情報の読み込み
  Future<List<Client>> loadClients() async {
    try {
      String? jsonString;
      
      if (isWeb) {
        // Web用の実装 - SharedPreferencesを使用
        final prefs = await getPrefs();
        jsonString = prefs.getString(_clientsStorageKey);
        if (jsonString == null) return [];
      } else {
        // ネイティブ用の実装
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_clientsFileName');
        
        if (!await file.exists()) {
          return [];
        }
        
        jsonString = await file.readAsString();
      }
      
      final List<dynamic> jsonData = jsonDecode(jsonString);
      return jsonData.map((data) => Client.fromJson(data)).toList();
    } catch (e) {
      print('Error loading clients: $e');
      return [];
    }
  }

  // 単一の訪問記録の追加
  Future<void> addVisitRecord(VisitRecord record) async {
    print('訪問記録の追加を開始: ${record.clientName} (${DateFormat('yyyy/MM/dd HH:mm').format(record.arrivalTime)})');
    
    // 同期ロックのためのCompleter (完了を保証するため)
    final completer = Completer<void>();
    
    try {
      // 現在のレコードを取得
      final records = await loadVisitRecords();
      print('現在の訪問記録数: ${records.length}件');
      
      // 新しいレコードを追加
      records.add(record);
      print('新しい訪問記録を追加しました (ID: ${record.id})');
      
      // ファイルに保存 - 直接awaitせず、completerを使用
      saveVisitRecords(records).then((_) {
        print('訪問記録ファイルへの保存が完了しました');
        
        // 日付別のグループキャッシュを更新
        final recordDate = DateTime(
          record.arrivalTime.year,
          record.arrivalTime.month,
          record.arrivalTime.day,
        );
        
        // 最新の日付ごとのデータを取得して更新を確認
        return getVisitRecordsGroupedByDate();
      }).then((updatedGroups) {
        final recordDate = DateTime(
          record.arrivalTime.year,
          record.arrivalTime.month,
          record.arrivalTime.day,
        );
        final updatedDateRecords = updatedGroups[recordDate] ?? [];
        print('この日付の訪問記録数: ${updatedDateRecords.length}件');
        
        // 再度読み込みを試してみる (完全に非同期)
        return loadVisitRecords();
      }).then((allRecordsAfterSave) {
        print('保存後の総訪問記録数: ${allRecordsAfterSave.length}件');
        
        // バグデバッグ用: 追加したレコードが正しく保存されたか確認
        final foundAfterSave = allRecordsAfterSave.any((r) => r.id == record.id);
        print('保存後の記録に新しいIDが見つかりました: $foundAfterSave');
        
        // すべての処理が完了
        completer.complete();
      }).catchError((e) {
        print('訪問記録の処理中にエラーが発生しました: $e');
        completer.completeError(e);
      });
      
      // このメソッドを呼び出す側はこのcompleterが完了するまで待つ
      return completer.future;
    } catch (e) {
      print('訪問記録の追加に失敗しました: $e');
      completer.completeError(Exception('訪問記録の追加に失敗しました: $e'));
      return completer.future;
    }
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
      final jsonData = records.map((record) => record.toJson()).toList();
      final jsonString = jsonEncode(jsonData);

      if (isWeb) {
        // Web用の実装 - SharedPreferencesを使用
        final prefs = await getPrefs();
        await prefs.setString(_dailyRecordsStorageKey, jsonString);
      } else {
        // ネイティブ用の実装
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_dailyRecordsFileName');
        await file.writeAsString(jsonString);
      }
    } catch (e) {
      print('Error saving daily records: $e');
      rethrow;
    }
  }
  
  // 日ごとの記録をすべて読み込む
  Future<List<DailyRecord>> loadDailyRecords() async {
    try {
      String? jsonString;
      
      if (isWeb) {
        // Web用の実装 - SharedPreferencesを使用
        final prefs = await getPrefs();
        jsonString = prefs.getString(_dailyRecordsStorageKey);
        if (jsonString == null) return [];
      } else {
        // ネイティブ用の実装
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_dailyRecordsFileName');
        
        if (!await file.exists()) {
          return [];
        }
        
        jsonString = await file.readAsString();
      }
      
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
  
  // 点呼記録の保存
  Future<void> saveRollCallRecords(List<RollCallRecord> records) async {
    final jsonData = records.map((record) => record.toJson()).toList();
    final jsonString = jsonEncode(jsonData);
    
    if (isWeb) {
      // Web用の実装 - SharedPreferencesを使用
      final prefs = await getPrefs();
      await prefs.setString(_rollCallRecordsStorageKey, jsonString);
    } else {
      // ネイティブ用の実装
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_rollCallRecordsFileName');
      await file.writeAsString(jsonString);
    }
  }
  
  // 点呼記録の読み込み
  Future<List<RollCallRecord>> loadRollCallRecords() async {
    try {
      String? jsonString;
      
      if (isWeb) {
        // Web用の実装 - SharedPreferencesを使用
        final prefs = await getPrefs();
        jsonString = prefs.getString(_rollCallRecordsStorageKey);
        if (jsonString == null) return [];
      } else {
        // ネイティブ用の実装
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_rollCallRecordsFileName');
        
        if (!await file.exists()) {
          return [];
        }
        
        jsonString = await file.readAsString();
      }
      
      final List<dynamic> jsonData = jsonDecode(jsonString);
      return jsonData.map((data) => RollCallRecord.fromJson(data)).toList();
    } catch (e) {
      print('Error loading roll call records: $e');
      return [];
    }
  }
  
  // 単一の点呼記録の追加
  Future<void> addRollCallRecord(RollCallRecord record) async {
    final records = await loadRollCallRecords();
    records.add(record);
    await saveRollCallRecords(records);
  }
  
  // 点呼記録を日付で取得
  Future<List<RollCallRecord>> getRollCallRecordsForDate(DateTime date) async {
    final allRecords = await loadRollCallRecords();
    return allRecords.where((record) {
      final recordDate = record.datetime;
      return recordDate.year == date.year && 
             recordDate.month == date.month && 
             recordDate.day == date.day;
    }).toList()
      ..sort((a, b) => a.datetime.compareTo(b.datetime));
  }
  
  // 点呼記録を日付とタイプで取得
  Future<RollCallRecord?> getRollCallRecordByDateAndType(DateTime date, String type) async {
    final dayRecords = await getRollCallRecordsForDate(date);
    
    try {
      return dayRecords.firstWhere((record) => record.type == type);
    } catch (e) {
      return null; // 該当する記録が見つからない場合
    }
  }
  
  // 今日の始業点呼記録を取得
  Future<RollCallRecord?> getTodayStartRollCall() async {
    final now = DateTime.now();
    return getRollCallRecordByDateAndType(now, 'start');
  }
  
  // 今日の終業点呼記録を取得
  Future<RollCallRecord?> getTodayEndRollCall() async {
    final now = DateTime.now();
    return getRollCallRecordByDateAndType(now, 'end');
  }
  
  // 点呼記録を更新
  Future<void> updateRollCallRecord(RollCallRecord updatedRecord) async {
    final records = await loadRollCallRecords();
    final index = records.indexWhere((record) => record.id == updatedRecord.id);
    
    if (index != -1) {
      records[index] = updatedRecord;
      await saveRollCallRecords(records);
    } else {
      throw Exception('点呼記録が見つかりません: ${updatedRecord.id}');
    }
  }
  
  // 点呼記録を削除
  Future<void> deleteRollCallRecord(String id) async {
    final records = await loadRollCallRecords();
    records.removeWhere((record) => record.id == id);
    await saveRollCallRecords(records);
  }
} 