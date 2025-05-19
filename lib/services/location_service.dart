import 'package:geolocator/geolocator.dart';
import 'package:transport_daily_report/models/client.dart';

class LocationService {
  // 位置情報のパーミッション取得とチェック
  Future<bool> checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 位置情報サービスが有効かどうかチェック
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    // 位置情報の権限をチェック
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  // 現在の位置情報を取得
  Future<Position?> getCurrentLocation() async {
    try {
      final hasPermission = await checkLocationPermission();
      if (!hasPermission) {
        return null;
      }

      return await Geolocator.getCurrentPosition();
    } catch (e) {
      print('Error getting current location: $e');
      return null;
    }
  }

  // 2つの位置情報間の距離を計算（メートル単位）
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  // 現在位置から近い顧客を検索（指定した距離内）
  Future<List<Client>> findNearbyClients(
      List<Client> allClients, {double maxDistanceInMeters = 300}) async {
    final currentPosition = await getCurrentLocation();
    if (currentPosition == null) {
      return [];
    }

    return allClients.where((client) {
      // 緯度経度がnullでないクライアントだけチェック
      if (client.latitude == null || client.longitude == null) {
        return false;
      }

      final distance = calculateDistance(
        currentPosition.latitude,
        currentPosition.longitude,
        client.latitude!,
        client.longitude!,
      );

      return distance <= maxDistanceInMeters;
    }).toList();
  }
} 