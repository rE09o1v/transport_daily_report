
class Client {
  final String id;
  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? phoneNumber;

  Client({
    required this.id,
    required this.name,
    this.address,
    this.latitude,
    this.longitude,
    this.phoneNumber,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'phoneNumber': phoneNumber,
    };
  }

  factory Client.fromJson(Map<String, dynamic> json) {
    return Client(
      id: json['id'],
      name: json['name'],
      address: json['address'],
      latitude: json['latitude'],
      longitude: json['longitude'],
      phoneNumber: json['phoneNumber'],
    );
  }

  @override
  String toString() {
    return 'Client(id: $id, name: $name, address: $address, latitude: $latitude, longitude: $longitude, phoneNumber: $phoneNumber)';
  }
} 