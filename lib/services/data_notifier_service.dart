import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// データ変更通知サービス
/// 
/// アプリ全体でデータの変更を監視し、関連する画面に自動更新を通知する
/// ChangeNotifierを使用してリアルタイムなUI更新を実現
class DataNotifierService extends ChangeNotifier {
  static final DataNotifierService _instance = DataNotifierService._internal();
  factory DataNotifierService() => _instance;
  DataNotifierService._internal();

  // 各種データ変更のフラグ
  bool _clientsChanged = false;
  bool _rollCallRecordsChanged = false;
  bool _visitRecordsChanged = false;
  bool _mileageRecordsChanged = false;

  /// 得意先データの変更通知
  void notifyClientsChanged() {
    _clientsChanged = true;
    notifyListeners();
    if (kDebugMode) {
      print('DataNotifier: 得意先データが変更されました');
    }
  }

  /// 点呼記録データの変更通知
  void notifyRollCallRecordsChanged() {
    _rollCallRecordsChanged = true;
    notifyListeners();
    if (kDebugMode) {
      print('DataNotifier: 点呼記録データが変更されました');
    }
  }

  /// 訪問記録データの変更通知
  void notifyVisitRecordsChanged() {
    _visitRecordsChanged = true;
    notifyListeners();
    if (kDebugMode) {
      print('DataNotifier: 訪問記録データが変更されました');
    }
  }

  /// メーター値記録データの変更通知
  void notifyMileageRecordsChanged() {
    _mileageRecordsChanged = true;
    notifyListeners();
    if (kDebugMode) {
      print('DataNotifier: メーター値記録データが変更されました');
    }
  }

  /// 得意先データ変更フラグの確認とリセット
  bool consumeClientsChanged() {
    final changed = _clientsChanged;
    _clientsChanged = false;
    return changed;
  }

  /// 点呼記録データ変更フラグの確認とリセット
  bool consumeRollCallRecordsChanged() {
    final changed = _rollCallRecordsChanged;
    _rollCallRecordsChanged = false;
    return changed;
  }

  /// 訪問記録データ変更フラグの確認とリセット
  bool consumeVisitRecordsChanged() {
    final changed = _visitRecordsChanged;
    _visitRecordsChanged = false;
    return changed;
  }

  /// メーター値記録データ変更フラグの確認とリセット
  bool consumeMileageRecordsChanged() {
    final changed = _mileageRecordsChanged;
    _mileageRecordsChanged = false;
    return changed;
  }

  /// すべての変更フラグをリセット
  void resetAllFlags() {
    _clientsChanged = false;
    _rollCallRecordsChanged = false;
    _visitRecordsChanged = false;
    _mileageRecordsChanged = false;
  }

  /// 現在の変更状態を取得（デバッグ用）
  Map<String, bool> getChangeStatus() {
    return {
      'clients': _clientsChanged,
      'rollCallRecords': _rollCallRecordsChanged,
      'visitRecords': _visitRecordsChanged,
      'mileageRecords': _mileageRecordsChanged,
    };
  }
}

/// DataNotifierServiceを使用するためのMixin
/// 
/// 画面クラスでこのMixinを使用することで、データ変更の監視と
/// 自動更新処理を簡単に実装できる
mixin DataNotifierMixin<T extends StatefulWidget> on State<T> {
  late DataNotifierService _dataNotifier;

  @override
  void initState() {
    super.initState();
    _dataNotifier = DataNotifierService();
    _dataNotifier.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    _dataNotifier.removeListener(_onDataChanged);
    super.dispose();
  }

  /// データ変更時のコールバック
  /// 
  /// 継承先クラスでこのメソッドをオーバーライドして
  /// 具体的な更新処理を実装する
  void _onDataChanged() {
    if (mounted) {
      onDataNotification();
    }
  }

  /// データ通知を受け取った時の処理
  /// 
  /// 継承先クラスでオーバーライドして実装する
  void onDataNotification() {}

  /// DataNotifierServiceのインスタンスを取得
  DataNotifierService get dataNotifier => _dataNotifier;
}