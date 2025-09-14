import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'dart:async'; // Completerのためのimport
import '../utils/logger.dart';

// Webプラットフォーム対応
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:transport_daily_report/models/visit_record.dart';
import 'package:transport_daily_report/models/client.dart';
import 'package:transport_daily_report/models/daily_record.dart';
import 'package:transport_daily_report/models/roll_call_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:transport_daily_report/models/mileage_record.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'data_notifier_service.dart';

class StorageService {

  // データ変更通知サービス
  final DataNotifierService _notifier = DataNotifierService();
  // データ変更通知サービスのpublicアクセサー
  DataNotifierService get notifier => _notifier;

  // 新しいメーター値関連のファイル名とキー
  static const String _mileageRecordsFileName = 'mileage_records.json';
  static const String _gpsTrackingRecordsFileName = 'gps_tracking_records.json';
  static const String _mileageAuditLogFileName = 'mileage_audit_log.json';
  static const String _mileageRecordsStorageKey = 'mileage_records';
  static const String _gpsTrackingRecordsStorageKey = 'gps_tracking_records';
  static const String _mileageAuditLogStorageKey = 'mileage_audit_log';

  // ============ MileageRecord 関連メソッド ============

  // MileageRecordの保存
  Future<void> saveMileageRecords(List<MileageRecord> records) async {
    AppLogger.info('MileageRecordの保存を開始: ${records.length}件', 'StorageService');
    
    try {
      final jsonData = records.map((record) => record.toJson()).toList();
      final jsonString = jsonEncode(jsonData);
      
      if (isWeb) {
        final prefs = await getPrefs();
        await prefs.setString(_mileageRecordsStorageKey, jsonString);
        AppLogger.info('Web: SharedPreferencesにMileageRecordを保存', 'StorageService');
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_mileageRecordsFileName');
        await file.writeAsString(jsonString, flush: true);
        AppLogger.info('ネイティブ: ファイルにMileageRecordを保存: ${file.path}', 'StorageService');
      }
    } catch (e) {
      AppLogger.error('MileageRecordの保存中にエラー', 'StorageService', e);
      rethrow;
    }
  }

  // MileageRecordの読み込み
  Future<List<MileageRecord>> loadMileageRecords() async {
    AppLogger.info('MileageRecordの読み込みを開始', 'StorageService');
    
    try {
      String? jsonString;
      
      if (isWeb) {
        final prefs = await getPrefs();
        jsonString = prefs.getString(_mileageRecordsStorageKey);
        if (jsonString == null) return [];
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_mileageRecordsFileName');
        
        if (!await file.exists()) return [];
        jsonString = await file.readAsString();
      }
      
      if (jsonString.isEmpty) return [];
      
      final List<dynamic> jsonData = jsonDecode(jsonString);
      final records = jsonData.map((data) => MileageRecord.fromJson(data)).toList();
      AppLogger.info('MileageRecordの読み込み完了: ${records.length}件', 'StorageService');
      return records;
    } catch (e) {
      AppLogger.error('MileageRecordの読み込み中にエラー', 'StorageService', e);
      return [];
    }
  }

  // MileageRecordの追加
  Future<void> addMileageRecord(MileageRecord record) async {
    AppLogger.info('MileageRecord追加開始: ${record.date}', 'StorageService');
    
    final records = await loadMileageRecords();
    records.add(record);
    await saveMileageRecords(records);
    
    AppLogger.info('MileageRecord追加完了: ${record.id}', 'StorageService');
    
    // データ変更通知
    _notifier.notifyMileageRecordsChanged();
  }

  // 日付でMileageRecordを取得
  Future<MileageRecord?> getMileageRecordByDate(DateTime date) async {
    final allRecords = await loadMileageRecords();
    final normalizedDate = DateTime(date.year, date.month, date.day);
    
    try {
      return allRecords.firstWhere((record) {
        final recordDate = DateTime(record.date.year, record.date.month, record.date.day);
        return recordDate.isAtSameMomentAs(normalizedDate);
      });
    } catch (e) {
      return null;
    }
  }


  // MileageRecordの更新
  Future<void> updateMileageRecord(MileageRecord updatedRecord) async {
    final records = await loadMileageRecords();
    final index = records.indexWhere((record) => record.id == updatedRecord.id);
    
    if (index != -1) {
      records[index] = updatedRecord;
      await saveMileageRecords(records);
      AppLogger.info('MileageRecord更新完了: ${updatedRecord.id}', 'StorageService');
      
      // データ変更通知
      _notifier.notifyMileageRecordsChanged();
    } else {
      throw Exception('MileageRecordが見つかりません: ${updatedRecord.id}');
    }
  }

  // 期間でMileageRecordを取得
  Future<List<MileageRecord>> getMileageRecordsByDateRange(DateTime from, DateTime to) async {
    final allRecords = await loadMileageRecords();
    return allRecords.where((record) {
      return record.date.isAfter(from.subtract(Duration(days: 1))) &&
             record.date.isBefore(to.add(Duration(days: 1)));
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  // ============ GPSTrackingRecord 関連メソッド ============

  // GPSTrackingRecordの保存
  Future<void> saveGPSTrackingRecords(List<GPSTrackingRecord> records) async {
    try {
      final jsonData = records.map((record) => record.toJson()).toList();
      final jsonString = jsonEncode(jsonData);
      
      if (isWeb) {
        final prefs = await getPrefs();
        await prefs.setString(_gpsTrackingRecordsStorageKey, jsonString);
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_gpsTrackingRecordsFileName');
        await file.writeAsString(jsonString, flush: true);
      }
      
      AppLogger.info('GPSTrackingRecord保存完了: ${records.length}件', 'StorageService');
    } catch (e) {
      AppLogger.error('GPSTrackingRecordの保存中にエラー', 'StorageService', e);
      rethrow;
    }
  }

  // GPSTrackingRecordの読み込み
  Future<List<GPSTrackingRecord>> loadGPSTrackingRecords() async {
    try {
      String? jsonString;
      
      if (isWeb) {
        final prefs = await getPrefs();
        jsonString = prefs.getString(_gpsTrackingRecordsStorageKey);
        if (jsonString == null) return [];
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_gpsTrackingRecordsFileName');
        
        if (!await file.exists()) return [];
        jsonString = await file.readAsString();
      }
      
      if (jsonString.isEmpty) return [];
      
      final List<dynamic> jsonData = jsonDecode(jsonString);
      return jsonData.map((data) => GPSTrackingRecord.fromJson(data)).toList();
    } catch (e) {
      AppLogger.error('GPSTrackingRecordの読み込み中にエラー', 'StorageService', e);
      return [];
    }
  }

  // GPSTrackingRecordの追加
  Future<void> addGPSTrackingRecord(GPSTrackingRecord record) async {
    final records = await loadGPSTrackingRecords();
    records.add(record);
    await saveGPSTrackingRecords(records);
  }

  // GPSTrackingRecordをIDで取得
  Future<GPSTrackingRecord?> getGPSTrackingRecordById(String trackingId) async {
    final allRecords = await loadGPSTrackingRecords();
    
    try {
      return allRecords.firstWhere((record) => record.trackingId == trackingId);
    } catch (e) {
      return null;
    }
  }

  // GPSTrackingRecordの更新
  Future<void> updateGPSTrackingRecord(GPSTrackingRecord updatedRecord) async {
    final records = await loadGPSTrackingRecords();
    final index = records.indexWhere((record) => record.trackingId == updatedRecord.trackingId);
    
    if (index != -1) {
      records[index] = updatedRecord;
      await saveGPSTrackingRecords(records);
    } else {
      throw Exception('GPSTrackingRecordが見つかりません: ${updatedRecord.trackingId}');
    }
  }

  // ============ MileageAuditEntry 関連メソッド ============

  // 監査ログの保存
  Future<void> saveMileageAuditLog(List<MileageAuditEntry> entries) async {
    try {
      final jsonData = entries.map((entry) => entry.toJson()).toList();
      final jsonString = jsonEncode(jsonData);
      
      if (isWeb) {
        final prefs = await getPrefs();
        await prefs.setString(_mileageAuditLogStorageKey, jsonString);
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_mileageAuditLogFileName');
        await file.writeAsString(jsonString, flush: true);
      }
    } catch (e) {
      AppLogger.error('MileageAuditLogの保存中にエラー', 'StorageService', e);
      rethrow;
    }
  }

  // 監査ログの読み込み
  Future<List<MileageAuditEntry>> loadMileageAuditLog() async {
    try {
      String? jsonString;
      
      if (isWeb) {
        final prefs = await getPrefs();
        jsonString = prefs.getString(_mileageAuditLogStorageKey);
        if (jsonString == null) return [];
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_mileageAuditLogFileName');
        
        if (!await file.exists()) return [];
        jsonString = await file.readAsString();
      }
      
      if (jsonString.isEmpty) return [];
      
      final List<dynamic> jsonData = jsonDecode(jsonString);
      return jsonData.map((data) => MileageAuditEntry.fromJson(data)).toList();
    } catch (e) {
      AppLogger.error('MileageAuditLogの読み込み中にエラー', 'StorageService', e);
      return [];
    }
  }

  // 監査ログエントリの追加
  Future<void> addMileageAuditEntry(MileageAuditEntry entry) async {
    final entries = await loadMileageAuditLog();
    entries.add(entry);
    await saveMileageAuditLog(entries);
    
    AppLogger.info('監査ログ追加: ${entry.action.name} - RecordID: ${entry.recordId}', 'StorageService');
  }

  // ============ データ暗号化・セキュリティ機能 ============

  // データの改ざん防止用チェックサムを生成
  String _generateChecksum(String data, String timestamp) {
    final input = '$data$timestamp';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // 暗号化されたメーター値データの保存（将来の拡張用）
  Future<void> saveEncryptedMileageData(MileageRecord record) async {
    try {
      final jsonData = record.toJson();
      final timestamp = DateTime.now().toIso8601String();
      final checksum = _generateChecksum(jsonEncode(jsonData), timestamp);
      
      final encryptedPayload = {
        'data': jsonData,
        'timestamp': timestamp,
        'checksum': checksum
      };
      
      // 監査ログに記録
      await addMileageAuditEntry(MileageAuditEntry(
        id: MileageAuditEntry.generateId(),
        recordId: record.id,
        timestamp: DateTime.now(),
        action: AuditAction.create,
        newValue: record.startMileage,
        deviceInfo: 'Flutter App',
        reason: 'メーター値記録作成',
      ));
      
      AppLogger.info('暗号化メーター値データ保存完了: ${record.id}', 'StorageService');
    } catch (e) {
      AppLogger.error('暗号化メーター値データの保存中にエラー', 'StorageService', e);
      rethrow;
    }
  }

  // ============ データ移行・互換性メソッド ============

  // 既存の古いメーター値データを新しい形式に移行
  Future<void> migrateLegacyMileageData() async {
    try {
      AppLogger.info('レガシーメーター値データの移行を開始', 'StorageService');
      
      // 古い形式のデータを読み込み
      final legacyData = await getMileageData();
      final startMileage = legacyData['startMileage'] as double?;
      final endMileage = legacyData['endMileage'] as double?;
      final lastUpdateDate = legacyData['lastUpdateDate'] as String?;
      
      if (startMileage != null && lastUpdateDate != null) {
        final migrationDate = DateTime.now();
        
        // 新しいMileageRecordとして保存
        final mileageRecord = MileageRecord(
          id: MileageRecord.generateId(),
          date: migrationDate,
          startMileage: startMileage,
          endMileage: endMileage,
          source: MileageSource.manual,
          createdAt: migrationDate,
          updatedAt: migrationDate,
        );
        
        await addMileageRecord(mileageRecord);
        
        // 監査ログに移行記録を追加
        await addMileageAuditEntry(MileageAuditEntry(
          id: MileageAuditEntry.generateId(),
          recordId: mileageRecord.id,
          timestamp: migrationDate,
          action: AuditAction.create,
          newValue: startMileage,
          deviceInfo: 'Migration Process',
          reason: 'レガシーデータからの移行',
        ));
        
        AppLogger.info('レガシーデータ移行完了: StartMileage=$startMileage', 'StorageService');
      }
    } catch (e) {
      AppLogger.error('レガシーデータ移行中にエラー', 'StorageService', e);
      // 移行失敗でも処理は継続
    }
  }

  // 既存のファイル名定数
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
    AppLogger.info('訪問記録の保存を開始: ${records.length}件', 'StorageService');
    
    try {
      final jsonData = records.map((record) => record.toJson()).toList();
      final jsonString = jsonEncode(jsonData);
      
      if (isWeb) {
        // Web用の実装 - SharedPreferencesを使用
        final prefs = await getPrefs();
        await prefs.setString(_visitRecordsStorageKey, jsonString);
        AppLogger.info('Web: SharedPreferencesに訪問記録を保存しました', 'StorageService');
      } else {
        // ネイティブ用の実装
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_visitRecordsFileName');
        await file.writeAsString(jsonString, flush: true);
        AppLogger.info('ネイティブ: ファイルに訪問記録を保存しました: ${file.path}', 'StorageService');
        
        // 書き込みが完了したことを確認
        if (await file.exists()) {
          final fileContents = await file.readAsString();
          final savedRecords = jsonDecode(fileContents) as List;
          AppLogger.info('保存されたデータを確認: ${savedRecords.length}件のレコードが保存されています', 'StorageService');
        }
      }
    } catch (e) {
      AppLogger.error('訪問記録の保存中にエラーが発生しました', 'StorageService', e);
      rethrow;
    }
  }

  // 訪問記録の読み込み
  Future<List<VisitRecord>> loadVisitRecords() async {
    AppLogger.info('訪問記録の読み込みを開始', 'StorageService');
    try {
      String? jsonString;
      
      if (isWeb) {
        // Web用の実装 - SharedPreferencesを使用
        final prefs = await getPrefs();
        jsonString = prefs.getString(_visitRecordsStorageKey);
        if (jsonString == null) {
          AppLogger.info('Web: 保存された訪問記録がありません', 'StorageService');
          return [];
        }
        AppLogger.info('Web: SharedPreferencesから訪問記録を読み込みました', 'StorageService');
      } else {
        // ネイティブ用の実装
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_visitRecordsFileName');
        
        if (!await file.exists()) {
          AppLogger.info('ネイティブ: 訪問記録ファイルが存在しません: ${file.path}', 'StorageService');
          return [];
        }
        
        jsonString = await file.readAsString();
        AppLogger.info('ネイティブ: ファイルから訪問記録を読み込みました: ${file.path}', 'StorageService');
      }
      
      // 空文字列やnullの場合は空のリストを返す
      if (jsonString.isEmpty) {
        AppLogger.warning('訪問記録のJSONデータが空です', 'StorageService');
        return [];
      }
      
      final List<dynamic> jsonData = jsonDecode(jsonString);
      final records = jsonData.map((data) => VisitRecord.fromJson(data)).toList();
      AppLogger.info('訪問記録の読み込みが完了しました: ${records.length}件', 'StorageService');
      return records;
    } catch (e) {
      AppLogger.error('訪問記録の読み込み中にエラーが発生しました', 'StorageService', e);
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
      AppLogger.error('顧客情報の読み込み中にエラーが発生しました', 'StorageService', e);
      return [];
    }
  }

  // 単一の訪問記録の追加
  Future<void> addVisitRecord(VisitRecord record) async {
    AppLogger.info('訪問記録の追加を開始: ${record.clientName} (${DateFormat('yyyy/MM/dd HH:mm').format(record.arrivalTime)})', 'StorageService');
    
    // 同期ロックのためのCompleter (完了を保証するため)
    final completer = Completer<void>();
    
    try {
      // 現在のレコードを取得
      final records = await loadVisitRecords();
      AppLogger.info('現在の訪問記録数: ${records.length}件', 'StorageService');
      
      // 新しいレコードを追加
      records.add(record);
      AppLogger.info('新しい訪問記録を追加しました (ID: ${record.id})', 'StorageService');
      
      // ファイルに保存 - 直接awaitせず、completerを使用
      saveVisitRecords(records).then((_) {
        AppLogger.info('訪問記録ファイルへの保存が完了しました', 'StorageService');
        
        // 訪問記録データ変更を通知
        _notifier.notifyVisitRecordsChanged();
        
        // 日付別のグループキャッシュを更新
        // final recordDate = DateTime(
        //   record.arrivalTime.year,
        //   record.arrivalTime.month,
        //   record.arrivalTime.day,
        // );
        
        // 最新の日付ごとのデータを取得して更新を確認
        return getVisitRecordsGroupedByDate();
      }).then((updatedGroups) {
        final recordDate = DateTime(
          record.arrivalTime.year,
          record.arrivalTime.month,
          record.arrivalTime.day,
        );
        final updatedDateRecords = updatedGroups[recordDate] ?? [];
        AppLogger.info('この日付の訪問記録数: ${updatedDateRecords.length}件', 'StorageService');
        
        // 再度読み込みを試してみる (完全に非同期)
        return loadVisitRecords();
      }).then((allRecordsAfterSave) {
        AppLogger.info('保存後の総訪問記録数: ${allRecordsAfterSave.length}件', 'StorageService');
        
        // バグデバッグ用: 追加したレコードが正しく保存されたか確認
        final foundAfterSave = allRecordsAfterSave.any((r) => r.id == record.id);
        AppLogger.debug('保存後の記録に新しいIDが見つかりました: $foundAfterSave', 'StorageService');
        
        // すべての処理が完了
        completer.complete();
      }).catchError((e) {
        AppLogger.error('訪問記録の処理中にエラーが発生しました', 'StorageService', e);
        completer.completeError(e);
      });
      
      // このメソッドを呼び出す側はこのcompleterが完了するまで待つ
      return completer.future;
    } catch (e) {
      AppLogger.error('訪問記録の追加に失敗しました', 'StorageService', e);
      completer.completeError(Exception('訪問記録の追加に失敗しました: $e'));
      return completer.future;
    }
  }

  // 単一の顧客情報の追加
  Future<void> addClient(Client client) async {
    final clients = await loadClients();
    clients.add(client);
    await saveClients(clients);
    
    // 得意先データ変更を通知
    _notifier.notifyClientsChanged();
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
    
    // 訪問記録データ変更を通知
    _notifier.notifyVisitRecordsChanged();
  }


  // 顧客情報を削除
  Future<void> deleteClient(String id) async {
    final clients = await loadClients();
    clients.removeWhere((client) => client.id == id);
    await saveClients(clients);
    
    // 得意先データ変更を通知
    _notifier.notifyClientsChanged();
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
    double? totalDistance,
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
        totalDistance: totalDistance ?? existing.totalDistance,
      );
    } else {
      // 新しいレコードを追加
      allRecords.add(DailyRecord(
        date: dateStr,
        startMileage: startMileage,
        endMileage: endMileage,
        morningAlcoholValue: morningAlcoholValue,
        eveningAlcoholValue: eveningAlcoholValue,
        totalDistance: totalDistance,
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
      AppLogger.error('日次記録の保存中にエラーが発生しました', 'StorageService', e);
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
      AppLogger.error('日次記録の読み込み中にエラーが発生しました', 'StorageService', e);
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
      AppLogger.error('点呼記録の読み込み中にエラーが発生しました', 'StorageService', e);
      return [];
    }
  }
  
  // 単一の点呼記録の追加
  Future<void> addRollCallRecord(RollCallRecord record) async {
    final records = await loadRollCallRecords();
    records.add(record);
    await saveRollCallRecords(records);
    
    // 点呼記録データ変更を通知
    _notifier.notifyRollCallRecordsChanged();
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
  
  // DailyRecordオブジェクトを直接保存（BackupService用）
  Future<void> saveDailyRecordObject(DailyRecord record) async {
    await saveDailyRecord(
      record.date,
      startMileage: record.startMileage,
      endMileage: record.endMileage,
      morningAlcoholValue: record.morningAlcoholValue,
      eveningAlcoholValue: record.eveningAlcoholValue,
      totalDistance: record.totalDistance,
    );
  }

  // GPS追跡による移動距離を保存
  Future<void> saveTotalDistance(double totalDistance) async {
    final now = DateTime.now();
    final dateStr = DailyRecord.normalizeDate(now);
    
    // 日ごとの記録に移動距離を保存
    await saveDailyRecord(
      dateStr,
      totalDistance: totalDistance,
    );
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
      
      // 点呼記録データ変更を通知
      _notifier.notifyRollCallRecordsChanged();
    } else {
      throw Exception('点呼記録が見つかりません: ${updatedRecord.id}');
    }
  }
  
  // 点呼記録を削除
  Future<void> deleteRollCallRecord(String id) async {
    final records = await loadRollCallRecords();
    records.removeWhere((record) => record.id == id);
    await saveRollCallRecords(records);
    
    // 点呼記録データ変更を通知
    _notifier.notifyRollCallRecordsChanged();
  }
} 