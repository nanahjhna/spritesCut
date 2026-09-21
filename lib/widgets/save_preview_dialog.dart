import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'image_canvas.dart' show CheckerboardPainter;

/// 프레임 한 장 (파일명 + PNG 바이트).
typedef SaveFrame = ({String name, Uint8List bytes});

/// 저장 단위 그룹.
///
/// - [folder]: ZIP 내부 폴더 경로 (사용자가 만든 폴더명). 빈 문자열이면 루트.
/// - [frames]: 해당 폴더에 들어갈 프레임 목록 (번호는 폴더 안에서 1부터 재정렬).
typedef SaveGroup = ({String folder, List<SaveFrame> frames});

/// 저장 전 프레임 검토 팝업.
///
/// - 잘라낸 모든 컷을 체커보드 위 그리드로 표시 (투명 확인용)
/// - 사진을 탭하면 삭제 버튼이 표시되고, 누르면 해당 컷을 삭제
/// - 삭제 시 파일명 번호를 연속으로 재배열한다
/// - `folders-switch`(폴더 정리)를 켜면 사이드바에서 **폴더를 직접 만들고**,
///   프레임을 멀티 선택(선택 모드 or Ctrl/Shift+클릭)한 뒤
///   길게 드래그해서 폴더 안에 격납할 수 있다
/// - 폴더 이름 변경/삭제 지원 (삭제 시 안의 이미지는 기본=폴더 없음으로 이동)
/// - "다운로드 (ZIP)" 버튼으로 폴더 구조가 포함된 결과를 반환한다 (취소 시 null)
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
  final List<SaveFrame> frames;

  /// 프레임별 실제 크기 (sizes[i] ↔ frames[i]).
  final List<({int w, int h})> sizes;

  @override
  State<SavePreviewDialog> createState() => _SavePreviewDialogState();
}

class _SavePreviewDialogState extends State<SavePreviewDialog> {
  late final List<SaveFrame> _frames = [...widget.frames];
  late final List<({int w, int h})> _sizes = [...widget.sizes];

  /// 사용자가 만든 폴더 이름 (생성 순서).
  final List<String> _folders = [];

  /// 프레임별 폴더 배정 ('' = 루트/기본). `_frames`와 인덱스가 항상 같다.
  late final List<String> _folderAssignments =
      List.generate(_frames.length, (_) => '');

  /// 삭제 버튼이 표시 중인 타일 (단일 선택 시 오버레이로 표시).
  final Set<int> _marked = {};

  /// 멀티 선택된 프레임 인덱스 (폴더 모드).
  final Set<int> _selection = {};

  /// Shift 범위 선택 기준점.
  int? _selectionAnchor;

  /// 현재 보고 있는 폴더. null = 전체 보기, '' = 기본(폴더 없음), 그 외 = 폴더명.
  String? _activeFolder;

  /// 폴더 정리 모드 여부 (folders-switch).
  bool _folderMode = true;

  /// 클릭 없이 탭만으로 멀티 선택하기 위한 선택 모드.
  bool _selectMode = false;

  // ── 폴더 이름 정리 ──────────────────────────────────
  /// ZIP/HTML에서 안전한 폴더명 (공백은 유지, 부적합 문자만 제거).
  String _sanitizeFolderName(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'''[/\\:*?"<>|#%]+'''), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned;
  }

  bool _folderNameExists(String name, {int? exceptIndex}) {
    final lower = name.toLowerCase();
    for (var i = 0; i < _folders.length; i++) {
      if (i != exceptIndex && _folders[i].toLowerCase() == lower) return true;
    }
    return false;
  }

  String _defaultFolderName() {
    var n = _folders.length + 1;
    while (_folderNameExists('새 폴더 $n')) {
      n++;
    }
    return '새 폴더 $n';
  }

  int _folderCount(String folder) =>
      _folderAssignments.where((f) => f == folder).length;

  /// 현재 그리드에 보여줄 프레임 인덱스 (전역 인덱스 기준).
  List<int> get _visibleIndices {
    if (!_folderMode) return [for (var i = 0; i < _frames.length; i++) i];
    final active = _activeFolder;
    if (active == null) return [for (var i = 0; i < _frames.length; i++) i];
    return [
      for (var i = 0; i < _frames.length; i++)
        if (_folderAssignments[i] == active) i,
    ];
  }

  // ── 폴더 모드 토글 ──────────────────────────────────
  void _toggleFolderMode(bool on) {
    setState(() {
      _folderMode = on;
      if (!on) _activeFolder = null;
      _selectionAnchor = null;
      _selection.clear();
      _marked.clear();
    });
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      _selection.clear();
      _selectionAnchor = null;
      _syncMarkedFromSelection();
    });
  }

  // ── 폴더 이름 입력 다이얼로그 ───────────────────────
  Future<String?> _promptFolderName({
    required String title,
    required String initial,
    int? exceptIndex,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _FolderNameDialog(
        title: title,
        initial: initial,
        sanitize: _sanitizeFolderName,
        validate: (value) {
          final name = value ?? '';
          final cleaned = _sanitizeFolderName(name);
          if (name.trim().isEmpty) return '이름을 입력해 주세요.';
          if (cleaned.isEmpty) return '사용할 수 없는 이름입니다.';
          if (_folderNameExists(cleaned, exceptIndex: exceptIndex)) {
            return '같은 이름의 폴더가 이미 있습니다.';
          }
          return null;
        },
      ),
    );
  }

  // ── 폴더 관리 ───────────────────────────────────────
  Future<void> _addFolder() async {
    final name = await _promptFolderName(
      title: '폴더 추가',
      initial: _defaultFolderName(),
    );
    if (name == null || !mounted) return;
    setState(() {
      _folders.add(name);
      _selection.clear();
      _selectionAnchor = null;
      _syncMarkedFromSelection();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"$name" 폴더를 추가했습니다 — 이미지를 길게 드래그하거나 [이동] 버튼으로 넣으세요.'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _renameFolder(int index) async {
    final oldName = _folders[index];
    final name = await _promptFolderName(
      title: '폴더 이름 변경',
      initial: oldName,
      exceptIndex: index,
    );
    if (name == null || !mounted || name == oldName) return;
    setState(() {
      _folders[index] = name;
      for (var i = 0; i < _folderAssignments.length; i++) {
        if (_folderAssignments[i] == oldName) _folderAssignments[i] = name;
      }
      if (_activeFolder == oldName) _activeFolder = name;
    });
  }

  Future<void> _deleteFolder(int index) async {
    final folder = _folders[index];
    final count = _folderCount(folder);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('폴더 삭제'),
        content: Text(
          count == 0
              ? '폴더 "$folder"을(를) 삭제할까요?'
              : '폴더 "$folder"의 이미지 $count개가 기본(폴더 없음)으로 이동합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('folder-delete-ok'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _folders.removeAt(index);
      for (var i = 0; i < _folderAssignments.length; i++) {
        if (_folderAssignments[i] == folder) _folderAssignments[i] = '';
      }
      if (_activeFolder == folder) _activeFolder = '';
      _selection.clear();
      _selectionAnchor = null;
      _syncMarkedFromSelection();
    });
  }

  // ── 선택 / 클릭 ─────────────────────────────────────
  void _onTileTap(int index) {
    if (!_folderMode) {
      setState(() {
        if (!_marked.remove(index)) _marked.add(index);
      });
      return;
    }

    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final ctrl = keys.any(
      (k) =>
          k == LogicalKeyboardKey.controlLeft ||
          k == LogicalKeyboardKey.controlRight,
    );
    final shift = keys.any(
      (k) =>
          k == LogicalKeyboardKey.shiftLeft ||
          k == LogicalKeyboardKey.shiftRight,
    );

    setState(() {
      if (shift && _selectionAnchor != null) {
        final lo = math.min(_selectionAnchor!, index);
        final hi = math.max(_selectionAnchor!, index);
        _selection
          ..clear()
          ..addAll([for (var i = lo; i <= hi; i++) i]);
      } else if (ctrl || _selectMode) {
        if (!_selection.remove(index)) _selection.add(index);
        _selectionAnchor = index;
      } else {
        _selection
          ..clear()
          ..add(index);
        _selectionAnchor = index;
      }
      _syncMarkedFromSelection();
    });
  }

  /// 삭제 오버레이는 단일 선택일 때 그 타일에만 표시한다.
  void _syncMarkedFromSelection() {
    _marked.clear();
    if (_selection.length == 1) _marked.addAll(_selection);
  }

  // ── 삭제 ────────────────────────────────────────────
  void _delete(int index) {
    setState(() {
      _frames.removeAt(index);
      _sizes.removeAt(index);
      _folderAssignments.removeAt(index);

      _marked.remove(index);
      _selection.remove(index);
      _rebuildSelectionIndices(index);
      _syncMarkedFromSelection();
      _renumberAll();
      _clearEmptyActiveFolder();
    });
  }

  void _deleteSelected() {
    final indices = _selection.toList()..sort();
    if (indices.isEmpty) return;
    setState(() {
      for (final i in indices.reversed) {
        _frames.removeAt(i);
        _sizes.removeAt(i);
        _folderAssignments.removeAt(i);
        _marked.remove(i);
      }
      _selectionAnchor = null;
      _selection.clear();
      _markAllMissed(_marked, indices);
      _syncMarkedFromSelection();
      _renumberAll();
      _clearEmptyActiveFolder();
    });
  }

  /// 인덱스 [removed] 삭제 후 남은 선택 인덱스들을 한 칸씩 당긴다.
  void _rebuildSelectionIndices(int removed) {
    final shifted = <int>{};
    for (final m in _selection) {
      shifted.add(m > removed ? m - 1 : m);
    }
    _selection
      ..clear()
      ..addAll(shifted);
    final anchor = _selectionAnchor;
    if (anchor != null && anchor > removed) _selectionAnchor = anchor - 1;
  }

  /// 여러 인덱스([removed] 오름차순) 삭제 시 `_marked` 재정렬.
  void _markAllMissed(Set<int> target, List<int> removed) {
    final shifted = <int>{};
    for (final m in target) {
      if (removed.contains(m)) continue;
      var newIndex = m;
      for (final r in removed) {
        if (m > r) newIndex--;
      }
      shifted.add(newIndex);
    }
    target
      ..clear()
      ..addAll(shifted);
  }

  /// 삭제 후 현재 보고 있는 폴더가 비었으면 전체 보기로 전환.
  void _clearEmptyActiveFolder() {
    final active = _activeFolder;
    if (active != null &&
        active.isNotEmpty &&
        !_folderAssignments.contains(active)) {
      _activeFolder = null;
    }
  }

  /// 전역 연속 번호로 파일명을 재배열한다.
  void _renumberAll() {
    for (var i = 0; i < _frames.length; i++) {
      _frames[i] = (
        name: '${widget.baseName}_${i + 1}.png',
        bytes: _frames[i].bytes,
      );
    }
  }

  // ── 폴더 이동 ───────────────────────────────────────
  void _moveToFolder(Set<int> indices, String folder) {
    if (!_folderMode || indices.isEmpty) return;
    setState(() {
      for (final i in indices) {
        if (i >= 0 && i < _folderAssignments.length) {
          _folderAssignments[i] = folder;
        }
      }
      _activeFolder = folder;
      _selection.clear();
      _selectionAnchor = null;
      _syncMarkedFromSelection();
    });
  }

  void _selectFolder(String? folder) {
    setState(() {
      _activeFolder = folder;
      _selection.clear();
      _selectionAnchor = null;
      _syncMarkedFromSelection();
    });
  }

  /// 선택된 이미지를 대상 폴더 선택 다이얼로그로 일괄 이동한다.
  Future<void> _moveSelectionToFolder() async {
    if (_selection.isEmpty) return;
    final folder = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('이동할 폴더 선택'),
        children: [
          ListTile(
            key: const ValueKey('move-target-root'),
            leading: const Icon(Icons.folder_off_outlined),
            title: const Text('기본(폴더 없음)'),
            trailing: Text('${_folderCount('')}'),
            onTap: () => Navigator.of(context).pop(''),
          ),
          for (var i = 0; i < _folders.length; i++)
            ListTile(
              key: ValueKey('move-target-$i'),
              leading: const Icon(Icons.folder_outlined),
              title: Text(_folders[i]),
              trailing: Text('${_folderCount(_folders[i])}'),
              onTap: () => Navigator.of(context).pop(_folders[i]),
            ),
        ],
      ),
    );
    if (folder == null || !mounted) return;
    _moveToFolder(Set<int>.of(_selection), folder);
  }

  // ── 결과 반환 ───────────────────────────────────────
  void _confirm() {
    Navigator.of(context).pop(_buildResult());
  }

  List<SaveGroup> _buildResult() {
    if (!_folderMode) return [(folder: '', frames: List.of(_frames))];

    final map = <String, List<SaveFrame>>{};
    for (var i = 0; i < _frames.length; i++) {
      (map[_folderAssignments[i]] ??= []).add(_frames[i]);
    }

    final groups = <SaveGroup>[];
    final root = map[''];
    if (root != null && root.isNotEmpty) {
      groups.add((folder: '', frames: _renumberFolder(root)));
    }
    for (final folder in _folders) {
      final list = map[folder];
      if (list != null && list.isNotEmpty) {
        groups.add((folder: folder, frames: _renumberFolder(list)));
      }
    }
    return groups;
  }

  /// 폴더 안에서 프레임 번호를 1부터 다시 붙인다.
  List<SaveFrame> _renumberFolder(List<SaveFrame> list) {
    return [
      for (var j = 0; j < list.length; j++)
        (name: '${widget.baseName}_${j + 1}.png', bytes: list[j].bytes),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _frames.length;
    final removedCount = widget.frames.length - total;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 640),
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

            // ── 폴더 정리 도구바 ────────────────────────────
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 20),
                    key: const ValueKey('folders-switch'),
                    title: const Text(
                      '폴더 정리',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const Text(
                      '폴더를 만들어 이미지를 정리합니다.',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _folderMode,
                    onChanged: (v) => _toggleFolderMode(v),
                  ),
                ),
                if (_folderMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      key: const ValueKey('select-mode'),
                      onPressed: _toggleSelectMode,
                      isSelected: _selectMode,
                      tooltip: '선택 모드 (여러 개 선택)',
                      icon: Icon(
                        Icons.checklist_rtl,
                        color: _selectMode
                            ? Colors.blue[800]
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 1),

            // ── 프레임 그리드 / 폴더 사이드바 ──────────────
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
                  : _folderMode
                  ? Row(
                      children: [
                        SizedBox(width: 200, child: _buildSidebar(theme)),
                        const VerticalDivider(width: 1),
                        Expanded(child: _buildGrid(theme)),
                      ],
                    )
                  : _buildGrid(theme),
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
                          : _folderMode
                          ? '이미지를 0.5초 길게 눌러 드래그하거나, 선택 후 [이동] 버튼으로 넣으세요.'
                          : '사진을 누르면 삭제할 수 있어요.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_folderMode && _selection.isNotEmpty) ...[
                    if (_folders.isNotEmpty)
                      TextButton.icon(
                        key: const ValueKey('move-selected'),
                        onPressed: _moveSelectionToFolder,
                        icon: const Icon(
                          Icons.drive_file_move_outline,
                          size: 16,
                        ),
                        label: const Text('이동'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    TextButton.icon(
                      key: const ValueKey('delete-selected'),
                      onPressed: _deleteSelected,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('선택 삭제'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red[700],
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
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

  // ── 사이드바 (폴더 목록) ────────────────────────────
  Widget _buildSidebar(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('add-folder'),
              onPressed: _addFolder,
              icon: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: const Text('폴더 추가'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 6),
            children: [
              // 전체 보기 (보기 전용)
              _FolderItem(
                key: const ValueKey('folder-all'),
                title: '전체 보기',
                count: _frames.length,
                selected: _activeFolder == null,
                onTap: () => _selectFolder(null),
              ),
              // 기본(폴더 없음) — 이동 드롭존
              DragTarget<Set<int>>(
                onWillAcceptWithDetails: (_) => true,
                onAcceptWithDetails: (details) =>
                    _moveToFolder(details.data, ''),
                builder: (context, candidates, rejected) => _FolderItem(
                  key: const ValueKey('folder-root'),
                  title: '기본(폴더 없음)',
                  count: _folderCount(''),
                  selected: _activeFolder == '',
                  highlighted: candidates.isNotEmpty,
                  onTap: () => _selectFolder(''),
                ),
              ),
              if (_folders.isNotEmpty) const Divider(height: 8),
              // 사용자 폴더 — 이동 드롭존 + 이름 변경/삭제
              for (var i = 0; i < _folders.length; i++)
                DragTarget<Set<int>>(
                  onWillAcceptWithDetails: (_) => true,
                  onAcceptWithDetails: (details) =>
                      _moveToFolder(details.data, _folders[i]),
                  builder: (context, candidates, rejected) {
                    final folder = _folders[i];
                    return _FolderItem(
                      key: ValueKey('folder-$i'),
                      title: folder,
                      count: _folderCount(folder),
                      selected: _activeFolder == folder,
                      highlighted: candidates.isNotEmpty,
                      onTap: () => _selectFolder(folder),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MiniIconButton(
                            key: ValueKey('rename-folder-$i'),
                            icon: Icons.edit_outlined,
                            tooltip: '이름 변경',
                            onPressed: () => _renameFolder(i),
                          ),
                          _MiniIconButton(
                            key: ValueKey('delete-folder-$i'),
                            icon: Icons.delete_outline,
                            tooltip: '폴더 삭제',
                            onPressed: () => _deleteFolder(i),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 프레임 그리드 ───────────────────────────────────
  Widget _buildGrid(ThemeData theme) {
    final visible = _visibleIndices;
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: visible.length,
      itemBuilder: (context, i) => _buildTile(visible[i], theme),
    );
  }

  Widget _buildTile(int index, ThemeData theme) {
    final frame = _frames[index];
    final size = index < _sizes.length ? _sizes[index] : null;
    // 삭제 오버레이는 레거시(폴더 OFF) 모드에서만 표시한다.
    final showDelete = !_folderMode && _marked.contains(index);
    final selected = _folderMode && _selection.contains(index);

    final tile = InkWell(
      key: ValueKey('tile-$index'),
      onTap: () => _onTileTap(index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? Colors.blue
                : showDelete
                ? Colors.red.shade400
                : Colors.grey.shade400,
            width: selected || showDelete ? 2.5 : 1,
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
                  if (selected || (showDelete && !_folderMode))
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.blue[700],
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (showDelete)
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
              color: selected
                  ? Colors.blue.shade50
                  : showDelete
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
                  color: selected
                      ? Colors.blue[900]
                      : showDelete
                      ? Colors.red[900]
                      : null,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!_folderMode) return tile;

    // 드래그 데이터: 이미 선택된 타일이면 전체 선택, 아니면 해당 타일 하나
    final dragData = _selection.isNotEmpty && _selection.contains(index)
        ? Set<int>.of(_selection)
        : {index};

    return LongPressDraggable<Set<int>>(
      data: dragData,
      feedback: _DragFeedback(count: dragData.length),
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: tile,
    );
  }
}

/// 폴더 이름 입력 다이얼로그.
class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({
    required this.title,
    required this.initial,
    required this.sanitize,
    required this.validate,
  });

  final String title;
  final String initial;
  final String Function(String raw) sanitize;
  final String? Function(String? raw) validate;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(widget.sanitize(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const ValueKey('folder-name-field'),
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '폴더 이름',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          validator: widget.validate,
          onFieldSubmitted: (_) => _submit(),
          textInputAction: TextInputAction.done,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          key: const ValueKey('folder-name-ok'),
          onPressed: _submit,
          child: const Text('확인'),
        ),
      ],
    );
  }
}

/// 사이드바 폴더 아이템.
class _FolderItem extends StatelessWidget {
  const _FolderItem({
    super.key,
    required this.title,
    required this.count,
    required this.selected,
    this.onTap,
    this.highlighted = false,
    this.trailing,
  });

  final String title;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  /// 드래그 호버 시 강조.
  final bool highlighted;

  /// 이름 변경/삭제 등 우측 액션.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.only(left: 8, right: 2),
        decoration: BoxDecoration(
          color: highlighted
              ? Colors.blue.withValues(alpha: 0.18)
              : selected
              ? Colors.blue.withValues(alpha: 0.12)
              : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: highlighted
                ? Colors.blue
                : selected
                ? Colors.blue[300]!
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.folder_open : Icons.folder_outlined,
              size: 18,
              color: selected
                  ? Colors.blue[700]
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : null,
                  color: selected ? Colors.blue[800] : null,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Text(
              '$count',
              style: theme.textTheme.bodySmall?.copyWith(
                color: selected ? Colors.blue[700] : null,
                fontWeight: FontWeight.w600,
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// 폴더 아이템 우측 작은 아이콘 버튼.
class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

/// 드래그 중 표시되는 선택 개수 배지.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.blue[700],
      borderRadius: BorderRadius.circular(20),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.drive_file_move_outline,
                color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              '$count개',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}