import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../models/location_selection_controller.dart';

class LocationMapPickerScreen extends StatefulWidget {
  final LatLng? initialPosition;

  /// For tests / advanced usage. If omitted, screen creates its own controller.
  final LocationSelectionController? controller;

  const LocationMapPickerScreen({
    super.key,
    this.initialPosition,
    this.controller,
  });

  @override
  State<LocationMapPickerScreen> createState() => _LocationMapPickerScreenState();
}

class _LocationMapPickerScreenState extends State<LocationMapPickerScreen> {
  // NOTE: Old flutter_map controller kept until migration is completed.
  late MapController _mapController;

  gmaps.GoogleMapController? _googleMapController;
  late LocationSelectionController _controller;
  bool _isLoading = true;
  bool _hasMapError = false;
  String? _errorMessage;

  // デフォルト位置: 東京駅
  static const LatLng _defaultPosition = LatLng(35.6812, 139.7671);

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    try {
      _mapController = MapController();
      _controller = widget.controller ?? LocationSelectionController(
        initialCenter: widget.initialPosition,
        defaultCenter: _defaultPosition,
      );
      
      // 初期化完了まで少し待つ
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasMapError = false;
        });
      }
    } catch (e) {
      debugPrint('マップ初期化エラー: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasMapError = true;
          _errorMessage = 'マップの読み込みに失敗しました: ${e.toString()}';
        });
      }
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _googleMapController?.dispose();
    super.dispose();
  }

  // マップの中心座標が変更された際のコールバック
  void _onMapPositionChanged(MapCamera position, bool hasGesture) {
    if (hasGesture) {
      setState(() {
        _controller.updateCenter(position.center);
      });
    }
  }

  // 決定ボタンが押された際の処理
  void _confirmLocation() {
    Navigator.of(context).pop(_controller.confirm());
  }

  // キャンセルボタンが押された際の処理
  void _cancelSelection() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('位置を選択'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _cancelSelection,
        ),
        actions: [
          TextButton.icon(
            onPressed: _confirmLocation,
            icon: const Icon(Icons.check, color: Colors.white),
            label: const Text('決定', style: TextStyle(color: Colors.white)),
          ),
        ],
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('地図を読み込み中...'),
                ],
              ),
            )
          : _hasMapError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'マップの読み込みに失敗しました',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage ?? '不明なエラーが発生しました',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _isLoading = true;
                            });
                            _initializeMap();
                          },
                          child: const Text('再試行'),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
              children: [
                // メイン地図（Google Maps）
                gmaps.GoogleMap(
                  initialCameraPosition: gmaps.CameraPosition(
                    target: gmaps.LatLng(
                      _controller.currentCenter.latitude,
                      _controller.currentCenter.longitude,
                    ),
                    zoom: 15.0,
                  ),
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  onMapCreated: (c) {
                    _googleMapController = c;
                  },
                  onCameraMove: (pos) {
                    _controller.updateCenter(LatLng(pos.target.latitude, pos.target.longitude));
                  },
                ),
                
                // 中央の固定ピン
                Center(
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
                
                // 座標情報表示パネル
                Positioned(
                  bottom: 80,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '選択中の位置',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '緯度: ${_controller.currentCenter.latitude.toStringAsFixed(6)}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          '経度: ${_controller.currentCenter.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // 操作ボタン
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _cancelSelection,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('キャンセル'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _confirmLocation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('この位置を選択'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}