// Web環境用のFileクラスのモック
class File {
  final String path;
  
  File(this.path);
  
  Future<bool> exists() async => false;
  
  Future<String> readAsString() async => '';
  
  Future<void> writeAsString(String contents) async {}
} 