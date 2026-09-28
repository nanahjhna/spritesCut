import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/batch_crop_settings.dart';
import '../services/batch_cropper.dart';
import '../services/image_engine.dart';
import '../services/sprite_cropper.dart';
import '../widgets/batch_crop_canvas.dart';

/// 여러 장의 사진을 고정한 크기·가운데 정렬로 일괄 자르는 화면.
///
/// 스프라이트 시트 분할과 달리 격자 개념이 없고, 모든 사진에 같은 사각형이
/// 적용된다. 지정한 크기가 원본보다 크면 자동으로 확대한 뒤 자른다.
class BatchCropScreen extends StatefulWidget {
  const BatchCropScreen({super.key});

  @override
  State<BatchCropScreen> createState() => _BatchCropScreenState();
}

class _BatchCropScreenState extends State<BatchCropScreen> {
  /// 테마 강조색. `MaterialColor` 로 선언해 `shade`/`[]` 를 함께 쓴다.
  static const MaterialColor _accent = Colors.deepOrange;

  /// 입력 필드 구분용 번호 ([_focusedField]).
  static const int _widthField = 0;
  static const int _heightField = 1;

  /// 불러온 사진 목록.
  List<BatchSourceFile> _files = const [];

  /// 모든 사진에 적용할 고정 크기.
  BatchCropSettings _settings = BatchCropSettings.defaultSize;

  /// 사각형 드래그 기준으로 삼는 사진 인덱스.
  int _selectedIndex = 0;

  /// 캔버스에서 사각형을 드래그하는 중인지 여부.
  ///
  /// 드래그 중에는 비싼 결과 미리보기 재계산을 하지 않아 60fps 를 유지한다.
  bool _interacting = false;

  /// 썸네일 캐시: 파일(객체 식별) → 엔진으로 한 번만 만든 작은 PNG.
  ///
  /// 원본 JPEG(수 MB)를 목록 리빌드마다 디코딩하지 않도록 캐시한다.
  final Map<BatchSourceFile, Uint8List> _thumbPngs = {};
  bool _thumbsBusy = false;

  // ── 크기 입력 ─────────────────────────────────────────
  late final TextEditingController _widthController =
      TextEditingController(text: '${_settings.width}');
  late final TextEditingController _heightController =
      TextEditingController(text: '${_settings.height}');
  late final FocusNode _widthFocus = FocusNode();
  late final FocusNode _heightFocus = FocusNode();

  /// 포커스를 가진 입력 필드. 사용자가 직접 입력 중일 때는 자동 동기화하지 않는다.
  int? _focusedField;

  // ── 작업 상태 ─────────────────────────────────────────
  bool _busy = false;
  int _done = 0;
  int _total = 0;
  String _status = '';

  /// 마지막 저장 결과를 좌측 패널에 보여줄 메시지.
  String? _lastResult;

  // ── 결과 미리보기 (선택한 사진 1장만) ─────────────────
  Timer? _previewDebounce;
  int _previewToken = 0;
  Uint8List? _resultPreview;
  String? _previewError;
  bool _previewing = false;

  BatchSourceFile? get _current =>
      _files.isEmpty ? null : _files[_selectedIndex.clamp(0, _files.length - 1)];

  @override
  void initState() {
    super.initState();
    _widthFocus.addListener(() => _syncFocusedField(_widthField, _widthFocus));
    _heightFocus.addListener(() => _syncFocusedField(_heightField, _heightFocus));
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _widthController.dispose();
    _heightController.dispose();
    _widthFocus.dispose();
    _heightFocus.dispose();
    super.dispose();
  }

  void _syncFocusedField(int field, FocusNode node) {
    final next = node.hasFocus ? field : (_focusedField == field ? null : _focusedField);
    if (next == _focusedField) return;
    setState(() => _focusedField = next);
  }

  // ── 사진 선택 (다중) ───────────────────────────────────
  Future<void> _pickFiles() async {
    if (_busy) return;
    try {
      // file_picker 13.x 의 pickFiles() 는 항상 다중 선택이다.
      // (단일 선택이 필요하면 pickFile() 을 쓴다.)
      final picked = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: '자를 사진 선택 (여러 장 가능)',
      );
      if (picked.isEmpty || !mounted) return;

      setState(() {
        _busy = true;
        _done = 0;
        _total = picked.length;
        _lastResult = null;
        _status = '사진을 불러오는 중…';
      });

      final loaded = <BatchSourceFile>[];
      final skipped = <String>[];
      for (final file in picked) {
        try {
          final bytes = await file.readAsBytes();
          final size = await BatchCropper.readImageSize(bytes);
          loaded.add(
            (name: file.name, bytes: bytes, width: size.width, height: size.height),
          );
        } catch (_) {
          skipped.add(file.name);
        }
        if (mounted) {
          setState(() {
            _done++;
            _status = file.name;
          });
        }
        // 다음 파일 전에 이벤트 루프를 한 번 돌려 진행 표시가 갱신되게 한다.
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      if (!mounted) return;
      if (loaded.isEmpty) {
        _showSnack('이미지를 읽을 수 있는 파일이 없습니다.');
        return;
      }

      final firstNew = _files.length;
      setState(() {
        _files = [..._files, ...loaded];
        // 새로 추가된 첫 사진을 기준으로 삼는다.
        _selectedIndex = firstNew;
        _lastResult = skipped.isEmpty
            ? null
            : '${skipped.length}개 파일은 읽지 못해 건너뛰었습니다.';
      });
      _schedulePreview();
      _generateThumbnails();

      if (skipped.isNotEmpty) {
        _showSnack('${skipped.length}개 파일은 읽지 못해 건너뛰었습니다.');
      }
    } catch (e) {
      if (mounted) _showSnack('사진을 불러오지 못했습니다: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearFiles() {
    if (_busy || _files.isEmpty) return;
    _previewDebounce?.cancel();
    setState(() {
      _files = const [];
      _thumbPngs.clear();
      _selectedIndex = 0;
      _resultPreview = null;
      _previewError = null;
      _previewing = false;
      // 진행 중인 미리보기가 결과를 덮어쓰지 않도록 무효화한다.
      _previewToken++;
    });
  }

  void _removeFile(int index) {
    if (_busy || index < 0 || index >= _files.length) return;
    setState(() {
      final next = List<BatchSourceFile>.from(_files)..removeAt(index);
      _files = next;
      if (_selectedIndex >= next.length) {
        _selectedIndex = next.isEmpty ? 0 : next.length - 1;
      }
    });
    _schedulePreview();
  }

  // ── 크기 변경 ─────────────────────────────────────────
  void _applySettings(BatchCropSettings next) {
    if (next == _settings) return;
    setState(() => _settings = next);
    _syncControllers();
    _schedulePreview();
  }

  void _onWidthChanged(String text) {
    final value = int.tryParse(text.trim());
    if (value == null) return;
    _applySettings(_settings.copyWith(
      width: value.clamp(BatchCropSettings.minSize, BatchCropSettings.maxSize),
    ));
  }

  void _onHeightChanged(String text) {
    final value = int.tryParse(text.trim());
    if (value == null) return;
    _applySettings(_settings.copyWith(
      height: value.clamp(BatchCropSettings.minSize, BatchCropSettings.maxSize),
    ));
  }

  /// 드래그 등으로 바뀐 크기를 입력 필드에 반영한다.
  void _syncControllers() {
    void sync(TextEditingController controller, int value, int field) {
      final text = '$value';
      if (controller.text == text) return;
      // 사용자가 직접 입력 중인 필드는 커서가 튀지 않도록 건드리지 않는다.
      if (_focusedField == field) return;
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }

    sync(_widthController, _settings.width, _widthField);
    sync(_heightController, _settings.height, _heightField);
  }

  // ── 결과 미리보기 (선택한 사진 1장) ─────────────────────
  /// 캔버스 드래그 시작: 미리보기 재계산을 잠시 멈춘다.
  void _onInteractionStart() {
    if (_interacting) return;
    setState(() => _interacting = true);
  }

  /// 캔버스 드래그 종료: 결과 미리보기를 다시 계산한다.
  void _onInteractionEnd() {
    if (!_interacting) return;
    setState(() => _interacting = false);
    _schedulePreview();
  }

  void _schedulePreview() {
    _previewDebounce?.cancel();
    if (_files.isEmpty || _interacting) return;
    setState(() => _previewing = true);

    final token = ++_previewToken;
    final file = _current!;
    final settings = _settings;

    _previewDebounce = Timer(
      const Duration(milliseconds: 180),
      () => _updateResultPreview(file, settings, token),
    );
  }

  Future<void> _updateResultPreview(
    BatchSourceFile file,
    BatchCropSettings settings,
    int token,
  ) async {
    try {
      final bytes = await BatchCropper.cropToPng(file.bytes, settings);
      if (!mounted || token != _previewToken) return;
      setState(() {
        _resultPreview = bytes;
        _previewError = null;
        _previewing = false;
      });
    } catch (e) {
      if (!mounted || token != _previewToken) return;
      setState(() {
        _resultPreview = null;
        _previewError = '$e';
        _previewing = false;
      });
    }
  }

  // ── 저장 ──────────────────────────────────────────────
  Future<void> _saveZip() async {
    final files = _files;
    if (files.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _done = 0;
      _total = files.length;
      _lastResult = null;
      _status = '자르는 중…';
    });

    try {
      // 오버레이가 먼저 그려진 뒤 무거운 작업이 시작되도록 한 프레임 대기.
      await WidgetsBinding.instance.endOfFrame;

      final settings = _settings;
      final results = await BatchCropper.cropAll(
        files,
        settings,
        onProgress: (done, total, name) {
          if (!mounted) return;
          setState(() {
            _done = done;
            _total = total;
            _status = name;
          });
        },
      );

      if (!mounted) return;

      final entries = <({String name, Uint8List bytes})>[
        for (final result in results)
          if (result.bytes != null) (name: result.name, bytes: result.bytes!),
      ];
      final failed = results.where((r) => r.bytes == null).length;

      if (entries.isEmpty) {
        setState(() => _lastResult = '자르기에 성공한 사진이 없습니다.');
        _showSnack('자르기에 성공한 사진이 없습니다.');
        return;
      }

      await FileSaver.instance.saveFile(
        name: BatchCropper.zipBaseName(settings, entries.length),
        bytes: SpriteCropper.buildZip(entries),
        fileExtension: 'zip',
        mimeType: MimeType.zip,
      );

      if (!mounted) return;
      final message = failed == 0
          ? '${entries.length}장을 ZIP으로 저장했습니다.'
          : '${entries.length}장 저장, $failed장 실패했습니다.';
      setState(() => _lastResult = message);
      _showSnack(message);
    } catch (e) {
      if (mounted) {
        setState(() => _lastResult = 'ZIP 저장에 실패했습니다: $e');
        _showSnack('ZIP 저장에 실패했습니다: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── UI ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveZip,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveZip,
      },
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: const Text('다중 이미지 일괄 자르기'),
              backgroundColor: _accent[700],
              foregroundColor: Colors.white,
            ),
            body: _files.isEmpty ? _buildEmptyState() : _buildEditor(),
          ),
          if (_busy)
            _ProcessingOverlay(
              done: _done,
              total: _total,
              status: _status,
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 96, color: _accent[200]),
          const SizedBox(height: 16),
          Text(
            '자를 사진을 여러 장 선택해 주세요',
            style: theme.textTheme.titleMedium?.copyWith(color: _accent[700]),
          ),
          const SizedBox(height: 8),
          Text(
            '선택한 모든 사진에 같은 크기로 가운데 정렬 자르기합니다.\n'
            '지정한 크기가 원본보다 크면 자동으로 확대한 뒤 자릅니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: _accent[400]),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _pickFiles,
            icon: const Icon(Icons.folder_open),
            label: const Text('사진 선택'),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final controls = _buildControls();
        final preview = _buildPreview();

        if (wide) {
          return Row(
            children: [
              SizedBox(width: 340, child: controls),
              const VerticalDivider(width: 1),
              Expanded(child: preview),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: preview),
            const Divider(height: 1),
            SizedBox(height: 280, child: controls),
          ],
        );
      },
    );
  }

  Widget _buildControls() {
    final theme = Theme.of(context);
    final current = _current;
    final upscaling = current != null &&
        (_settings.width > current.width || _settings.height > current.height);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(Icons.photo_library, size: 20, color: _accent[700]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '사진 ${_files.length}장',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _pickFiles,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('추가'),
            ),
            IconButton(
              onPressed: _busy ? null : _clearFiles,
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '전체 비우기',
            ),
          ],
        ),
        if (current != null)
          Text(
            '기준: ${current.name}  •  ${current.width}×${current.height} px',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        const Divider(height: 32),

        _label('자르기 크기'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _sizeField(_widthField, _widthController, _widthFocus, '가로')),
            const SizedBox(width: 12),
            Expanded(child: _sizeField(_heightField, _heightController, _heightFocus, '세로')),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _settings.isCentered
              ? '모든 사진에 ${_settings.label} px 로 가운데 정렬 자르기'
              : '모든 사진에 ${_settings.label} px 로 ${_settings.positionLabel} 위치 자르기',
          style: theme.textTheme.bodySmall,
        ),
        if (upscaling)
          Text(
            '기준 사진보다 큰 크기입니다. 자동으로 확대한 뒤 자릅니다.',
            style: theme.textTheme.bodySmall?.copyWith(color: _accent[700]),
          ),
        const SizedBox(height: 16),

        _label('자르기 위치'),
        const SizedBox(height: 2),
        Text(
          '사각형 안을 드래그해 원하는 위치로 옮길 수 있습니다.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        _positionSlider(
          '가로',
          Icons.swap_horiz,
          _settings.offsetX,
          (v) => _applySettings(_settings.copyWith(offsetX: v)),
        ),
        _positionSlider(
          '세로',
          Icons.swap_vert,
          _settings.offsetY,
          (v) => _applySettings(_settings.copyWith(offsetY: v)),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _busy || _interacting || _settings.isCentered
                  ? null
                  : () => _applySettings(_settings.withCentered()),
              icon: const Icon(Icons.center_focus_strong, size: 18),
              label: const Text('가운데로'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildResultPreview(),
        const Divider(height: 32),

        _label('저장'),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _saveZip,
          icon: const Icon(Icons.folder_zip),
          label: Text('ZIP으로 저장 (${_files.length}장)'),
        ),
        const SizedBox(height: 4),
        Text('Ctrl+S 로도 저장할 수 있습니다.', style: theme.textTheme.bodySmall),
        if (_lastResult != null) ...[
          const SizedBox(height: 8),
          Text(
            _lastResult!,
            style: theme.textTheme.bodySmall?.copyWith(color: _accent[700]),
          ),
        ],
      ],
    );
  }

  Widget _label(String text) =>
      Text(text, style: Theme.of(context).textTheme.labelLarge);

  Widget _sizeField(
    int field,
    TextEditingController controller,
    FocusNode focusNode,
    String label,
  ) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: !_busy,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'px',
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: field == _widthField ? _onWidthChanged : _onHeightChanged,
      onSubmitted: (_) => _syncControllers(),
    );
  }

  /// 위치(오프셋) 슬라이더 한 줄.
  Widget _positionSlider(
    String label,
    IconData icon,
    double value,
    ValueChanged<double> onChanged,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: _accent[600]),
        const SizedBox(width: 6),
        SizedBox(
          width: 30,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(-1.0, 1.0),
            min: -1,
            max: 1,
            onChanged: _busy ? null : onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  /// 실제로 잘린 결과를 보여주는 미리보기 (선택한 사진 1장 기준).
  Widget _buildResultPreview() {
    final base = 220.0;
    final ratio = _settings.aspectRatio <= 0 ? 1.0 : _settings.aspectRatio;
    final boxWidth = ratio >= 1 ? base : base * ratio;
    final boxHeight = ratio >= 1 ? base / ratio : base;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '결과 미리보기 (${_settings.label} px)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Container(
          height: 170,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _accent.shade200),
          ),
          child: _previewing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : (_previewError != null
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _previewError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _accent[700], fontSize: 12),
                      ),
                    )
                  : (_resultPreview == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.all(8),
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: boxWidth,
                              height: boxHeight,
                              child: Image.memory(
                                _resultPreview!,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.medium,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                        ))),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final current = _current;
    if (current == null) return const SizedBox.shrink();

    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.black12,
            padding: const EdgeInsets.all(16),
            child: Center(
              child: BatchCropCanvas(
                imageBytes: current.bytes,
                imageWidth: current.width,
                imageHeight: current.height,
                settings: _settings,
                onCropSizeChanged: _applySettings,
                onInteractionStart: _onInteractionStart,
                onInteractionEnd: _onInteractionEnd,
                interactive: !_busy,
                accent: _accent,
              ),
            ),
          ),
        ),
        _buildThumbnailStrip(),
      ],
    );
  }

  /// 기준 사진을 고르는 하단 썸네일 목록.
  Widget _buildThumbnailStrip() {
    final theme = Theme.of(context);
    return Container(
      height: 118,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _accent.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '사각형을 조절할 기준 사진 선택 (${_files.length}장)',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _files.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _buildThumbnail(index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(int index) {
    final file = _files[index];
    final selected = index == _selectedIndex;

    return GestureDetector(
      onTap: _busy ? null : () => _selectFile(index),
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _accent : Colors.black12,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: _thumbnailWidget(file),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${file.width}×${file.height}',
                  style: Theme.of(context).textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            // 선택된 사진에만 표시되는 제거 버튼
            if (selected)
              Positioned(
                top: 0,
                right: 0,
                child: Tooltip(
                  message: '목록에서 빼기',
                  child: InkWell(
                    onTap: _busy ? null : () => _removeFile(index),
                    borderRadius: BorderRadius.circular(11),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 썸네일 위젯: 캐시된 작은 PNG를 쓰고, 아직 없으면 플레이스홀더를 보여준다.
  Widget _thumbnailWidget(BatchSourceFile file) {
    final thumb = _thumbPngs[file];
    if (thumb != null) {
      return Image.memory(
        thumb,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
      );
    }
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        size: 24,
        color: Colors.black26,
      ),
    );
  }

  /// 불러온 사진들의 썸네일을 엔진으로 한 번씩 만들어 캐시한다.
  ///
  /// 원본(수 MB)을 목록 리빌드마다 디코딩하는 대신, 작은 PNG로 줄여 한 번만
  /// 만든다. 사진이 많아도 이벤트 루프를 돌며 조금씩 처리해 UI가 멈추지 않게
  /// 한다.
  Future<void> _generateThumbnails() async {
    if (_thumbsBusy) return;
    _thumbsBusy = true;
    try {
      for (final file in [..._files]) {
        if (!mounted) return;
        if (_thumbPngs.containsKey(file)) continue;
        try {
          final png = await ImageEngine.thumbnailPng(file.bytes, targetWidth: 360);
          if (!mounted) return;
          setState(() => _thumbPngs[file] = png);
        } catch (_) {
          // 썸네일 생성 실패는 무시하고 플레이스홀더를 유지한다.
        }
        // 한 장마다 이벤트 루프를 돌려 진행 중인 UI 갱신을 방해하지 않는다.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _thumbsBusy = false;
    }
  }

  void _selectFile(int index) {
    if (index < 0 || index >= _files.length || index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    _schedulePreview();
  }
}

/// 저장 등 무거운 작업 중: 화면 전체를 덮고 진행률을 보여주는 오버레이.
class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay({
    required this.done,
    required this.total,
    required this.status,
  });

  final int done;
  final int total;

  /// 현재 처리 중인 파일명 (비어 있으면 일반 메시지).
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio =
        total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0).toDouble();

    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 280, maxWidth: 380),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(strokeWidth: 4),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        status.isEmpty ? '처리 중입니다…' : status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text('$done / $total', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: ratio, minHeight: 6),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
