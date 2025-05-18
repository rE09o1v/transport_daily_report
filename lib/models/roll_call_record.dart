class RollCallRecord {
  final String id;
  final DateTime datetime; // 点呼実施日時
  final String type; // 'start' または 'end'（始業点呼または終業点呼）
  final String method; // 点呼方法（'対面' または 'その他'）
  final String? otherMethodDetail; // その他の場合の詳細
  final String inspectorName; // 点呼執行者名
  final bool isAlcoholTestUsed; // アルコール検知器の使用有無
  final bool hasDrunkAlcohol; // 酒気帯びの有無
  final String? remarks; // 備考

  RollCallRecord({
    required this.id,
    required this.datetime,
    required this.type,
    required this.method,
    this.otherMethodDetail,
    required this.inspectorName,
    required this.isAlcoholTestUsed,
    required this.hasDrunkAlcohol,
    this.remarks,
  });

  // 日付の文字列をYYYY-MM-DD形式に正規化
  static String normalizeDate(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  // 新しいIDを生成
  static String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
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
      'remarks': remarks,
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
      remarks: json['remarks'],
    );
  }
} 