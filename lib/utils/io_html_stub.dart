// File APIをエクスポート（dart:ioと同じインターフェイス）
export '../utils/web_file_stub.dart';

// Webブラウザ環境用のモック
class Window {
  final LocalStorage localStorage = LocalStorage();
}

class LocalStorage {
  final Map<String, String> _storage = {};
  
  String? operator [](String key) => _storage[key];
  
  void operator []=(String key, String value) {
    _storage[key] = value;
  }
}

// dart:htmlのWindowオブジェクトのモック
final Window window = Window(); 