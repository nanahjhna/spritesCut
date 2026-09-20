import 'package:flutter_test/flutter_test.dart';
import 'package:spritescut/models/undo_history.dart';

void main() {
  group('UndoHistory', () {
    test('record 후 undo로 직전 상태로 복원된다', () {
      final h = UndoHistory<int>(coalesceInterval: Duration.zero);
      h.record(1);
      h.record(2);
      expect(h.canUndo, isTrue);
      expect(h.undo(3), 2);
      expect(h.undo(2), 1);
      expect(h.canUndo, isFalse);
      expect(h.undo(1), isNull);
    });

    test('redo로 되돌린 변경을 다시 적용한다', () {
      final h = UndoHistory<int>(coalesceInterval: Duration.zero);
      h.record(1);
      h.record(2);
      // 현재 상태 3에서 과거 상태 2 → 1로 차례로 되돌아간다.
      expect(h.undo(3), 2);
      expect(h.undo(2), 1);
      expect(h.canRedo, isTrue);
      // 다시 실행하면 2 → 3으로 앞으로 돌아간다.
      expect(h.redo(1), 2);
      expect(h.redo(2), 3);
      expect(h.canRedo, isFalse);
      expect(h.redo(3), isNull);
    });

    test('새로 기록하면 redo 스택이 비워진다', () {
      final h = UndoHistory<int>(coalesceInterval: Duration.zero);
      h.record(1);
      h.record(2);
      h.undo(2);
      expect(h.canRedo, isTrue);
      h.record(3);
      expect(h.canRedo, isFalse);
    });

    test('capacity 초과 시 가장 오래된 항목이 제거된다', () {
      final h = UndoHistory<int>(capacity: 2, coalesceInterval: Duration.zero);
      h.record(1);
      h.record(2);
      h.record(3);
      h.record(4);
      // 기록은 "이전 상태"를 저장하므로 1, 2는 제거되고 3, 4만 남는다.
      expect(h.undo(99), 4);
      expect(h.undo(4), 3);
      expect(h.undo(3), isNull);
    });

    test('짧은 시간 안의 연속 변경은 하나의 단계로 합쳐진다', () {
      final h = UndoHistory<int>(coalesceInterval: const Duration(seconds: 1));
      // 드래그처럼 연속으로 발생한 변경: A(10)→B(11)→C(12)
      h.record(10);
      h.record(11);
      h.record(12);
      expect(h.canUndo, isTrue);
      // 한 번의 undo로 첫 기록 상태(10)로 돌아간다.
      expect(h.undo(12), 10);
      expect(h.canUndo, isFalse);
    });

    test('합쳐진 기록 후 redo는 가능하다', () {
      final h = UndoHistory<int>(coalesceInterval: const Duration(seconds: 1));
      h.record(10);
      h.record(11);
      h.record(12);
      expect(h.undo(12), 10);
      expect(h.redo(10), 12);
      expect(h.undo(12), 10);
    });

    test('clear 후에는 모든 기록이 사라진다', () {
      final h = UndoHistory<int>(coalesceInterval: Duration.zero);
      h.record(1);
      h.record(2);
      h.undo(2);
      h.clear();
      expect(h.canUndo, isFalse);
      expect(h.canRedo, isFalse);
      expect(h.undo(2), isNull);
      expect(h.redo(1), isNull);
    });
  });
}
