// PDF期間選択用のダイアログコンポーネント
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum PeriodType { daily, monthly, range }

class PeriodSelection {
  final PeriodType type;
  final DateTime? startDate;
  final DateTime? endDate;

  PeriodSelection({
    required this.type,
    this.startDate,
    this.endDate,
  });

  bool get isValid {
    switch (type) {
      case PeriodType.daily:
        return startDate != null;
      case PeriodType.monthly:
        return startDate != null;
      case PeriodType.range:
        return startDate != null && endDate != null;
    }
  }

  String get displayText {
    final formatter = DateFormat('yyyy/MM/dd');
    switch (type) {
      case PeriodType.daily:
        return startDate != null ? formatter.format(startDate!) : '';
      case PeriodType.monthly:
        return startDate != null ? DateFormat('yyyy年MM月').format(startDate!) : '';
      case PeriodType.range:
        if (startDate != null && endDate != null) {
          return '${formatter.format(startDate!)} 〜 ${formatter.format(endDate!)}';
        }
        return '';
    }
  }
}

class PeriodSelectorDialog extends StatefulWidget {
  final String title;
  final PeriodSelection? initialSelection;

  const PeriodSelectorDialog({
    Key? key,
    this.title = '期間選択',
    this.initialSelection,
  }) : super(key: key);

  @override
  State<PeriodSelectorDialog> createState() => _PeriodSelectorDialogState();
}

class _PeriodSelectorDialogState extends State<PeriodSelectorDialog>
    with TickerProviderStateMixin {
  late TabController _tabController;
  DateTime? _selectedDate;
  DateTime? _startDate;
  DateTime? _endDate;
  PeriodType _currentType = PeriodType.daily;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // 初期値の設定
    if (widget.initialSelection != null) {
      final selection = widget.initialSelection!;
      _currentType = selection.type;
      _selectedDate = selection.startDate;
      _startDate = selection.startDate;
      _endDate = selection.endDate;
      
      // タブの初期位置を設定
      switch (selection.type) {
        case PeriodType.daily:
          _tabController.index = 0;
          break;
        case PeriodType.monthly:
          _tabController.index = 1;
          break;
        case PeriodType.range:
          _tabController.index = 2;
          break;
      }
    }

    _tabController.addListener(() {
      setState(() {
        switch (_tabController.index) {
          case 0:
            _currentType = PeriodType.daily;
            break;
          case 1:
            _currentType = PeriodType.monthly;
            break;
          case 2:
            _currentType = PeriodType.range;
            break;
        }
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  PeriodSelection? get _currentSelection {
    switch (_currentType) {
      case PeriodType.daily:
        return _selectedDate != null
            ? PeriodSelection(type: PeriodType.daily, startDate: _selectedDate)
            : null;
      case PeriodType.monthly:
        return _selectedDate != null
            ? PeriodSelection(type: PeriodType.monthly, startDate: _selectedDate)
            : null;
      case PeriodType.range:
        return (_startDate != null && _endDate != null)
            ? PeriodSelection(
                type: PeriodType.range,
                startDate: _startDate,
                endDate: _endDate,
              )
            : null;
    }
  }

  bool get _isSelectionValid => _currentSelection?.isValid ?? false;

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ja', 'JP'),
    );
    if (date != null) {
      setState(() {
        _selectedDate = date;
      });
    }
  }

  Future<void> _selectMonth() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ja', 'JP'),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (date != null) {
      setState(() {
        // 月の最初の日を設定
        _selectedDate = DateTime(date.year, date.month, 1);
      });
    }
  }

  Future<void> _selectDateRange() async {
    final dateRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: (_startDate != null && _endDate != null)
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      locale: const Locale('ja', 'JP'),
    );
    if (dateRange != null) {
      setState(() {
        _startDate = dateRange.start;
        _endDate = dateRange.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '日別'),
                Tab(text: '月別'),
                Tab(text: '期間指定'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDailySelector(),
                  _buildMonthlySelector(),
                  _buildRangeSelector(),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: _isSelectionValid
              ? () => Navigator.of(context).pop(_currentSelection)
              : null,
          child: const Text('決定'),
        ),
      ],
    );
  }

  Widget _buildDailySelector() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.calendar_today, size: 48, color: Colors.blue),
        const SizedBox(height: 16),
        const Text('出力する日付を選択してください'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _selectDate,
          icon: const Icon(Icons.date_range),
          label: Text(
            _selectedDate != null
                ? DateFormat('yyyy年MM月dd日').format(_selectedDate!)
                : '日付を選択',
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlySelector() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.calendar_view_month, size: 48, color: Colors.green),
        const SizedBox(height: 16),
        const Text('出力する月を選択してください'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _selectMonth,
          icon: const Icon(Icons.date_range),
          label: Text(
            _selectedDate != null
                ? DateFormat('yyyy年MM月').format(_selectedDate!)
                : '月を選択',
          ),
        ),
      ],
    );
  }

  Widget _buildRangeSelector() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.date_range, size: 48, color: Colors.orange),
        const SizedBox(height: 16),
        const Text('出力する期間を選択してください'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _selectDateRange,
          icon: const Icon(Icons.date_range),
          label: Text(
            (_startDate != null && _endDate != null)
                ? '${DateFormat('MM/dd').format(_startDate!)} 〜 ${DateFormat('MM/dd').format(_endDate!)}'
                : '期間を選択',
          ),
        ),
        if (_startDate != null && _endDate != null) ...[
          const SizedBox(height: 8),
          Text(
            '${_endDate!.difference(_startDate!).inDays + 1}日間',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

// 期間選択ダイアログを表示するヘルパー関数
Future<PeriodSelection?> showPeriodSelectorDialog({
  required BuildContext context,
  String title = '期間選択',
  PeriodSelection? initialSelection,
}) {
  return showDialog<PeriodSelection>(
    context: context,
    builder: (context) => PeriodSelectorDialog(
      title: title,
      initialSelection: initialSelection,
    ),
  );
}