import 'package:latlong2/latlong.dart';

/// Pure-Dart controller for the location picker flow.
///
/// Kept independent from any map widget (flutter_map / google_maps_flutter)
/// so it can be unit-tested.
class LocationSelectionController {
  LatLng _currentCenter;

  LocationSelectionController({LatLng? initialCenter, LatLng? defaultCenter})
      : _currentCenter = initialCenter ??
            defaultCenter ??
            const LatLng(35.6812, 139.7671); // Tokyo station

  LatLng get currentCenter => _currentCenter;

  void updateCenter(LatLng newCenter) {
    _currentCenter = newCenter;
  }

  LatLng confirm() => _currentCenter;
}
