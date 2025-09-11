/// 走行距離記録の独立したモデル
/// 日別の詳細なメーター値・走行距離情報を管理
class MileageRecord {
  final String id;
  final DateTime date; // 記録日付
  final double startMileage; // 開始時メーター値 (km)
  final double? endMileage; // 終了時メーター値 (km)
  final double? distance; // 走行距離 (km)
  final MileageSource source; // 記録方法（手動 or GPS）
  final GPSTrackingRecord? gpsTrackingData; // GPS記録データ（GPS使用時のみ）
  final List<MileageAuditEntry> auditLog; // 監査ログ
  final DateTime createdAt; // 作成日時
  final DateTime updatedAt; // 更新日時

  MileageRecord({
    required this.id,
    required this.date,
    required this.startMileage,
    this.endMileage,
    this.distance,
    required this.source,
    this.gpsTrackingData,
    this.auditLog = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  // 算出された走行距離を取得
  double? get calculatedDistance {
    if (endMileage != null) {
      return endMileage! - startMileage;
    }
    return distance; // GPS算出値
  }

  // データが完全かどうかを確認
  bool get isComplete {
    return endMileage != null || (source == MileageSource.gps && distance != null);
  }

  // 異常値があるかどうかを確認
  bool get hasAnomalies {
    final calc = calculatedDistance;
    if (calc == null) return false;
    
    // 1000km/日超過または負の値
    return calc > 1000.0 || calc < 0;
  }

  // メーター値逆転（メーター交換の可能性）
  bool get hasMeterReversal {
    return endMileage != null && endMileage! < startMileage;
  }

  // IDを生成
  static String generateId() {
    return 'mileage_${DateTime.now().millisecondsSinceEpoch}';
  }

  // コピーファクトリメソッド
  MileageRecord copyWith({
    String? id,
    DateTime? date,
    double? startMileage,
    double? endMileage,
    double? distance,
    MileageSource? source,
    GPSTrackingRecord? gpsTrackingData,
    List<MileageAuditEntry>? auditLog,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MileageRecord(
      id: id ?? this.id,
      date: date ?? this.date,
      startMileage: startMileage ?? this.startMileage,
      endMileage: endMileage ?? this.endMileage,
      distance: distance ?? this.distance,
      source: source ?? this.source,
      gpsTrackingData: gpsTrackingData ?? this.gpsTrackingData,
      auditLog: auditLog ?? this.auditLog,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  // JSONへの変換
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'startMileage': startMileage,
      'endMileage': endMileage,
      'distance': distance,
      'source': source.name,
      'gpsTrackingData': gpsTrackingData?.toJson(),
      'auditLog': auditLog.map((entry) => entry.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // JSONからの生成
  factory MileageRecord.fromJson(Map<String, dynamic> json) {
    return MileageRecord(
      id: json['id'],
      date: DateTime.parse(json['date']),
      startMileage: json['startMileage'].toDouble(),
      endMileage: json['endMileage']?.toDouble(),
      distance: json['distance']?.toDouble(),
      source: MileageSource.values.firstWhere(
        (e) => e.name == json['source'],
        orElse: () => MileageSource.manual,
      ),
      gpsTrackingData: json['gpsTrackingData'] != null
          ? GPSTrackingRecord.fromJson(json['gpsTrackingData'])
          : null,
      auditLog: (json['auditLog'] as List<dynamic>?)
              ?.map((item) => MileageAuditEntry.fromJson(item))
              .toList() ?? [],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

/// 走行距離の記録方法
enum MileageSource {
  manual, // 手動入力
  gps, // GPS記録
  hybrid // GPS+手動修正
}

/// GPS追跡記録モデル
class GPSTrackingRecord {
  final String trackingId;
  final DateTime startTime;
  final DateTime? endTime;
  final double totalDistance; // 総走行距離 (km)
  final bool isComplete; // 記録が完了しているか
  final GPSQualityMetrics qualityMetrics; // 品質指標
  final List<LocationPoint> locationPoints; // 位置データ（デバッグ用）

  GPSTrackingRecord({
    required this.trackingId,
    required this.startTime,
    this.endTime,
    required this.totalDistance,
    required this.isComplete,
    required this.qualityMetrics,
    this.locationPoints = const [],
  });

  // 記録時間を取得
  Duration? get trackingDuration {
    if (endTime == null) return null;
    return endTime!.difference(startTime);
  }

  // IDを生成
  static String generateTrackingId() {
    return 'gps_${DateTime.now().millisecondsSinceEpoch}';
  }

  // コピーファクトリメソッド
  GPSTrackingRecord copyWith({
    String? trackingId,
    DateTime? startTime,
    DateTime? endTime,
    double? totalDistance,
    bool? isComplete,
    GPSQualityMetrics? qualityMetrics,
    List<LocationPoint>? locationPoints,
  }) {
    return GPSTrackingRecord(
      trackingId: trackingId ?? this.trackingId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      totalDistance: totalDistance ?? this.totalDistance,
      isComplete: isComplete ?? this.isComplete,
      qualityMetrics: qualityMetrics ?? this.qualityMetrics,
      locationPoints: locationPoints ?? this.locationPoints,
    );
  }

  // JSONへの変換
  Map<String, dynamic> toJson() {
    return {
      'trackingId': trackingId,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'totalDistance': totalDistance,
      'isComplete': isComplete,
      'qualityMetrics': qualityMetrics.toJson(),
      'locationPoints': locationPoints.map((point) => point.toJson()).toList(),
    };
  }

  // JSONからの生成
  factory GPSTrackingRecord.fromJson(Map<String, dynamic> json) {
    return GPSTrackingRecord(
      trackingId: json['trackingId'],
      startTime: DateTime.parse(json['startTime']),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      totalDistance: json['totalDistance'].toDouble(),
      isComplete: json['isComplete'],
      qualityMetrics: GPSQualityMetrics.fromJson(json['qualityMetrics']),
      locationPoints: (json['locationPoints'] as List<dynamic>?)
              ?.map((item) => LocationPoint.fromJson(item))
              .toList() ?? [],
    );
  }
}

/// GPS品質指標
class GPSQualityMetrics {
  final double accuracyPercentage; // 精度パーセンテージ
  final double signalQuality; // シグナル品質 (0.0-1.0)
  final double batteryImpact; // バッテリー影響度 (0.0-1.0)
  final int totalLocationPoints; // 総位置データポイント数
  final int validLocationPoints; // 有効位置データポイント数

  GPSQualityMetrics({
    required this.accuracyPercentage,
    required this.signalQuality,
    required this.batteryImpact,
    required this.totalLocationPoints,
    required this.validLocationPoints,
  });

  // 品質スコア（総合評価）
  double get qualityScore {
    return (accuracyPercentage + signalQuality * 100) / 2;
  }

  // 有効率
  double get validityRate {
    if (totalLocationPoints == 0) return 0.0;
    return validLocationPoints / totalLocationPoints;
  }

  // JSONへの変換
  Map<String, dynamic> toJson() {
    return {
      'accuracyPercentage': accuracyPercentage,
      'signalQuality': signalQuality,
      'batteryImpact': batteryImpact,
      'totalLocationPoints': totalLocationPoints,
      'validLocationPoints': validLocationPoints,
    };
  }

  // JSONからの生成
  factory GPSQualityMetrics.fromJson(Map<String, dynamic> json) {
    return GPSQualityMetrics(
      accuracyPercentage: json['accuracyPercentage'].toDouble(),
      signalQuality: json['signalQuality'].toDouble(),
      batteryImpact: json['batteryImpact'].toDouble(),
      totalLocationPoints: json['totalLocationPoints'],
      validLocationPoints: json['validLocationPoints'],
    );
  }
}

/// 位置データポイント
class LocationPoint {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? accuracy; // 精度 (m)
  final double? speed; // 速度 (m/s)

  LocationPoint({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speed,
  });

  // JSONへの変換
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
    };
  }

  // JSONからの生成
  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    return LocationPoint(
      timestamp: DateTime.parse(json['timestamp']),
      latitude: json['latitude'].toDouble(),
      longitude: json['longitude'].toDouble(),
      accuracy: json['accuracy']?.toDouble(),
      speed: json['speed']?.toDouble(),
    );
  }
}

/// メーター値監査ログエントリ
class MileageAuditEntry {
  final String id;
  final String recordId; // 対象のMileageRecord ID
  final DateTime timestamp; // 変更日時
  final AuditAction action; // アクション種別
  final double? oldValue; // 変更前の値
  final double? newValue; // 変更後の値
  final String? userId; // 変更者ID（将来の拡張用）
  final String? deviceInfo; // デバイス情報
  final String? reason; // 変更理由

  MileageAuditEntry({
    required this.id,
    required this.recordId,
    required this.timestamp,
    required this.action,
    this.oldValue,
    this.newValue,
    this.userId,
    this.deviceInfo,
    this.reason,
  });

  // IDを生成
  static String generateId() {
    return 'audit_${DateTime.now().millisecondsSinceEpoch}';
  }

  // JSONへの変換
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'recordId': recordId,
      'timestamp': timestamp.toIso8601String(),
      'action': action.name,
      'oldValue': oldValue,
      'newValue': newValue,
      'userId': userId,
      'deviceInfo': deviceInfo,
      'reason': reason,
    };
  }

  // JSONからの生成
  factory MileageAuditEntry.fromJson(Map<String, dynamic> json) {
    return MileageAuditEntry(
      id: json['id'],
      recordId: json['recordId'],
      timestamp: DateTime.parse(json['timestamp']),
      action: AuditAction.values.firstWhere(
        (e) => e.name == json['action'],
        orElse: () => AuditAction.modify,
      ),
      oldValue: json['oldValue']?.toDouble(),
      newValue: json['newValue']?.toDouble(),
      userId: json['userId'],
      deviceInfo: json['deviceInfo'],
      reason: json['reason'],
    );
  }
}

/// 監査アクション種別
enum AuditAction {
  create, // 新規作成
  modify, // 修正
  delete, // 削除
  gpsStart, // GPS記録開始
  gpsStop, // GPS記録停止
  validate, // 検証実行
}