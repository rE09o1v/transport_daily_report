class DailyRecord {
  final String date; // ISO8601形式の日付文字列（YYYY-MM-DD）
  final double? startMileage; // 出発時の走行距離
  final double? endMileage; // 帰社時の走行距離
  final double? morningAlcoholValue; // 朝のアルコール検出値
  final double? eveningAlcoholValue; // 夜のアルコール検出値

  DailyRecord({
    required this.date,
    this.startMileage,
    this.endMileage,
    this.morningAlcoholValue,
    this.eveningAlcoholValue,
  });

  // 日付の文字列をYYYY-MM-DD形式に正規化
  static String normalizeDate(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  // 走行距離の差分を計算
  double? get mileageDifference {
    if (startMileage != null && endMileage != null) {
      return endMileage! - startMileage! > 0 ? endMileage! - startMileage! : 0.0;
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'startMileage': startMileage,
      'endMileage': endMileage,
      'morningAlcoholValue': morningAlcoholValue,
      'eveningAlcoholValue': eveningAlcoholValue,
    };
  }

  factory DailyRecord.fromJson(Map<String, dynamic> json) {
    return DailyRecord(
      date: json['date'],
      startMileage: json['startMileage']?.toDouble(),
      endMileage: json['endMileage']?.toDouble(),
      morningAlcoholValue: json['morningAlcoholValue']?.toDouble(),
      eveningAlcoholValue: json['eveningAlcoholValue']?.toDouble(),
    );
  }

  // 今日の日付のインスタンスを作成
  factory DailyRecord.today() {
    final now = DateTime.now();
    return DailyRecord(date: normalizeDate(now));
  }

  // 指定された日付のインスタンスを作成
  factory DailyRecord.forDate(DateTime date) {
    return DailyRecord(date: normalizeDate(date));
  }

  @override
  String toString() {
    return 'DailyRecord(date: $date, startMileage: $startMileage, endMileage: $endMileage, morningAlcoholValue: $morningAlcoholValue, eveningAlcoholValue: $eveningAlcoholValue)';
  }
} 