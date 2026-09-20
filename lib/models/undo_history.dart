/// 제네릭 실행 취소(Undo)/다시 실행(Redo) 히스토리.
///
/// 불변(immutable) 객체의 스냅샷을 여러 단계 저장해 두고 되돌리는 용도에 적합하다.
class UndoHistory<T> {
  UndoHistory({
    this.capacity = 100,
    this.coalesceInterval = const Duration(milliseconds: 350),
  }) : assert(capacity > 0);

  /// 보관할 최대 단계 수 (초과 시 가장 오래된 항목이 제거된다).
  final int capacity;

  /// 이 간격 안에 연속으로 기록되는 변경은 하나의 단계로 합쳐진다.
  ///
  /// 캔버스 드래그처럼 짧은 시간에 미세한 변경이 연달아 발생하는 경우
  /// Undo 스택이 지나치게 쌓이는 것을 방지한다.
  final Duration coalesceInterval;

  final List<T> _undoStack = [];
  final List<T> _redoStack = [];
  DateTime? _lastRecordAt;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// [current]를 "되돌아갈 수 있는 이전 상태"로 기록한다.
  ///
  /// 호출 시점의 상태가 [current]인데, 그 다음 상태로 변경되는 상황에서
  /// 변경 직전에 호출하면 된다. redo 스택은 비워진다.
  void record(T current) {
    final now = DateTime.now();
    final coalescing =
        _lastRecordAt != null &&
        _undoStack.isNotEmpty &&
        now.difference(_lastRecordAt!) < coalesceInterval;
    if (!coalescing) {
      _undoStack.add(current);
      if (_undoStack.length > capacity) {
        _undoStack.removeAt(0);
      }
    }
    _lastRecordAt = now;
    _redoStack.clear();
  }

  /// 한 단계 실행 취소한다. [current]는 현재 상태로, redo를 위해 보관한다.
  ///
  /// 되돌아갈 항목이 없으면 null을 반환한다.
  T? undo(T current) {
    if (_undoStack.isEmpty) return null;
    _redoStack.add(current);
    _lastRecordAt = null;
    return _undoStack.removeLast();
  }

  /// 한 단계 다시 실행한다. [current]는 현재 상태로, undo를 위해 보관한다.
  ///
  /// 다시 실행할 항목이 없으면 null을 반환한다.
  T? redo(T current) {
    if (_redoStack.isEmpty) return null;
    _undoStack.add(current);
    if (_undoStack.length > capacity) {
      _undoStack.removeAt(0);
    }
    _lastRecordAt = null;
    return _redoStack.removeLast();
  }

  /// 기록을 모두 비운다. (새 이미지 로드 등으로 이전 기록이 무의미해질 때)
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _lastRecordAt = null;
  }
}
