import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart' hide UndoHistory;
import 'package:flutter/services.dart' show LogicalKeyboardKey, rootBundle;
import 'package:image/image.dart' as img;

import '../models/crop_settings.dart';
import '../models/undo_history.dart';
import '../services/color_bg_remover.dart';
import '../services/sprite_cropper.dart';
import '../widgets/control_panel.dart';
import '../widgets/image_canvas.dart';
import '../widgets/save_preview_dialog.dart';
import '../widgets/sprite_preview_panel.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  Uint8List? _rawOriginalBytes;
  Uint8List? _sourceBytes;
  img.Image? _decoded;
  String? _fileName;

  bool _removeBg = false;
  bool _busy = false;

  /// 배경 처리 상태 (색상 기반 크로마키).
  RgbColor? _bgColor;
  double _bgTolerance = 0.1;
  Timer? _bgApplyDebounce;

  // ── 결과물 미리보기 / 프레임별 편집 상태 ──────────────
  Timer? _previewDebounce;
  List<Uint8List> _previewFrames = [];
  List<({int w, int h})> _previewSizes = [];
  int? _editingFrameIndex;
  bool _previewCollapsed = false;

  /// 설정 변경 이력 (되돌리기/다시 실행).
  final UndoHistory<CropSettings> _undoHistory = UndoHistory(capacity: 100);

  CropSettings _settings = const CropSettings(
    horizontalCount: 4,
    verticalCount: 1,
  );

  late final TextEditingController _horizontalController =
      TextEditingController(text: '${_settings.horizontalCount}');
  late final TextEditingController _verticalController = TextEditingController(
    text: '${_settings.verticalCount}',
  );
  late final TextEditingController _topPaddingController =
      TextEditingController(text: '${_settings.topPadding.round()}');
  late final TextEditingController _bottomPaddingController =
      TextEditingController(text: '${_settings.bottomPadding.round()}');
  late final TextEditingController _leftPaddingController =
      TextEditingController(text: '${_settings.leftPadding.round()}');
  late final TextEditingController _rightPaddingController =
      TextEditingController(text: '${_settings.rightPadding.round()}');

  // 수동 경계선 위치 입력용 컨트롤러 (경계 개수 변동 시 동기화)
  final List<TextEditingController> _colBoundaryControllers = [];
  final List<TextEditingController> _rowBoundaryControllers = [];

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _bgApplyDebounce?.cancel();
    _horizontalController.dispose();
    _verticalController.dispose();
    _topPaddingController.dispose();
    _bottomPaddingController.dispose();
    _leftPaddingController.dispose();
    _rightPaddingController.dispose();
    for (final c in _colBoundaryControllers) {
      c.dispose();
    }
    for (final c in _rowBoundaryControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── 이미지 업로드 ────────────────────────────────────
  Future<void> _pickImage() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: '스프라이트 시트 이미지 선택',
      );

      if (files.isEmpty) return;

      final file = files.first;
      final bytes = await file.readAsBytes();
      final decoded = SpriteCropper.decode(bytes);

      if (!mounted) return;

      _bgApplyDebounce?.cancel();
      setState(() {
        _undoHistory.clear();
        _rawOriginalBytes = bytes;
        _sourceBytes = bytes;
        _decoded = decoded;
        _fileName = file.name;
        _removeBg = false;
        _bgColor = null;
        _editingFrameIndex = null;

        _settings = _settings
            .copyWith(
              topPadding: 0.0,
              bottomPadding: 0.0,
              leftPadding: 0.0,
              rightPadding: 0.0,
              useManualBoundaries: false,
            )
            .clearFrameRects();
        _topPaddingController.text = '0';
        _bottomPaddingController.text = '0';
        _leftPaddingController.text = '0';
        _rightPaddingController.text = '0';
      });
      _schedulePreviewUpdate();
    } on FormatException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('이미지를 불러오지 못했습니다: $e');
    }
  }

  // ── 배경 제거 연동 처리 (단색 배경 크로마키) ─────────
  Future<void> _toggleBackgroundRemoval(bool enable) async {
    final raw = _rawOriginalBytes;
    if (raw == null) return;

    if (!enable) {
      // 배경 제거 해제 시 원본 복원
      final decoded = SpriteCropper.decode(raw);
      setState(() {
        _undoHistory.clear();
        _removeBg = false;
        _bgColor = null;
        _sourceBytes = raw;
        _decoded = decoded;
        _editingFrameIndex = null;
        _settings = _settings.clearFrameRects();
      });
      _schedulePreviewUpdate();
      return;
    }

    setState(() {
      _busy = true;
    });
    _showSnack('단색 배경을 감지해 제거하는 중입니다…');

    try {
      final detected = ColorBgRemover.detectBackgroundColor(
        SpriteCropper.decode(raw),
      );
      if (detected == null) {
        if (!mounted) return;
        _showSnack('배경색을 감지하지 못했습니다. 배경이 단색인지 확인해 주세요.');
        return;
      }
      final processedBytes = ColorBgRemover.removeBackground(
        raw,
        backgroundColor: detected,
        tolerance: _bgTolerance,
      );
      final decoded = SpriteCropper.decode(processedBytes);

      if (!mounted) return;
      setState(() {
        _undoHistory.clear();
        _removeBg = true;
        _bgColor = detected;
        _sourceBytes = processedBytes;
        _decoded = decoded;
        _editingFrameIndex = null;
        _settings = _settings.clearFrameRects();
      });
      _schedulePreviewUpdate();
      _showSnack('배경 제거 완료!');
    } catch (e) {
      if (!mounted) return;
      _showSnack('배경 제거 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// 오차 슬라이더 변경 시 지연 적용 (드래그 중 반복 실행 방지).
  void _onBgToleranceChanged(double value) {
    _bgApplyDebounce?.cancel();
    setState(() => _bgTolerance = value);
    if (!_removeBg || _rawOriginalBytes == null) return;
    _bgApplyDebounce = Timer(const Duration(milliseconds: 200), () {
      _reapplyBackgroundRemoval();
    });
  }

  /// 새 오차 값으로 배경 제거를 원본 이미지에 다시 적용한다.
  Future<void> _reapplyBackgroundRemoval() async {
    final raw = _rawOriginalBytes;
    if (!_removeBg || raw == null) return;

    setState(() {
      _busy = true;
    });
    try {
      final detected =
          _bgColor ??
          ColorBgRemover.detectBackgroundColor(SpriteCropper.decode(raw));
      if (detected == null) return;
      final processedBytes = ColorBgRemover.removeBackground(
        raw,
        backgroundColor: detected,
        tolerance: _bgTolerance,
      );
      final decoded = SpriteCropper.decode(processedBytes);

      if (!mounted) return;
      setState(() {
        _undoHistory.clear();
        _bgColor = detected;
        _sourceBytes = processedBytes;
        _decoded = decoded;
        _editingFrameIndex = null;
        _settings = _settings.clearFrameRects();
      });
      _schedulePreviewUpdate();
    } catch (e) {
      if (!mounted) return;
      _showSnack('배경 제거 재적용 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _updateSettings(
    CropSettings nextSettings, {
    bool resetFrameEdits = false,
  }) {
    _undoHistory.record(_settings);
    _applySettingsState(nextSettings, resetFrameEdits: resetFrameEdits);
  }

  bool get _canUndo => _undoHistory.canUndo;
  bool get _canRedo => _undoHistory.canRedo;

  /// 한 단계 실행 취소 (되돌리기).
  void _undo() {
    final restored = _undoHistory.undo(_settings);
    if (restored == null) return;
    _guardEditingIndex(restored);
    _applySettingsState(restored);
  }

  /// 한 단계 다시 실행.
  void _redo() {
    final restored = _undoHistory.redo(_settings);
    if (restored == null) return;
    _guardEditingIndex(restored);
    _applySettingsState(restored);
  }

  /// 복원된 설정의 프레임 수가 편집 중 인덱스보다 적으면 편집을 해제한다.
  void _guardEditingIndex(CropSettings restored) {
    final index = _editingFrameIndex;
    if (index != null && index >= restored.totalCount) {
      _editingFrameIndex = null;
    }
  }

  void _applySettingsState(
    CropSettings nextSettings, {
    bool resetFrameEdits = false,
  }) {
    setState(() {
      if (resetFrameEdits) {
        // 분할 수/여백/경계선 같은 전역 설정이 바뀌면 프레임별 편집을 초기화
        _editingFrameIndex = null;
        nextSettings = nextSettings.clearFrameRects();
      }
      _settings = nextSettings;

      final topText = '${nextSettings.topPadding.round()}';
      if (_topPaddingController.text != topText) {
        _topPaddingController.text = topText;
      }

      final bottomText = '${nextSettings.bottomPadding.round()}';
      if (_bottomPaddingController.text != bottomText) {
        _bottomPaddingController.text = bottomText;
      }

      final leftText = '${nextSettings.leftPadding.round()}';
      if (_leftPaddingController.text != leftText) {
        _leftPaddingController.text = leftText;
      }

      final rightText = '${nextSettings.rightPadding.round()}';
      if (_rightPaddingController.text != rightText) {
        _rightPaddingController.text = rightText;
      }

      final hText = '${nextSettings.horizontalCount}';
      if (_horizontalController.text != hText) {
        _horizontalController.text = hText;
      }

      final vText = '${nextSettings.verticalCount}';
      if (_verticalController.text != vText) {
        _verticalController.text = vText;
      }

      _syncBoundaryControllers(nextSettings);
    });
    _schedulePreviewUpdate();
  }

  /// 경계선 컨트롤러 목록을 설정값과 동기화한다 (개수 변동 시 재구성).
  ///
  /// 사용이 끝난 컨트롤러는 같은 프레임에서 즉시 dispose하지 않고, 위젯
  /// 재빌드가 끝난 뒤 정리한다. 그렇지 않으면 아직 화면에 붙어 있는
  /// TextField가 dispose된 컨트롤러의 listener를 해제하려다
  /// "A TextEditingController was used after being disposed" 예외가 발생한다.
  void _syncBoundaryControllers(CropSettings next) {
    final retired = <TextEditingController>[];

    void sync(List<TextEditingController> controllers, List<int> values) {
      while (controllers.length < values.length) {
        final i = controllers.length;
        controllers.add(TextEditingController(text: '${values[i]}'));
      }
      if (controllers.length > values.length) {
        retired.addAll(controllers.sublist(values.length));
        controllers.removeRange(values.length, controllers.length);
      }
      for (var i = 0; i < values.length; i++) {
        final v = '${values[i]}';
        if (controllers[i].text != v) {
          controllers[i].text = v;
        }
      }
    }

    sync(_colBoundaryControllers, next.columnBoundaries);
    sync(_rowBoundaryControllers, next.rowBoundaries);

    // 같은 프레임 재빌드(TextField 언마운트)가 끝난 뒤에만 안전하게 정리한다.
    if (retired.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in retired) {
          c.dispose();
        }
      });
    }
  }

  // ── 수동 경계선 모드 전환 ─────────────────────────────
  void _toggleManualMode(bool enable) {
    final decoded = _decoded;
    if (decoded == null) return;
    final next = enable
        ? _settings.withEqualBoundaries(
            imageWidth: decoded.width,
            imageHeight: decoded.height,
          )
        : _settings.copyWith(useManualBoundaries: false);
    _updateSettings(next, resetFrameEdits: true);
  }

  /// 수동 모드에서 경계선을 균등 간격으로 되돌린다.
  void _resetBoundaries() {
    final decoded = _decoded;
    if (decoded == null) return;
    _updateSettings(
      _settings.withEqualBoundaries(
        imageWidth: decoded.width,
        imageHeight: decoded.height,
      ),
      resetFrameEdits: true,
    );
  }

  /// 저장 파일명 접두어: 원본 파일명에서 확장자를 제거한 값 (없으면 'sprite').
  String get _namePrefix {
    final name = _fileName;
    if (name == null || name.isEmpty) return 'sprite';
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Future<void> _saveZip() async {
    final bytes = _sourceBytes;
    if (bytes == null) {
      _showSnack('이미지를 먼저 업로드해 주세요.');
      return;
    }

    // 1단계: 프레임 크롭 + 파일명/크기 준비
    List<({String name, Uint8List bytes})> frames;
    List<({int w, int h})> sizes;
    late String zipBase;
    try {
      setState(() => _busy = true);
      frames = SpriteCropper.cropFrames(
        sourceBytes: bytes,
        settings: _settings,
        namePrefix: _namePrefix,
      );
      zipBase = SpriteCropper.zipBaseName(
        namePrefix: _namePrefix,
        settings: _settings,
      );
      sizes = [];
      for (final frame in frames) {
        final decoded = img.decodeImage(frame.bytes);
        sizes.add((w: decoded?.width ?? 0, h: decoded?.height ?? 0));
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('저장 준비에 실패했습니다: $e');
      return;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }

    // 2단계: 저장 전 검토 팝업 (삭제/폴더 분류 가능)
    final groups = await showDialog<List<SaveGroup>>(
      context: context,
      builder: (_) =>
          SavePreviewDialog(baseName: zipBase, frames: frames, sizes: sizes),
    );
    if (!mounted || groups == null) return; // 취소

    // 폴더 구조를 ZIP 경로로 펼친다 (예: 64x64/접두어_1.png)
    final zipEntries = <({String name, Uint8List bytes})>[];
    final frameNames = <String>[];
    for (final group in groups) {
      for (final frame in group.frames) {
        final path = group.folder.isEmpty
            ? frame.name
            : '${group.folder}/${frame.name}';
        zipEntries.add((name: path, bytes: frame.bytes));
        frameNames.add(path);
      }
    }

    // 3단계: ZIP 생성 + 저장
    setState(() => _busy = true);
    try {
      final decoded = _decoded!;
      final sizeRange = _settings.frameSizeRange(
        imageWidth: decoded.width,
        imageHeight: decoded.height,
      );

      // stage.jpg 배경 이미지를 ZIP에 포함 (asset이 없으면 생략)
      List<({String name, Uint8List bytes})>? extraFiles;
      try {
        final stageBytes = await rootBundle.load('assets/images/stage.jpg');
        extraFiles = [
          (name: 'stage.jpg', bytes: stageBytes.buffer.asUint8List()),
        ];
      } catch (_) {
        extraFiles = null; // 배경 이미지가 없으면 포함하지 않음
      }

      final zip = SpriteCropper.buildZip(
        zipEntries,
        extraFiles: extraFiles,
        previewHtml: SpriteCropper.buildPreviewHtml(
          frameNames: frameNames,
          spriteWidth: sizeRange.maxWidth,
          spriteHeight: sizeRange.maxHeight,
        ),
      );

      await FileSaver.instance.saveFile(
        name: zipBase,
        bytes: zip,
        fileExtension: 'zip',
        mimeType: MimeType.zip,
      );

      if (!mounted) return;
      _showSnack('${zipEntries.length}개의 스프라이트를 $zipBase.zip으로 저장했습니다.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('저장에 실패했습니다: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  // ── 결과물 미리보기 (디바운스) ─────────────────────────
  void _schedulePreviewUpdate() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(
      const Duration(milliseconds: 150),
      _updatePreviewFrames,
    );
  }

  void _updatePreviewFrames() {
    final decoded = _decoded;
    final settings = _settings;
    if (decoded == null || settings.totalCount == 0) {
      if (mounted && (_previewFrames.isNotEmpty || _previewSizes.isNotEmpty)) {
        setState(() {
          _previewFrames = [];
          _previewSizes = [];
        });
      }
      return;
    }

    try {
      final images = SpriteCropper.cropFrameImagesFrom(
        decoded,
        settings: settings,
      );
      final frames = <Uint8List>[];
      final sizes = <({int w, int h})>[];
      for (final im in images) {
        frames.add(Uint8List.fromList(img.encodePng(im)));
        sizes.add((w: im.width, h: im.height));
      }
      if (!mounted) return;
      setState(() {
        _previewFrames = frames;
        _previewSizes = sizes;
      });
    } catch (_) {
      // 크롭 실패는 무시 (설정 변경 중 잠깐 발생할 수 있음)
    }
  }

  // ── 프레임별 개별 편집 ────────────────────────────────
  void _onSelectFrame(int? index) {
    setState(() => _editingFrameIndex = index);
  }

  void _onCloseFrameEdit() {
    setState(() => _editingFrameIndex = null);
  }

  void _onFrameRectChanged(int index, CropRect? rect) {
    _updateSettings(_settings.withFrameRect(index, rect: rect));
  }

  void _clearAllFrameOverrides() {
    _updateSettings(_settings.clearFrameRects());
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Colors.blue[700]!;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _redo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AI 스프라이트 시트 분할 도구'),
          centerTitle: false,
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          actions: [
            Tooltip(
              message: '실행 취소 (Ctrl+Z)',
              child: IconButton(
                onPressed: _canUndo ? _undo : null,
                icon: const Icon(Icons.undo),
                color: Colors.white,
                disabledColor: Colors.white60,
              ),
            ),
            Tooltip(
              message: '다시 실행 (Ctrl+Shift+Z)',
              child: IconButton(
                onPressed: _canRedo ? _redo : null,
                icon: const Icon(Icons.redo),
                color: Colors.white,
                disabledColor: Colors.white60,
              ),
            ),
          ],
        ),
        body: Row(
          children: [
            SizedBox(
              width: 320,
              child: ControlPanel(
                fileName: _fileName,
                imageWidth: _decoded?.width,
                imageHeight: _decoded?.height,
                settings: _settings,
                busy: _busy,
                removeBg: _removeBg,
                namePrefix: _namePrefix,
                bgColor: _bgColor == null
                    ? null
                    : Color.fromARGB(
                        255,
                        _bgColor!.r,
                        _bgColor!.g,
                        _bgColor!.b,
                      ),
                tolerance: _bgTolerance,
                horizontalController: _horizontalController,
                verticalController: _verticalController,
                topPaddingController: _topPaddingController,
                bottomPaddingController: _bottomPaddingController,
                leftPaddingController: _leftPaddingController,
                rightPaddingController: _rightPaddingController,
                onPickImage: _pickImage,
                onRemoveBgChanged: _toggleBackgroundRemoval,
                onToleranceChanged: _onBgToleranceChanged,
                onSettingsChanged:
                    ({
                      int? horizontalCount,
                      int? verticalCount,
                      double? topPadding,
                      double? bottomPadding,
                      double? leftPadding,
                      double? rightPadding,
                      List<int>? columnBoundaries,
                      List<int>? rowBoundaries,
                    }) {
                      var next = _settings.copyWith(
                        horizontalCount:
                            horizontalCount ?? _settings.horizontalCount,
                        verticalCount: verticalCount ?? _settings.verticalCount,
                        topPadding: topPadding ?? _settings.topPadding,
                        bottomPadding: bottomPadding ?? _settings.bottomPadding,
                        leftPadding: leftPadding ?? _settings.leftPadding,
                        rightPadding: rightPadding ?? _settings.rightPadding,
                        columnBoundaries:
                            columnBoundaries ?? _settings.columnBoundaries,
                        rowBoundaries: rowBoundaries ?? _settings.rowBoundaries,
                      );
                      // 수동 모드에서 분할 수를 바꾸면 경계선을 균등 간격으로 재초기화
                      if (next.useManualBoundaries &&
                          (horizontalCount != null || verticalCount != null)) {
                        final decoded = _decoded;
                        if (decoded != null) {
                          next = next.withEqualBoundaries(
                            imageWidth: decoded.width,
                            imageHeight: decoded.height,
                          );
                        }
                      }
                      _updateSettings(next, resetFrameEdits: true);
                    },
                onManualModeChanged: _toggleManualMode,
                onResetBoundaries: _resetBoundaries,
                onSave: _saveZip,
                colBoundaryControllers: _colBoundaryControllers,
                rowBoundaryControllers: _rowBoundaryControllers,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _buildPreview()),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final bytes = _sourceBytes;
    final decoded = _decoded;
    if (bytes == null || decoded == null) {
      return const _EmptyState();
    }

    final range = _settings.frameSizeRange(
      imageWidth: decoded.width,
      imageHeight: decoded.height,
    );

    final activeWidth =
        (decoded.width - _settings.leftPadding - _settings.rightPadding)
            .round()
            .clamp(0, decoded.width);
    final activeHeight =
        (decoded.height - _settings.topPadding - _settings.bottomPadding)
            .round()
            .clamp(0, decoded.height);

    final infoText = _settings.useManualBoundaries
        ? '전체: ${decoded.width} × ${decoded.height} px  •  '
              '1컷: ${range.minWidth}×${range.minHeight} ~ '
              '${range.maxWidth}×${range.maxHeight} px  •  '
              '총 ${_settings.totalCount}개 '
              '(${_settings.effectiveHorizontalCount}×${_settings.effectiveVerticalCount})  •  수동 조절'
        : '전체: ${decoded.width} × ${decoded.height} px  •  '
              '영역: $activeWidth × $activeHeight px '
              '(상: ${_settings.topPadding.round()}, '
              '하: ${_settings.bottomPadding.round()}, '
              '좌: ${_settings.leftPadding.round()}, '
              '우: ${_settings.rightPadding.round()})  •  '
              '1컷: ${range.maxWidth} × ${range.maxHeight} px  •  '
              '총 ${_settings.totalCount}개 '
              '(${_settings.effectiveHorizontalCount}×${_settings.effectiveVerticalCount})';

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ImageCanvas(
              key: ValueKey(bytes),
              imageBytes: bytes,
              imageWidth: decoded.width,
              imageHeight: decoded.height,
              settings: _settings,
              onSettingsChanged: (s) =>
                  _updateSettings(s, resetFrameEdits: true),
              editingFrameIndex: _editingFrameIndex,
              onFrameRectChanged: _onFrameRectChanged,
              interactive: !_busy,
            ),
          ),
        ),
        SizedBox(
          height: _previewCollapsed ? 44 : 240,
          child: SpritePreviewPanel(
            frames: _previewFrames,
            sizes: _previewSizes,
            settings: _settings,
            imageWidth: decoded.width,
            imageHeight: decoded.height,
            selectedIndex: _editingFrameIndex,
            collapsed: _previewCollapsed,
            onCollapseChanged: (v) => setState(() => _previewCollapsed = v),
            onSelectFrame: _onSelectFrame,
            onFrameRectChanged: _onFrameRectChanged,
            onCloseEdit: _onCloseFrameEdit,
            onClearAllOverrides: _clearAllFrameOverrides,
            enabled: !_busy,
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              border: Border(top: BorderSide(color: Colors.blue[200]!)),
            ),
            child: Text(
              infoText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.blue[800],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.crop, size: 96, color: Colors.blue[200]),
          const SizedBox(height: 16),
          Text(
            '스프라이트 시트를 업로드해 주세요',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '가이드 박스의 핸들을 드래그하거나\n좌측 컨트롤 패널에서 세로 높이/여백 수치를 직접 수정할 수 있습니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.blue[400],
            ),
          ),
        ],
      ),
    );
  }
}
