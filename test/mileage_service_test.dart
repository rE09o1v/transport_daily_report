import 'package:flutter_test/flutter_test.dart';
import 'package:transport_daily_report/services/mileage_service.dart';
import 'package:transport_daily_report/models/mileage_record.dart';

void main() {
  group('MileageService Tests', () {
    late MileageService mileageService;

    setUp(() {
      mileageService = MileageService();
    });

    tearDown(() {
      mileageService.dispose();
    });

    group('データ検証', () {
      test('正常なメーター値の検証', () async {
        // 正常な値での検証
        final result = await mileageService.validateMileageData(
          100.0,  // 開始
          150.0,  // 終了
        );

        expect(result.isValid, true);
        expect(result.warnings, isEmpty);
        expect(result.flags, isEmpty);
      });

      test('メーター値逆転の検証', () async {
        // 終了値が開始値より小さい場合
        final result = await mileageService.validateMileageData(
          150.0,  // 開始
          100.0,  // 終了
        );

        expect(result.isValid, false);
        expect(result.warnings, contains(contains('逆転')));
        expect(result.flags, contains('METER_REVERSAL'));
      });

      test('異常な走行距離の検証', () async {
        // 1000km超過
        final result = await mileageService.validateMileageData(
          100.0,   // 開始
          1200.0,  // 終了（1100km走行）
        );

        expect(result.isValid, false);
        expect(result.warnings, contains(contains('1000kmを超過')));
        expect(result.flags, contains('EXCESSIVE_DISTANCE'));
      });

      test('GPS距離との乖離検証', () async {
        // GPS距離との大きな差
        final result = await mileageService.validateMileageData(
          100.0,  // 開始
          200.0,  // 終了（100km）
          gpsDistance: 50.0,  // GPS: 50km（50km差）
        );

        expect(result.isValid, false);
        expect(result.warnings, contains(contains('GPS算出距離')));
        expect(result.flags, contains('GPS_MILEAGE_MISMATCH'));
      });
    });

    group('異常値検知', () {
      test('異常値のないMileageRecord', () {
        final record = MileageRecord(
          id: 'test-001',
          date: DateTime.now(),
          startMileage: 100.0,
          endMileage: 150.0,
          source: MileageSource.manual,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(record.hasAnomalies, false);
        expect(record.hasMeterReversal, false);
      });

      test('走行距離異常値のあるMileageRecord', () {
        final record = MileageRecord(
          id: 'test-002',
          date: DateTime.now(),
          startMileage: 100.0,
          endMileage: 1200.0,  // 1100km走行
          source: MileageSource.manual,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(record.hasAnomalies, true);
      });

      test('メーター値逆転のあるMileageRecord', () {
        final record = MileageRecord(
          id: 'test-003',
          date: DateTime.now(),
          startMileage: 150.0,
          endMileage: 100.0,  // 逆転
          source: MileageSource.manual,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(record.hasMeterReversal, true);
      });
    });

    group('データ計算', () {
      test('走行距離の計算', () {
        final record = MileageRecord(
          id: 'test-004',
          date: DateTime.now(),
          startMileage: 100.5,
          endMileage: 250.7,
          source: MileageSource.manual,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(record.calculatedDistance, closeTo(150.2, 0.01));
      });

      test('GPS距離の取得', () {
        final record = MileageRecord(
          id: 'test-005',
          date: DateTime.now(),
          startMileage: 100.0,
          distance: 75.5,  // GPS算出値
          source: MileageSource.gps,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(record.calculatedDistance, closeTo(75.5, 0.01));
      });

      test('データ完整性の確認', () {
        // 完全なデータ
        final completeRecord = MileageRecord(
          id: 'test-006',
          date: DateTime.now(),
          startMileage: 100.0,
          endMileage: 150.0,
          source: MileageSource.manual,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(completeRecord.isComplete, true);

        // 不完全なデータ
        final incompleteRecord = MileageRecord(
          id: 'test-007',
          date: DateTime.now(),
          startMileage: 100.0,
          // endMileage なし
          source: MileageSource.manual,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(incompleteRecord.isComplete, false);
      });
    });

    group('JSONシリアライゼーション', () {
      test('MileageRecordのtoJson/fromJson', () {
        final originalRecord = MileageRecord(
          id: 'test-008',
          date: DateTime(2024, 1, 15),
          startMileage: 1000.5,
          endMileage: 1150.7,
          source: MileageSource.gps,
          createdAt: DateTime(2024, 1, 15, 8, 0),
          updatedAt: DateTime(2024, 1, 15, 18, 0),
        );

        final json = originalRecord.toJson();
        final recreatedRecord = MileageRecord.fromJson(json);

        expect(recreatedRecord.id, originalRecord.id);
        expect(recreatedRecord.date, originalRecord.date);
        expect(recreatedRecord.startMileage, originalRecord.startMileage);
        expect(recreatedRecord.endMileage, originalRecord.endMileage);
        expect(recreatedRecord.source, originalRecord.source);
        expect(recreatedRecord.calculatedDistance, originalRecord.calculatedDistance);
      });
    });

    group('監査ログ', () {
      test('MileageAuditEntryの作成', () {
        final auditEntry = MileageAuditEntry(
          id: 'audit-001',
          recordId: 'mileage-001',
          timestamp: DateTime.now(),
          action: AuditAction.create,
          newValue: 150.0,
          reason: 'テスト用監査ログ',
        );

        expect(auditEntry.id, 'audit-001');
        expect(auditEntry.action, AuditAction.create);
        expect(auditEntry.newValue, 150.0);
      });

      test('MileageAuditEntryのJSONシリアライゼーション', () {
        final auditEntry = MileageAuditEntry(
          id: 'audit-002',
          recordId: 'mileage-002',
          timestamp: DateTime(2024, 1, 15, 9, 30),
          action: AuditAction.modify,
          oldValue: 100.0,
          newValue: 120.0,
          reason: '修正テスト',
        );

        final json = auditEntry.toJson();
        final recreated = MileageAuditEntry.fromJson(json);

        expect(recreated.id, auditEntry.id);
        expect(recreated.action, auditEntry.action);
        expect(recreated.oldValue, auditEntry.oldValue);
        expect(recreated.newValue, auditEntry.newValue);
        expect(recreated.reason, auditEntry.reason);
      });
    });
  });
}