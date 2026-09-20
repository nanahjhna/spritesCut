import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'image_canvas.dart' show CheckerboardPainter;

/// 저장 전 프레임 검토 팝업.
///
/// - 잘라낸 모든 컷을 체커보드 위 그리드로 표시 (투명 확인용)
/// - 사진을 탭하면 삭제 버튼이 표시되고, 누르면 해당 컷을 삭제
/// - 삭제 시 파일명 번호를 연속으로 재배열한다
/// - "다운로드 (ZIP)" 버튼으로 남은 프레임 목록을 반환한다 (취소 시 null).
class SavePreviewDialog extends StatefulWidget {
  const SavePreviewDialog({
    super.key,
    required this.baseName,
    required this.frames,
    required this.sizes,
  });

  /// 프레임 재명명에 사용되는 ZIP 기본 이름 (예: `dino_4_2`).
  final String baseName;

  /// 프레임별 PNG 바이트와 파일명 (첫 노출 순서대로).
  final List<({String name, Uint8List bytes})> frames;

  /// 프레임별 실제 크기 (sizes[i] ↔ frames[i]).
  final List<({int w, int h})> sizes;

  @override
  State<SavePreviewDialog> createState() => _SavePreviewDialogState();
}

class _SavePreviewDialogState extends State<SavePreviewDialog> {
  late final List<({String name, Uint8List bytes})> _frames = [
    ...widget.frames,
  ];
  late final List<({int w, int h})> _sizes = [...widget.sizes];

  /// 삭제 버튼이 표시 중인 타일 인덱스.
  final Set<int> _marked = {};

  void _toggleMark(int index) {
    setState(() {
      if (!_marked.remove(index)) _marked.add(index);
    });
  }

  void _delete(int index) {
    setState(() {
      _frames.removeAt(index);
      _sizes.removeAt(index);

      // 삭제로 밀린 뒤의 표시 상태 재정렬
      _marked.remove(index);
      final shifted = <int>{};
      for (final m in _marked) {
        shifted.add(m > index ? m - 1 : m);
      }
      _marked
        ..clear()
        ..addAll(shifted);

      // 연속 번호로 재배열
      for (var i = 0; i < _frames.length; i++) {
        _frames[i] = (
          name: '${widget.baseName}_${i + 1}.png',
          bytes: _frames[i].bytes,
        );
      }
    });
  }

  void _confirm() {
    Navigator.of(context).pop(_frames);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _frames.length;
    final removedCount = widget.frames.length - total;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 헤더 ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.photo_library_outlined, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '저장할 스프라이트 미리보기',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '$total컷',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (removedCount > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(삭제 $removedCount)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.red[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: '닫기',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── 프레임 그리드 ───────────────────────────────
            Expanded(
              child: total == 0
                  ? Center(
                      child: Text(
                        '남은 프레임이 없습니다.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 160,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.0,
                          ),
                      itemCount: total,
                      itemBuilder: (context, i) => _buildTile(i, theme),
                    ),
            ),

            // ── 하단 바 ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      total == 0
                          ? '삭제를 취소하려면 아래 버튼을 눌러 주세요.'
                          : '사진을 누르면 삭제할 수 있어요.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: total == 0 ? null : _confirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.download),
                    label: const Text('다운로드 (ZIP)'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(int index, ThemeData theme) {
    final frame = _frames[index];
    final size = index < _sizes.length ? _sizes[index] : null;
    final marked = _marked.contains(index);

    return InkWell(
      key: ValueKey('tile-$index'),
      onTap: () => _toggleMark(index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: marked ? Colors.red.shade400 : Colors.grey.shade400,
            width: marked ? 2.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const CustomPaint(
                    painter: CheckerboardPainter(squareSize: 8),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Image.memory(
                      frame.bytes,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.none,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined, size: 40),
                    ),
                  ),
                  if (marked)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.45),
                        child: Center(
                          child: GestureDetector(
                            key: ValueKey('delete-$index'),
                            onTap: () => _delete(index),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red[600],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    '삭제',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              color: marked
                  ? Colors.red.shade50
                  : Colors.black.withValues(alpha: 0.06),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                size == null
                    ? frame.name
                    : '${frame.name} · ${size.w}×${size.h}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
