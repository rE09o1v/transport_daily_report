class VisitRecord {
  final String id;
  final String clientId;
  final String clientName;
  final DateTime arrivalTime;
  final String? notes;

  VisitRecord({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.arrivalTime,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientId': clientId,
      'clientName': clientName,
      'arrivalTime': arrivalTime.toIso8601String(),
      'notes': notes,
    };
  }

  factory VisitRecord.fromJson(Map<String, dynamic> json) {
    return VisitRecord(
      id: json['id'],
      clientId: json['clientId'] ?? '', // 既存データとの互換性のためデフォルト値
      clientName: json['clientName'],
      arrivalTime: DateTime.parse(json['arrivalTime']),
      notes: json['notes'],
    );
  }

  @override
  String toString() {
    return 'VisitRecord(id: $id, clientId: $clientId, clientName: $clientName, arrivalTime: $arrivalTime, notes: $notes)';
  }
} 