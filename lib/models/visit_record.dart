class VisitRecord {
  final String id;
  final String clientName;
  final DateTime arrivalTime;
  final String? notes;
  final double? latitude;
  final double? longitude;
  final double? startMileage;  // 出発時の走行距離
  final double? endMileage;    // 帰社時の走行距離

  VisitRecord({
    required this.id,
    required this.clientName,
    required this.arrivalTime,
    this.notes,
    this.latitude,
    this.longitude,
    this.startMileage,
    this.endMileage,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientName': clientName,
      'arrivalTime': arrivalTime.toIso8601String(),
      'notes': notes,
      'latitude': latitude,
      'longitude': longitude,
      'startMileage': startMileage,
      'endMileage': endMileage,
    };
  }

  factory VisitRecord.fromJson(Map<String, dynamic> json) {
    return VisitRecord(
      id: json['id'],
      clientName: json['clientName'],
      arrivalTime: DateTime.parse(json['arrivalTime']),
      notes: json['notes'],
      latitude: json['latitude'],
      longitude: json['longitude'],
      startMileage: json['startMileage']?.toDouble(),
      endMileage: json['endMileage']?.toDouble(),
    );
  }

  @override
  String toString() {
    return 'VisitRecord(id: $id, clientName: $clientName, arrivalTime: $arrivalTime, notes: $notes, latitude: $latitude, longitude: $longitude, startMileage: $startMileage, endMileage: $endMileage)';
  }
} 