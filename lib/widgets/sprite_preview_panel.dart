import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/crop_settings.dart';
import 'image_canvas.dart' show CheckerboardPainter;

/// 잘라낸 결과물 프레임들을 실시간으로 보여주는 하단 미리보기 패널.
///
/// - 체커보드 배경 위에 프레임 썸네일을 그리드로 표시 (투명 확인용)
/// - 썸네일 클릭 시 해당 프레임을 선택해 개별 크롭 편집 모드로 전환
/// - 선택된 프레임은 x/y/w/h 숫자 입력 + 기본값 복원 UI 제공
class SpritePreviewPanel extends StatefulWidget {
  const SpritePreviewPanel({
    super.key,
    required this.frames,
    required this.sizes,
    required this.settings,
    required this.imageWidth,
    required this.imageHeight,
    required this.selectedIndex,
    required this.collapsed,
    required this.onCollapseChanged,
    required this.onSelectFrame,
    required this.onFrameRectChanged,
    required this.onCloseEdit,
    required this.onClearAllOverrides,
    this.enabled = true,
  });

  /// 프레임별 PNG 미리보기 바이트.
  final List<Uint8List> frames;

  /// 프레임별 실제 크기 (w × h px).
  final List<({int w, int h})> sizes;

  final CropSettings settings;
  final int imageWidth;
  final int imageHeight;

  /// 현재 선택(편집) 중인 프레임 인덱스. null이면 선택 없음.
  final int? selectedIndex;

  final bool collapsed;
  final ValueChanged<bool> onCollapseChanged;
  final ValueChanged<int?> onSelectFrame;

  /// 프레임 크롭 rect 변경 콜백 (rect = null이면 기본값으로 복원).
  final void Function(int index, CropRect? rect) onFrameRectChanged;
  final VoidCallback onCloseEdit;
  final VoidCallback onClearAllOverrides;

  /// false면 모든 상호작용(썸네일 클릭/숫자 입력/버튼)을 차단한다.
  final bool enabled;

  @override
  State<SpritePreviewPanel> createState() => _SpritePreviewPanelState();
}

class _SpritePreviewPanelState extends State<SpritePreviewPanel> {
  final TextEditingController _xController = TextEditingController();
  final TextEditingController _yController = TextEditingController();
  final TextEditingController _wController = TextEditingController();
  final TextEditingController _hController = TextEditingController();
  final FocusNode _xFocus = FocusNode();
  final FocusNode _yFocus = FocusNode();
  final FocusNode _wFocus = FocusNode();
  final FocusNode _hFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _syncTexts();
  }

  @override
  void didUpdateWidget(covariant SpritePreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.settings != widget.settings ||
        oldWidget.imageWidth != widget.imageWidth ||
        oldWidget.imageHeight != widget.imageHeight) {
      _syncTexts();
    }
  }

  @override
  void dispose() {
    _xController.dispose();
    _yController.dispose();
    _wController.dispose();
    _hController.dispose();
    _xFocus.dispose();
    _yFocus.dispose();
    _wFocus.dispose();
    _hFocus.dispose();
    super.dispose();
  }

  void _syncTexts() {
    final index = widget.selectedIndex;
    if (index == null) return;
    final r = widget.settings.frameRectFor(
      index,
      widget.imageWidth,
      widget.imageHeight,
    );
    _setIfNotFocused(_xFocus, _xController, '${r.x}');
    _setIfNotFocused(_yFocus, _yController, '${r.y}');
    _setIfNotFocused(_wFocus, _wController, '${r.width}');
    _setIfNotFocused(_hFocus, _hController, '${r.height}');
  }

  void _setIfNotFocused(
    FocusNode node,
    TextEditingController controller,
    String text,
  ) {
    if (!node.hasFocus && controller.text != text) {
      controller.text = text;
    }
  }

  void _applyRect({int? x, int? y, int? w, int? h}) {
    final index = widget.selectedIndex;
    if (index == null) return;
    final cur = widget.settings.frameRectFor(
      index,
      widget.imageWidth,
      widget.imageHeight,
    );
    final next = CropSettings.clampFrameRect(
      x: x ?? cur.x,
      y: y ?? cur.y,
      width: w ?? cur.width,
      height: h ?? cur.height,
      imageWidth: widget.imageWidth,
      imageHeight: widget.imageHeight,
    );
    widget.onFrameRectChanged(index, next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = Colors.blue[700]!;
    final total = widget.settings.totalCount;
    final hasFrames = widget.frames.isNotEmpty;
    final anyOverride = widget.settings.frameRects.any((r) => r != null);

    return AnimatedOpacity(
      opacity: widget.enabled ? 1.0 : 0.5,
      duration: const Duration(milliseconds: 150),
      child: AbsorbPointer(
        absorbing: !widget.enabled,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue[50],
            border: Border(top: BorderSide(color: Colors.blue[200]!)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 헤더 (접기 포함) ────────────────────────────
              InkWell(
                onTap: () => widget.onCollapseChanged(!widget.collapsed),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 12,
                    right: 4,
                    top: 4,
                    bottom: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.grid_view_rounded, size: 20, color: primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '결과물 미리보기',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.blue[800],
                          ),
                        ),
                      ),
                      if (anyOverride)
                        TextButton.icon(
                          onPressed: widget.onClearAllOverrides,
                          icon: const Icon(Icons.clear_all, size: 16),
                          label: const Text('전체 초기화'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.orange[800],
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      Text(
                        '$total컷',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            widget.onCollapseChanged(!widget.collapsed),
                        icon: Icon(
                          widget.collapsed
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                        tooltip: widget.collapsed ? '펼치기' : '접기',
                        visualDensity: VisualDensity.compact,
                        color: primary,
                      ),
                    ],
                  ),
                ),
              ),

              // ── 프레임 개별 편집 스트립 ──────────────────────
              if (!widget.collapsed && widget.selectedIndex != null)
                _buildEditStrip(theme),

              // ── 썸네일 그리드 ───────────────────────────────
              if (!widget.collapsed)
                Expanded(
                  child: hasFrames
                      ? _buildGrid()
                      : Center(
                          child: Text(
                            total == 0
                                ? '분할 수를 설정하면 자동으로 미리보기가 생성됩니다.'
                                : '미리보기를 생성하는 중…',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditStrip(ThemeData theme) {
    final index = widget.selectedIndex!;
    final overridden =
        index < widget.settings.frameRects.length &&
        widget.settings.frameRects[index] != null;

    return Container(
      color: Colors.orange.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Icon(Icons.tune, size: 18, color: Colors.orange[800]),
            const SizedBox(width: 6),
            Text(
              '프레임 ${index + 1} 편집',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.orange[900],
              ),
            ),
            const SizedBox(width: 10),
            _EditField(
              controller: _xController,
              focusNode: _xFocus,
              label: 'x',
              onChanged: (v) => _applyRect(x: v),
            ),
            const SizedBox(width: 6),
            _EditField(
              controller: _yController,
              focusNode: _yFocus,
              label: 'y',
              onChanged: (v) => _applyRect(y: v),
            ),
            const SizedBox(width: 6),
            _EditField(
              controller: _wController,
              focusNode: _wFocus,
              label: 'w',
              onChanged: (v) => _applyRect(w: v),
            ),
            const SizedBox(width: 6),
            _EditField(
              controller: _hController,
              focusNode: _hFocus,
              label: 'h',
              onChanged: (v) => _applyRect(h: v),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: overridden
                  ? () => widget.onFrameRectChanged(index, null)
                  : null,
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('기본값'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            TextButton.icon(
              onPressed: widget.onCloseEdit,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('편집 종료'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: widget.frames.length,
      itemBuilder: (context, i) {
        final selected = widget.selectedIndex == i;
        final size = i < widget.sizes.length ? widget.sizes[i] : null;
        return InkWell(
          onTap: () => widget.onSelectFrame(selected ? null : i),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? Colors.orange : Colors.grey.shade400,
                width: selected ? 2.5 : 1,
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
                          widget.frames[i],
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.none,
                          gaplessPlayback: true,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: selected
                      ? Colors.orange.shade100
                      : Colors.black.withValues(alpha: 0.06),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    size == null
                        ? '${i + 1}'
                        : '${i + 1} · ${size.w}×${size.h}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected ? Colors.orange[900] : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
        ),
        onChanged: (text) {
          final value = int.tryParse(text.trim());
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}
