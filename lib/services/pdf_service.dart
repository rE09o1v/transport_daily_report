import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:transport_daily_report/models/visit_record.dart';
import 'package:transport_daily_report/models/roll_call_record.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

class PdfService {
  // フォントデータを読み込む
  Future<pw.Font> _loadFont() async {
    try {
      // アセットからIPAexフォントを読み込む
      final fontData = await rootBundle.load('assets/fonts/ipaexg.ttf');
      return pw.Font.ttf(fontData);
    } catch (e) {
      AppLogger.error('フォント読み込みエラー', 'PdfService', e);
      // 代替としてデフォルトフォントを使用
      return pw.Font.helvetica();
    }
  }

  // 保存されている走行距離データを取得
  Future<Map<String, dynamic>> _getMileageData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final startMileage = prefs.getDouble('start_mileage');
      final endMileage = prefs.getDouble('end_mileage');
      final lastUpdateDate = prefs.getString('last_mileage_update_date');
      
      return {
        'startMileage': startMileage,
        'endMileage': endMileage,
        'lastUpdateDate': lastUpdateDate,
      };
    } catch (e) {
      AppLogger.error('走行距離データの取得エラー', 'PdfService', e);
      return {
        'startMileage': null,
        'endMileage': null,
        'lastUpdateDate': null,
      };
    }
  }

  // ストレージ権限を確認・リクエスト
  Future<bool> _requestStoragePermission() async {

  // 期間フィルタリング用のヘルパーメソッド
  Map<DateTime, List<VisitRecord>> filterVisitRecordsByPeriod(
    Map<DateTime, List<VisitRecord>> groupedRecords,
    DateTime startDate,
    DateTime endDate,
  ) {
    final Map<DateTime, List<VisitRecord>> filteredRecords = {};
    
    for (final entry in groupedRecords.entries) {
      final date = entry.key;
      // 日付が範囲内にあるかチェック
      if (date.isAfter(startDate.subtract(const Duration(days: 1))) &&
          date.isBefore(endDate.add(const Duration(days: 1)))) {
        filteredRecords[date] = entry.value;
      }
    }
    
    return filteredRecords;
  }

  Map<DateTime, List<RollCallRecord>> filterRollCallRecordsByPeriod(
    Map<DateTime, List<RollCallRecord>> groupedRecords,
    DateTime startDate,
    DateTime endDate,
  ) {
    final Map<DateTime, List<RollCallRecord>> filteredRecords = {};
    
    for (final entry in groupedRecords.entries) {
      final date = entry.key;
      // 日付が範囲内にあるかチェック
      if (date.isAfter(startDate.subtract(const Duration(days: 1))) &&
          date.isBefore(endDate.add(const Duration(days: 1)))) {
        filteredRecords[date] = entry.value;
      }
    }
    
    return filteredRecords;
  }

  List<VisitRecord> filterVisitRecordsByDate(
    List<VisitRecord> records,
    DateTime targetDate,
  ) {
    return records.where((record) {
      final recordDate = DateTime(
        record.arrivalTime.year,
        record.arrivalTime.month,
        record.arrivalTime.day,
      );
      final target = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
      );
      return recordDate.isAtSameMomentAs(target);
    }).toList();
  }

  List<RollCallRecord> filterRollCallRecordsByDate(
    List<RollCallRecord> records,
    DateTime targetDate,
  ) {
    return records.where((record) {
      final recordDate = DateTime(
        record.datetime.year,
        record.datetime.month,
        record.datetime.day,
      );
      final target = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
      );
      return recordDate.isAtSameMomentAs(target);
    }).toList();
  }

  // 月別フィルタリング
  Map<DateTime, List<VisitRecord>> filterVisitRecordsByMonth(
    Map<DateTime, List<VisitRecord>> groupedRecords,
    DateTime month,
  ) {
    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0);
    return filterVisitRecordsByPeriod(groupedRecords, startOfMonth, endOfMonth);
  }

  Map<DateTime, List<RollCallRecord>> filterRollCallRecordsByMonth(
    Map<DateTime, List<RollCallRecord>> groupedRecords,
    DateTime month,
  ) {
    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0);
    return filterRollCallRecordsByPeriod(groupedRecords, startOfMonth, endOfMonth);
  }
    if (Platform.isAndroid) {
      // Android 13 (API 33)以降は特定のファイル権限が必要
      if (await Permission.manageExternalStorage.request().isGranted) {
        return true;
      }
      
      // Android 10以下はストレージ権限が必要
      if (await Permission.storage.request().isGranted) {
        return true;
      }
      
      // どの権限も取得できなかった場合
      return false;
    }
    return true; // iOSなど他のプラットフォームではtrueを返す
  }

  // 保存先のディレクトリを取得
  Future<Directory> _getOutputDirectory() async {
    try {
      if (Platform.isAndroid) {
        // ストレージ権限を確認
        final hasPermission = await _requestStoragePermission();
        if (!hasPermission) {
          // 権限がなければアプリ固有ディレクトリを使用
          final appDir = await getApplicationDocumentsDirectory();
          final directory = Directory('${appDir.path}/pdfs');
          if (!await directory.exists()) {
            await directory.create(recursive: true);
          }
          return directory;
        }
        
        // Android 11以降(API 30+)はメディアディレクトリのアクセスが制限されるため
        // アプリ固有の外部ストレージディレクトリを使用
        try {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            final directory = Directory('${externalDir.path}/transport_daily_report');
            if (!await directory.exists()) {
              await directory.create(recursive: true);
            }
            return directory;
          }
        } catch (e) {
          AppLogger.error('外部ストレージへのアクセスエラー', 'PdfService', e);
        }
        
        // ダウンロードディレクトリを使用 (古いAndroid向け)
        try {
          final downloadDir = Directory('/storage/emulated/0/Download/transport_daily_report');
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }
          return downloadDir;
        } catch (e) {
          AppLogger.error('ダウンロードディレクトリへのアクセスエラー', 'PdfService', e);
        }
      }
      
      // 上記すべてが失敗したか、iOSの場合はアプリドキュメントディレクトリを使用
      final appDir = await getApplicationDocumentsDirectory();
      final directory = Directory('${appDir.path}/pdfs');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    } catch (e) {
      // 最終手段としてテンポラリディレクトリを使用
      final tempDir = await getTemporaryDirectory();
      final directory = Directory('${tempDir.path}/pdfs');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    }
  }

  // 訪問記録リストからPDFレポートを生成する（単一日付）
  Future<File> generateDailyReport(List<VisitRecord> records, DateTime date) async {
    // 日本語フォントを読み込む
    final font = await _loadFont();
    
    // 走行距離データを取得
    final mileageData = await _getMileageData();
    final startMileage = mileageData['startMileage'];
    final endMileage = mileageData['endMileage'];
    String distanceDiff = '';
    
    // 差分の計算
    if (startMileage != null && endMileage != null) {
      distanceDiff = '${(endMileage - startMileage).toStringAsFixed(1)}km';
    }
    
    // PDF文書を作成
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
      ),
    );
    
    // フォーマッタを準備
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('HH:mm');
    
    // タイトルを表示する日付
    final formattedDate = dateFormatter.format(date);
    
    // 訪問記録を日付でフィルタリング
    final filteredRecords = records.where((record) {
      final recordDate = record.arrivalTime;
      return recordDate.year == date.year && 
             recordDate.month == date.month && 
             recordDate.day == date.day;
    }).toList();
    
    // 訪問時間でソート
    filteredRecords.sort((a, b) => a.arrivalTime.compareTo(b.arrivalTime));

    // PDFページを追加
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ヘッダー
              pw.Center(
                child: pw.Text(
                  '業務日報', 
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
              ),
              
              pw.SizedBox(height: 20),
              
              // 日付表示と走行距離情報
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '日付: ${dateFormatter.format(date)}',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        '出発: ${startMileage?.toStringAsFixed(1) ?? "---"} km',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                      pw.Text(
                        '帰社: ${endMileage?.toStringAsFixed(1) ?? "---"} km',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                      pw.Text(
                        '走行距離: ${distanceDiff.isNotEmpty ? distanceDiff : "---"}',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
              
              pw.SizedBox(height: 15),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text(
                    '作成日: ${dateFormatter.format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
              
              pw.SizedBox(height: 20),
              
              // 訪問記録テーブル
              pw.Table(
                border: pw.TableBorder.all(),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.5), // 訪問時間
                  1: const pw.FlexColumnWidth(3),   // 得意先名
                  2: const pw.FlexColumnWidth(5),   // メモ
                },
                children: [
                  // ヘッダー行
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('訪問時間', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('得意先名', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('メモ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                  // データ行
                  ...filteredRecords.map((record) {
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(timeFormatter.format(record.arrivalTime)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(record.clientName),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(record.notes ?? ''),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              
              pw.SizedBox(height: 20),
              
              // フッター情報
              pw.Text('訪問件数: ${filteredRecords.length}'),
              
              pw.SizedBox(height: 30),
              
              // 備考欄
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(),
                ),
                height: 150,
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('備考：', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    try {
      // 保存先ディレクトリを取得
      final directory = await _getOutputDirectory();
      AppLogger.info('PDFの保存先ディレクトリ: ${directory.path}', 'PdfService');
      
      // ファイル名にはハイフンを使用
      final fileName = 'daily_report_$formattedDate.pdf';
      final filePath = path.join(directory.path, fileName);
      final file = File(filePath);
      
      // PDFファイルを保存
      final pdfBytes = await pdf.save();
      await file.writeAsBytes(pdfBytes);
      
      AppLogger.info('PDFファイルが保存されました: ${file.path}', 'PdfService');
      return file;
    } catch (e) {
      AppLogger.error('PDFファイル生成エラー', 'PdfService', e);
      throw Exception('PDFファイルの生成中にエラーが発生しました: $e');
    }
  }

  // 複数日程の訪問記録からPDFレポートを生成する
  Future<File> generateMultiDayReport(Map<DateTime, List<VisitRecord>> groupedRecords, {String? title}) async {
    // 日本語フォントを読み込む
    final font = await _loadFont();
    
    // 走行距離データを取得
    final mileageData = await _getMileageData();
    final startMileage = mileageData['startMileage'];
    final endMileage = mileageData['endMileage'];
    String distanceDiff = '';
    
    // 差分の計算
    if (startMileage != null && endMileage != null) {
      distanceDiff = '${(endMileage - startMileage).toStringAsFixed(1)}km';
    }
    
    // PDF文書を作成
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
      ),
    );
    
    // フォーマッタを準備
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final dayFormatter = DateFormat('yyyy年MM月dd日(E)', 'ja_JP');
    final timeFormatter = DateFormat('HH:mm');
    
    // 日付を新しい順に並べる
    final sortedDates = groupedRecords.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    // レポートタイトル
    // 未使用変数のためコメントアウト
    // final reportTitle = title ?? '訪問記録レポート';
    // final reportPeriod = sortedDates.isNotEmpty 
    //     ? '${dateFormatter.format(sortedDates.last)} 〜 ${dateFormatter.format(sortedDates.first)}'
    //     : '';

    // 各日付ごとのページ
    for (final date in sortedDates) {
      final recordsForDate = groupedRecords[date]!;
      
      // 訪問時間でソート
      recordsForDate.sort((a, b) => a.arrivalTime.compareTo(b.arrivalTime));
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // タイトルと走行距離情報を並べて表示
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      dayFormatter.format(date), 
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          '出発: ${startMileage?.toStringAsFixed(1) ?? "---"} km',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(
                          '帰社: ${endMileage?.toStringAsFixed(1) ?? "---"} km',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(
                          '走行距離: ${distanceDiff.isNotEmpty ? distanceDiff : "---"}',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
                
                pw.SizedBox(height: 10),
                
                // 作成日表示（右寄せ）
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Text(
                      '作成日: ${dateFormatter.format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
                
                pw.SizedBox(height: 10),
                
                // 訪問記録がない場合
                if (recordsForDate.isEmpty)
                  pw.Text('この日の訪問記録はありません。'),
                  
                // 訪問記録テーブル
                if (recordsForDate.isNotEmpty) 
                  pw.Table(
                    border: pw.TableBorder.all(),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.5), // 訪問時間
                      1: const pw.FlexColumnWidth(3),   // 得意先名
                      2: const pw.FlexColumnWidth(5),   // メモ
                    },
                    children: [
                      // ヘッダー行
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.grey200,
                        ),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text('訪問時間', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text('得意先名', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text('メモ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                        ],
                      ),
                      // データ行
                      ...recordsForDate.map((record) {
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(timeFormatter.format(record.arrivalTime)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(record.clientName),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(record.notes ?? ''),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                
                pw.SizedBox(height: 20),
                
                // フッター
                pw.Text('訪問件数: ${recordsForDate.length}'),
                
                pw.SizedBox(height: 30),
                
                // 備考欄
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(),
                  ),
                  height: 150,
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('備考：', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    try {
      // 保存先ディレクトリを取得
      final directory = await _getOutputDirectory();
      AppLogger.info('PDFの保存先ディレクトリ: ${directory.path}', 'PdfService');
      
      // 日付文字列の生成（ハイフン区切り）
      final startDate = sortedDates.isNotEmpty ? dateFormatter.format(sortedDates.last) : '';
      final endDate = sortedDates.isNotEmpty ? dateFormatter.format(sortedDates.first) : '';
      final fileName = sortedDates.length > 1 
          ? 'visit_report_${startDate}_to_$endDate.pdf' 
          : 'daily_report_$startDate.pdf';
      
      final filePath = path.join(directory.path, fileName);
      final file = File(filePath);
      
      // PDFファイルを保存
      final pdfBytes = await pdf.save();
      await file.writeAsBytes(pdfBytes);
      
      AppLogger.info('PDFファイルが保存されました: ${file.path}', 'PdfService');
      return file;
    } catch (e) {
      AppLogger.error('PDFファイル生成エラー', 'PdfService', e);
      throw Exception('PDFファイルの生成中にエラーが発生しました: $e');
    }
  }
  

  // 単一日付の点呼記録からPDFレポートを生成する
  Future<File> generateRollCallReport(List<RollCallRecord> records, DateTime date) async {
    // 日本語フォントを読み込む
    final font = await _loadFont();
    
    // PDF文書を作成
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
      ),
    );
    
    // フォーマッタを準備
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('HH:mm');
    
    // タイトルを表示する日付
    final formattedDate = dateFormatter.format(date);
    
    // 点呼記録を日付でフィルタリング
    final filteredRecords = records.where((record) {
      final recordDate = record.datetime;
      return recordDate.year == date.year && 
             recordDate.month == date.month && 
             recordDate.day == date.day;
    }).toList();
    
    // 時間でソート
    filteredRecords.sort((a, b) => a.datetime.compareTo(b.datetime));

    // PDFページを追加
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ヘッダー
              pw.Center(
                child: pw.Text(
                  '点呼記録表', 
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
              ),
              
              pw.SizedBox(height: 20),
              
              // 日付表示
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '日付: ${dateFormatter.format(date)}',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              
              pw.SizedBox(height: 15),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text(
                    '作成日: ${dateFormatter.format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
              
              pw.SizedBox(height: 20),
              
              // 点呼記録テーブル
              pw.Table(
                border: pw.TableBorder.all(),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.5), // 点呼種類
                  1: const pw.FlexColumnWidth(1.5), // 点呼時間
                  2: const pw.FlexColumnWidth(2),   // 点呼執行者
                  3: const pw.FlexColumnWidth(1.5), // 点呼方法
                  4: const pw.FlexColumnWidth(1.5), // アルコール検査
                  5: const pw.FlexColumnWidth(1.5), // 酒気帯び
                  6: const pw.FlexColumnWidth(1.5), // アルコール検出値
                },
                children: [
                  // ヘッダー行
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('点呼種類', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('時刻', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('点呼執行者', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('点呼方法', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('アルコール検査', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('酒気帯び', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('検出値', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                  // データ行
                  ...filteredRecords.map((record) {
                    final methodText = record.method == 'その他' && record.otherMethodDetail != null
                        ? '${record.method}(${record.otherMethodDetail})'
                        : record.method;
                    
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(record.type == 'start' ? '始業点呼' : '終業点呼'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(timeFormatter.format(record.datetime)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(record.inspectorName),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(methodText),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(record.isAlcoholTestUsed ? '実施' : '未実施'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(record.hasDrunkAlcohol ? '有' : '無'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(record.alcoholValue != null ? '${record.alcoholValue!.toStringAsFixed(2)} mg/L' : '-'),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              
              pw.SizedBox(height: 20),
              
              // 備考欄
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(),
                ),
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('備考：', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 10),
                    ...filteredRecords.map((record) {
                      if (record.remarks == null || record.remarks!.isEmpty) {
                        return pw.SizedBox.shrink();
                      }
                      
                      return pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('${record.type == 'start' ? '始業点呼' : '終業点呼'} (${timeFormatter.format(record.datetime)}):',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.Text(record.remarks ?? ''),
                          pw.SizedBox(height: 5),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    try {
      // 保存先ディレクトリを取得
      final directory = await _getOutputDirectory();
      AppLogger.info('PDFの保存先ディレクトリ: ${directory.path}', 'PdfService');
      
      // ファイル名にはハイフンを使用
      final fileName = 'roll_call_report_$formattedDate.pdf';
      final filePath = path.join(directory.path, fileName);
      final file = File(filePath);
      
      // PDFファイルを保存
      final pdfBytes = await pdf.save();
      await file.writeAsBytes(pdfBytes);
      
      AppLogger.info('点呼記録PDFファイルが保存されました: ${file.path}', 'PdfService');
      return file;
    } catch (e) {
      AppLogger.error('PDFファイル生成エラー', 'PdfService', e);
      throw Exception('PDFファイルの生成中にエラーが発生しました: $e');
    }
  }

  // 複数日程の点呼記録からPDFレポートを生成する
  Future<File> generateMultiDayRollCallReport(Map<DateTime, List<RollCallRecord>> groupedRecords, {String? title}) async {
    // 日本語フォントを読み込む
    final font = await _loadFont();
    
    // PDF文書を作成
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
      ),
    );
    
    // フォーマッタを準備
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final dayFormatter = DateFormat('yyyy年MM月dd日(E)', 'ja_JP');
    final timeFormatter = DateFormat('HH:mm');
    
    // 日付を新しい順に並べる
    final sortedDates = groupedRecords.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    // レポートタイトル
    // 未使用変数のためコメントアウト
    // final reportTitle = title ?? '点呼記録レポート';
    // final reportPeriod = sortedDates.isNotEmpty 
    //     ? '${dateFormatter.format(sortedDates.last)} 〜 ${dateFormatter.format(sortedDates.first)}'
    //     : '';

    // 各日付ごとのページ
    for (final date in sortedDates) {
      final recordsForDate = groupedRecords[date]!;
      
      // 時間でソート
      recordsForDate.sort((a, b) => a.datetime.compareTo(b.datetime));
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // タイトル
                pw.Text(
                  dayFormatter.format(date), 
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)
                ),
                
                pw.SizedBox(height: 10),
                
                // 作成日表示（右寄せ）
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Text(
                      '作成日: ${dateFormatter.format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
                
                pw.SizedBox(height: 10),
                
                // 点呼記録がない場合
                if (recordsForDate.isEmpty)
                  pw.Text('この日の点呼記録はありません。'),
                  
                // 点呼記録テーブル
                if (recordsForDate.isNotEmpty) 
                  pw.Table(
                    border: pw.TableBorder.all(),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.5), // 点呼種類
                      1: const pw.FlexColumnWidth(1.5), // 点呼時間
                      2: const pw.FlexColumnWidth(2),   // 点呼執行者
                      3: const pw.FlexColumnWidth(1.5), // 点呼方法
                      4: const pw.FlexColumnWidth(1.5), // アルコール検査
                      5: const pw.FlexColumnWidth(1.5), // 酒気帯び
                      6: const pw.FlexColumnWidth(1.5), // アルコール検出値
                    },
                    children: [
                      // ヘッダー行
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.grey200,
                        ),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text('点呼種類', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text('時刻', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text('点呼執行者', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text('点呼方法', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text('アルコール検査', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text('酒気帯び', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text('検出値', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                        ],
                      ),
                      // データ行
                      ...recordsForDate.map((record) {
                        final methodText = record.method == 'その他' && record.otherMethodDetail != null
                          ? '${record.method}(${record.otherMethodDetail})'
                          : record.method;
                          
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(record.type == 'start' ? '始業点呼' : '終業点呼'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(timeFormatter.format(record.datetime)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(record.inspectorName),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(methodText),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(record.isAlcoholTestUsed ? '実施' : '未実施'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(record.hasDrunkAlcohol ? '有' : '無'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(record.alcoholValue != null ? '${record.alcoholValue!.toStringAsFixed(2)} mg/L' : '-'),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                
                pw.SizedBox(height: 20),
                
                // 備考欄
                if (recordsForDate.isNotEmpty) pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(),
                  ),
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('備考：', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 10),
                      ...recordsForDate.map((record) {
                        if (record.remarks == null || record.remarks!.isEmpty) {
                          return pw.SizedBox.shrink();
                        }
                        
                        return pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('${record.type == 'start' ? '始業点呼' : '終業点呼'} (${timeFormatter.format(record.datetime)}):',
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                            pw.Text(record.remarks ?? ''),
                            pw.SizedBox(height: 5),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    try {
      // 保存先ディレクトリを取得
      final directory = await _getOutputDirectory();
      AppLogger.info('PDFの保存先ディレクトリ: ${directory.path}', 'PdfService');
      
      // 日付文字列の生成（ハイフン区切り）
      final startDate = sortedDates.isNotEmpty ? dateFormatter.format(sortedDates.last) : '';
      final endDate = sortedDates.isNotEmpty ? dateFormatter.format(sortedDates.first) : '';
      final fileName = sortedDates.length > 1 
          ? 'roll_call_report_${startDate}_to_$endDate.pdf' 
          : 'roll_call_report_$startDate.pdf';
      
      final filePath = path.join(directory.path, fileName);
      final file = File(filePath);
      
      // PDFファイルを保存
      final pdfBytes = await pdf.save();
      await file.writeAsBytes(pdfBytes);
      
      AppLogger.info('点呼記録PDFファイルが保存されました: ${file.path}', 'PdfService');
      return file;
    } catch (e) {
      AppLogger.error('PDFファイル生成エラー', 'PdfService', e);
      throw Exception('PDFファイルの生成中にエラーが発生しました: $e');
    }
  }

  // 複数日程の点呼記録を1枚にまとめたPDFレポートを生成する
  Future<File> generateCombinedRollCallReport(Map<DateTime, List<RollCallRecord>> groupedRecords, {String? title}) async {
    if (groupedRecords.isEmpty) {
      throw Exception('点呼記録がありません');
    }

    // 最初の日付の記録を使用する（単一日付でない場合は最も古い日付）
    final sortedDates = groupedRecords.keys.toList()..sort();
    final firstDate = sortedDates.first;
    final allRecords = groupedRecords.values.expand((records) => records).toList();
    
    // 既存の単一日付レポート生成メソッドを使用
    return generateRollCallReport(allRecords, firstDate);
  }

  // 訪問記録のフィルタヘルパーメソッド
  Map<DateTime, List<VisitRecord>> _filterVisitRecordsByPeriod(
    Map<DateTime, List<VisitRecord>> allRecords,
    DateTime startDate,
    DateTime endDate,
  ) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    
    final filtered = <DateTime, List<VisitRecord>>{};
    
    allRecords.forEach((date, records) {
      if (date.isAfter(start.subtract(const Duration(days: 1))) &&
          date.isBefore(end.add(const Duration(days: 1)))) {
        filtered[date] = records;
      }
    });
    
    return filtered;
  }

  Map<DateTime, List<VisitRecord>> _filterVisitRecordsByMonth(
    Map<DateTime, List<VisitRecord>> allRecords,
    DateTime month,
  ) {
    final filtered = <DateTime, List<VisitRecord>>{};
    
    allRecords.forEach((date, records) {
      if (date.year == month.year && date.month == month.month) {
        filtered[date] = records;
      }
    });
    
    return filtered;
  }

  // 点呼記録のフィルタヘルパーメソッド
  Map<DateTime, List<RollCallRecord>> _filterRollCallRecordsByPeriod(
    Map<DateTime, List<RollCallRecord>> allRecords,
    DateTime startDate,
    DateTime endDate,
  ) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    
    final filtered = <DateTime, List<RollCallRecord>>{};
    
    allRecords.forEach((date, records) {
      if (date.isAfter(start.subtract(const Duration(days: 1))) &&
          date.isBefore(end.add(const Duration(days: 1)))) {
        filtered[date] = records;
      }
    });
    
    return filtered;
  }

  Map<DateTime, List<RollCallRecord>> _filterRollCallRecordsByMonth(
    Map<DateTime, List<RollCallRecord>> allRecords,
    DateTime month,
  ) {
    final filtered = <DateTime, List<RollCallRecord>>{};
    
    allRecords.forEach((date, records) {
      if (date.year == month.year && date.month == month.month) {
        filtered[date] = records;
      }
    });
    
    return filtered;
  }

  // 期間指定対応のPDF生成メソッド
  Future<File> generatePeriodVisitReport(
    Map<DateTime, List<VisitRecord>> allRecords,
    DateTime startDate,
    DateTime endDate, {
    String? title,
  }) async {
    final filteredRecords = _filterVisitRecordsByPeriod(allRecords, startDate, endDate);
    return generateMultiDayReport(filteredRecords, title: title ?? '訪問記録 ${DateFormat('yyyy/MM/dd').format(startDate)} - ${DateFormat('yyyy/MM/dd').format(endDate)}');
  }

  Future<File> generateDailyVisitReport(
    Map<DateTime, List<VisitRecord>> allRecords,
    DateTime date, {
    String? title,
  }) async {
    final targetDate = DateTime(date.year, date.month, date.day);
    final records = allRecords[targetDate] ?? [];
    return generateDailyReport(records, date);
  }

  Future<File> generateMonthlyVisitReport(
    Map<DateTime, List<VisitRecord>> allRecords,
    DateTime month, {
    String? title,
  }) async {
    final filteredRecords = _filterVisitRecordsByMonth(allRecords, month);
    return generateMultiDayReport(filteredRecords, title: title);
  }

  Future<File> generatePeriodRollCallReport(
    Map<DateTime, List<RollCallRecord>> allRecords,
    DateTime startDate,
    DateTime endDate, {
    String? title,
  }) async {
    final filteredRecords = _filterRollCallRecordsByPeriod(allRecords, startDate, endDate);
    return generateCombinedRollCallReport(filteredRecords, title: title);
  }

  Future<File> generateDailyRollCallReport(
    Map<DateTime, List<RollCallRecord>> allRecords,
    DateTime date, {
    String? title,
  }) async {
    final targetDate = DateTime(date.year, date.month, date.day);
    final records = allRecords[targetDate] ?? [];
    
    final filteredRecords = <DateTime, List<RollCallRecord>>{targetDate: records};
    return generateCombinedRollCallReport(filteredRecords, title: title);
  }

  Future<File> generateMonthlyRollCallReport(
    Map<DateTime, List<RollCallRecord>> allRecords,
    DateTime month, {
    String? title,
  }) async {
    final filteredRecords = _filterRollCallRecordsByMonth(allRecords, month);
    return generateCombinedRollCallReport(filteredRecords, title: title);
  }
}

