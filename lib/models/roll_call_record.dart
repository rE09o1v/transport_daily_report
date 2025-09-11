class RollCallRecord {
  final String id;
  final DateTime datetime; // 点呼実施日時
  final String type; // 'start' または 'end'（始業点呼または終業点呼）
  final String method; // 点呼方法（'対面' または 'その他'）
  final String? otherMethodDetail; // その他の場合の詳細
  final String inspectorName; // 点呼執行者名
  final bool isAlcoholTestUsed; // アルコール検知器の使用有無
  final bool hasDrunkAlcohol; // 酒気帯びの有無
  final double? alcoholValue; // アルコール検出量（mg/L）
  final String? remarks; // 備考
  
  // メーター値関連フィールド
  final double? startMileage; // 開始時メーター値 (km)
  final double? endMileage; // 終了時メーター値 (km)
  final double? calculatedDistance; // 算出された走行距離 (km)
  final bool gpsTrackingEnabled; // GPS記録が有効かどうか
  final String? gpsTrackingId; // GPS記録の識別ID
  final List<String> mileageValidationFlags; // メーター値検証フラグ

  RollCallRecord({
    required this.id,
    required this.datetime,
    required this.type,
    required this.method,
    this.otherMethodDetail,
    required this.inspectorName,
    required this.isAlcoholTestUsed,
    required this.hasDrunkAlcohol,
    this.alcoholValue,
    this.remarks,
    // メーター値関連パラメータ
    this.startMileage,
    this.endMileage,
    this.calculatedDistance,
    this.gpsTrackingEnabled = false,
    this.gpsTrackingId,
    this.mileageValidationFlags = const [],
  });

  // 走行距離を取得（終了-開始メーター値、またはGPS算出値）
  double? get totalDistance {
    if (startMileage != null && endMileage != null) {
      return endMileage! - startMileage!;
    }
    return calculatedDistance;
  }

  // メーター値データが完全かどうかを確認
  bool get isMileageDataComplete {
    return startMileage != null && 
           (endMileage != null || (gpsTrackingEnabled && calculatedDistance != null));
  }

  // 日付の文字列をYYYY-MM-DD形式に正規化
  static String normalizeDate(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  // 新しいIDを生成
  static String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  // コピーファクトリメソッド（メーター値更新用）
  RollCallRecord copyWith({
    String? id,
    DateTime? datetime,
    String? type,
    String? method,
    String? otherMethodDetail,
    String? inspectorName,
    bool? isAlcoholTestUsed,
    bool? hasDrunkAlcohol,
    double? alcoholValue,
    String? remarks,
    double? startMileage,
    double? endMileage,
    double? calculatedDistance,
    bool? gpsTrackingEnabled,
    String? gpsTrackingId,
    List<String>? mileageValidationFlags,
  }) {
    return RollCallRecord(
      id: id ?? this.id,
      datetime: datetime ?? this.datetime,
      type: type ?? this.type,
      method: method ?? this.method,
      otherMethodDetail: otherMethodDetail ?? this.otherMethodDetail,
      inspectorName: inspectorName ?? this.inspectorName,
      isAlcoholTestUsed: isAlcoholTestUsed ?? this.isAlcoholTestUsed,
      hasDrunkAlcohol: hasDrunkAlcohol ?? this.hasDrunkAlcohol,
      alcoholValue: alcoholValue ?? this.alcoholValue,
      remarks: remarks ?? this.remarks,
      startMileage: startMileage ?? this.startMileage,
      endMileage: endMileage ?? this.endMileage,
      calculatedDistance: calculatedDistance ?? this.calculatedDistance,
      gpsTrackingEnabled: gpsTrackingEnabled ?? this.gpsTrackingEnabled,
      gpsTrackingId: gpsTrackingId ?? this.gpsTrackingId,
      mileageValidationFlags: mileageValidationFlags ?? this.mileageValidationFlags,
    );
  }

  // JSONへの変換
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'datetime': datetime.toIso8601String(),
      'type': type,
      'method': method,
      'otherMethodDetail': otherMethodDetail,
      'inspectorName': inspectorName,
      'isAlcoholTestUsed': isAlcoholTestUsed,
      'hasDrunkAlcohol': hasDrunkAlcohol,
      'alcoholValue': alcoholValue,
      'remarks': remarks,
      // メーター値関連フィールド
      'startMileage': startMileage,
      'endMileage': endMileage,
      'calculatedDistance': calculatedDistance,
      'gpsTrackingEnabled': gpsTrackingEnabled,
      'gpsTrackingId': gpsTrackingId,
      'mileageValidationFlags': mileageValidationFlags,
    };
  }

  // JSONからの生成
  factory RollCallRecord.fromJson(Map<String, dynamic> json) {
    return RollCallRecord(
      id: json['id'],
      datetime: DateTime.parse(json['datetime']),
      type: json['type'],
      method: json['method'] ?? '対面', // 既存データ互換性のため
      otherMethodDetail: json['otherMethodDetail'],
      inspectorName: json['inspectorName'],
      isAlcoholTestUsed: json['isAlcoholTestUsed'] ?? true, // 既存データ互換性のため
      hasDrunkAlcohol: json['hasDrunkAlcohol'] ?? false, // 既存データ互換性のため
      alcoholValue: json['alcoholValue']?.toDouble(),
      remarks: json['remarks'],
      // メーター値関連フィールド（既存データ互換性のため）
      startMileage: json['startMileage']?.toDouble(),
      endMileage: json['endMileage']?.toDouble(),
      calculatedDistance: json['calculatedDistance']?.toDouble(),
      gpsTrackingEnabled: json['gpsTrackingEnabled'] ?? false,
      gpsTrackingId: json['gpsTrackingId'],
      mileageValidationFlags: List<String>.from(json['mileageValidationFlags'] ?? []),
    );
  }
}