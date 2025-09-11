import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:transport_daily_report/models/client.dart';

class LocationService {
  // 移動距離計測用の変数
  double _totalDistance = 0.0;
  Position? _lastPosition;
  StreamSubscription<Position>? _positionStream;
  DateTime? _trackingStartTime;
  
  // 距離計測状態の監視用
  final StreamController<double> _distanceController = StreamController<double>.broadcast();
  Stream<double> get distanceStream => _distanceController.stream;
  
  // 現在の総移動距離を取得
  double get totalDistance => _totalDistance;
  
  // 距離計測が実行中かどうか
  bool get isTracking => _positionStream != null;

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

  // 移動距離の追跡を開始
  Future<bool> startDistanceTracking() async {
    try {
      final hasPermission = await checkLocationPermission();
      if (!hasPermission) {
        return false;
      }

      // 既にトラッキング中の場合は停止してから開始
      if (_positionStream != null) {
        await stopDistanceTracking();
      }

      // 初期化
      _totalDistance = 0.0;
      _lastPosition = null;
      _trackingStartTime = DateTime.now();

      // 位置情報のストリームを開始（高精度、10秒間隔）
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // 5メートル移動したら更新
        ),
      ).listen(
        (Position position) {
          _updateDistance(position);
        },
        onError: (error) {
          print('Error in distance tracking: $error');
        },
      );

      return true;
    } catch (e) {
      print('Error starting distance tracking: $e');
      return false;
    }
  }

  // 移動距離の追跡を停止
  Future<void> stopDistanceTracking() async {
    await _positionStream?.cancel();
    _positionStream = null;
    print('Distance tracking stopped. Total distance: ${_totalDistance.toStringAsFixed(2)}m');
  }

  // 移動距離をリセット
  void resetDistance() {
    _totalDistance = 0.0;
    _lastPosition = null;
    _trackingStartTime = DateTime.now();
    _distanceController.add(_totalDistance);
    print('Distance tracking reset');
  }

  // 位置情報が更新された際の距離計算
  void _updateDistance(Position newPosition) {
    if (_lastPosition != null) {
      final distance = calculateDistance(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        newPosition.latitude,
        newPosition.longitude,
      );
      
      // 現実的でない距離の変化（例：100m/秒以上）を除外
      final timeElapsed = newPosition.timestamp != null && _lastPosition!.timestamp != null
          ? newPosition.timestamp!.difference(_lastPosition!.timestamp!).inSeconds
          : 1;
      
      if (timeElapsed > 0 && distance / timeElapsed < 100) { // 360km/h以下
        _totalDistance += distance;
        _distanceController.add(_totalDistance);
        print('Distance updated: +${distance.toStringAsFixed(2)}m, Total: ${_totalDistance.toStringAsFixed(2)}m');
      }
    }
    _lastPosition = newPosition;
  }

  // リソースの解放
  void dispose() {
    _positionStream?.cancel();
    _distanceController.close();
  }
} 