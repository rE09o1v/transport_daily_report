class VisitRecord {
  final String id;
  final String clientName;
  final DateTime arrivalTime;
  final String? notes;
  final double? latitude;
  final double? longitude;

  VisitRecord({
    required this.id,
    required this.clientName,
    required this.arrivalTime,
    this.notes,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientName': clientName,
      'arrivalTime': arrivalTime.toIso8601String(),
      'notes': notes,
      'latitude': latitude,
      'longitude': longitude,
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
    );
  }

  @override
  String toString() {
    return 'VisitRecord(id: $id, clientName: $clientName, arrivalTime: $arrivalTime, notes: $notes, latitude: $latitude, longitude: $longitude)';
  }
} 