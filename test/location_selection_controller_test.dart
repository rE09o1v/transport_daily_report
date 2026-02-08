import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:transport_daily_report/models/location_selection_controller.dart';

void main() {
  test('uses default center when initial is null', () {
    final c = LocationSelectionController();
    expect(c.currentCenter.latitude, closeTo(35.6812, 1e-6));
    expect(c.currentCenter.longitude, closeTo(139.7671, 1e-6));
  });

  test('uses initial center when provided', () {
    final init = LatLng(1.0, 2.0);
    final c = LocationSelectionController(initialCenter: init);
    expect(c.currentCenter, init);
  });

  test('updateCenter updates currentCenter and confirm returns it', () {
    final c = LocationSelectionController(initialCenter: LatLng(1.0, 2.0));
    c.updateCenter(LatLng(3.0, 4.0));
    expect(c.confirm(), LatLng(3.0, 4.0));
  });
}
