import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

import '../services/color_bg_remover.dart';
import '../services/gif_splitter.dart';
import '../services/sprite_cropper.dart';

/// GIF 애니메이션을 프레임별 스프라이트로 분할하는 화면.
class GifSplitterScreen extends StatefulWidget {
  const GifSplitterScreen({super.key});

  @override
  State<GifSplitterScreen> createState() => _GifSplitterScreenState();
}

class _GifSplitterScreenState extends State<GifSplitterScreen> {
  String? _fileName;
  List<GifFrame> _frames = const [];

  /// 처리(배경 제거 + 트리밍)된 프레임. 옵션이 바뀔 때만 갱신한다.
  List<img.Image> _processed = const [];
  RgbColor? _bgColor;
  List<Uint8List> _previewBytes = const [];

  /// 파일 저장·GIF 로딩처럼 화면을 잠가야 하는 중인지.
  bool _busy = false;

  /// 옵션 변경으로 프레임을 다시 계산하는 중인지.
  /// 슬라이더 드래그를 방해하지 않도록 화면을 잠그지는 않는다.
  bool _processing = false;
  bool _removeBg = false;
  bool _autoTrim = true;
  double _bgTolerance = 0.1;
  SheetLayout _layout = SheetLayout.horizontal;

  /// 연속 옵션 변경 시 오래된 프레임 처리 결과를 버리기 위한 토큰.
  int _processToken = 0;

  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // ── 공통: 처리 중 오버레이를 띄우고 작업을 수행한다 ────
  ///
  /// 오버레이가 화면에 그려진 뒤(최소 한 프레임) 무거운 작업이 시작되도록
  /// 기다리기 때문에, 버튼을 누르는 순간 곧바로 화면이 잠기는 것을 확인할 수 있다.
  Future<void> _runTask(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // 오버레이가 렌더링된 뒤 작업이 시작되도록 한 프레임 대기한다.
      await WidgetsBinding.instance.endOfFrame;
      await task();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── GIF 업로드 ────────────────────────────────────────
  Future<void> _pickGif() async {
    if (_busy) return;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: 'GIF 파일 선택',
      );
      if (files.isEmpty) return;

      final file = files.first;
      setState(() => _busy = true);
      // 오버레이가 그려진 뒤 디코딩(무거운 작업)을 시작한다.
      await WidgetsBinding.instance.endOfFrame;

      final bytes = await file.readAsBytes();
      final frames = GifSplitter.decode(bytes);
      if (frames.isEmpty) {
        throw const FormatException('GIF에 프레임이 없습니다.');
      }

      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _frames = frames;
        _removeBg = false;
        _bgColor = null;
      });
      _scheduleProcess();
    } on FormatException catch (e) {
      if (mounted) _showSnack(e.message);
    } catch (e) {
      if (mounted) _showSnack('GIF를 불러오지 못했습니다: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 프레임 처리 (디바운스) ──────────────────────────────
  void _scheduleProcess() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _processFrames);
  }

  Future<void> _processFrames() async {
    if (_frames.isEmpty || _busy) return;

    // 연속으로 옵션이 바뀌면 오래된 작업 결과는 버린다.
    final token = ++_processToken;
    setState(() => _processing = true);
    try {
      // 진행 표시가 먼저 그려지도록 한 프레임 대기한다.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || token != _processToken) return;

      var images = [for (final f in _frames) f.image];

      if (_removeBg) {
        // 첫 프레임 기준으로 배경색을 감지해 모든 프레임에 동일 적용한다.
        final detected = _bgColor ??
            ColorBgRemover.detectBackgroundColor(
              images.first,
              borderRatio: 0.08,
            );
        if (detected == null) {
          if (mounted) {
            _showSnack('배경색을 감지하지 못했습니다. 단색 배경인지 확인해 주세요.');
          }
          return;
        }
        _bgColor = detected;
        images = [
          for (final image in images)
            ColorBgRemover.removeBackgroundFromImage(
              image,
              backgroundColor: detected,
              tolerance: _bgTolerance,
            ),
        ];
      }

      // 투명 영역 자동 제거: 전체 프레임의 공통 경계 상자를 기준으로 자른다.
      if (_autoTrim) {
        final bounds = GifSplitter.contentBounds(images);
        if (bounds != null) {
          images = GifSplitter.cropFrames(images, bounds: bounds);
        }
      }

      if (!mounted || token != _processToken) return;
      setState(() {
        _processed = images;
        _previewBytes = [
          for (final image in images) Uint8List.fromList(img.encodePng(image)),
        ];
      });
    } catch (e) {
      if (mounted) _showSnack('프레임 처리에 실패했습니다: $e');
    } finally {
      if (mounted && token == _processToken) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _onToggleBackgroundRemoval(bool enable) async {
    setState(() {
      _removeBg = enable;
      if (!enable) _bgColor = null;
    });
    _scheduleProcess();
  }

  // ── 저장 ───────────────────────────────────────────────
  String get _baseName => SpriteCropper.sanitizeName(
        _fileName?.replaceAll(RegExp(r'\.[^.]+$'), '') ?? 'sprite',
      );

  Future<void> _saveSheet() async {
    if (_processed.isEmpty) return;
    await _runTask(() async {
      try {
        final bytes = GifSplitter.encodeSheet(_processed, layout: _layout);
        await FileSaver.instance.saveFile(
          name: '${_baseName}_sheet',
          bytes: bytes,
          fileExtension: 'png',
          mimeType: MimeType.png,
        );
        if (!mounted) return;
        _showSnack('스프라이트 시트를 저장했습니다. (${_processed.length}컷)');
      } catch (e) {
        if (!mounted) return;
        _showSnack('시트 저장에 실패했습니다: $e');
      }
    });
  }

  Future<void> _saveZip() async {
    if (_processed.isEmpty) return;
    await _runTask(() async {
      try {
        final names = GifSplitter.frameFileNames(
          namePrefix: _baseName,
          count: _processed.length,
        );
        final entries = <({String name, Uint8List bytes})>[
          for (var i = 0; i < _processed.length; i++)
            (
              name: names[i],
              bytes: Uint8List.fromList(img.encodePng(_processed[i])),
            ),
        ];

        final cellW = _processed.map((e) => e.width).reduce((a, b) => a > b ? a : b);
        final cellH = _processed.map((e) => e.height).reduce((a, b) => a > b ? a : b);

        // stage.jpg 배경 이미지를 ZIP에 포함 (없으면 생략)
        List<({String name, Uint8List bytes})>? extraFiles;
        try {
          final stage = await rootBundle.load('assets/images/stage.jpg');
          extraFiles = [
            (name: 'stage.jpg', bytes: stage.buffer.asUint8List()),
          ];
        } catch (_) {
          extraFiles = null;
        }

        final zip = SpriteCropper.buildZip(
          entries,
          extraFiles: extraFiles,
          previewHtml: SpriteCropper.buildPreviewHtml(
            frameNames: names,
            spriteWidth: cellW,
            spriteHeight: cellH,
          ),
        );

        await FileSaver.instance.saveFile(
          name: '${_baseName}_frames',
          bytes: zip,
          fileExtension: 'zip',
          mimeType: MimeType.zip,
        );
        if (!mounted) return;
        _showSnack('${entries.length}개 프레임을 ZIP으로 저장했습니다.');
      } catch (e) {
        if (!mounted) return;
        _showSnack('ZIP 저장에 실패했습니다: $e');
      }
    });
  }

  Future<void> _saveGif() async {
    if (_processed.isEmpty) return;
    await _runTask(() async {
      try {
        final encoder = img.GifEncoder()..repeat = 0;
        for (var i = 0; i < _processed.length; i++) {
          // duration은 1/100초 단위
          final cs = (_frames[i].durationMs / 10).round().clamp(2, 65535);
          encoder.addFrame(_processed[i], duration: cs);
        }
        final bytes = Uint8List.fromList(encoder.finish()!);
        await FileSaver.instance.saveFile(
          name: _baseName,
          bytes: bytes,
          fileExtension: 'gif',
          mimeType: MimeType.gif,
        );
        if (!mounted) return;
        _showSnack('GIF를 다시 저장했습니다.');
      } catch (e) {
        if (!mounted) return;
        _showSnack('GIF 저장에 실패했습니다: $e');
      }
    });
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
    final primary = Colors.teal[700]!;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('GIF 스프라이트 분할'),
            backgroundColor: primary,
            foregroundColor: Colors.white,
          ),
          body: Stack(
            children: [
              _frames.isEmpty ? _buildEmptyState() : _buildEditor(),
              // 옵션 변경으로 프레임을 다시 계산하는 중 (슬라이더 조작은 계속 가능)
              if (_processing && !_busy)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _SlimProgressBar(),
                ),
            ],
          ),
        ),
        // 저장 등 무거운 작업 중: 화면 전체를 회색으로 덮고 입력을 차단한다.
        if (_busy) const _ProcessingOverlay(),
      ],
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.gif_box_outlined, size: 96, color: Colors.teal[200]),
          const SizedBox(height: 16),
          Text(
            'GIF 파일을 선택해 주세요',
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.teal[700]),
          ),
          const SizedBox(height: 8),
          Text(
            'GIF의 모든 프레임을 개별 스프라이트 PNG로 나누거나\n'
            '하나의 스프라이트 시트로 합쳐서 저장할 수 있습니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.teal[400]),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _pickGif,
            icon: const Icon(Icons.folder_open),
            label: const Text('GIF 선택'),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    final totalMs = _frames.fold<int>(0, (sum, f) => sum + f.durationMs);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final controls = _buildControls(totalMs);

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
            controls,
          ],
        );
      },
    );
  }

  Widget _buildControls(int totalMs) {
    final theme = Theme.of(context);
    final cellW = _processed.isEmpty
        ? 0
        : _processed.map((e) => e.width).reduce((a, b) => a > b ? a : b);
    final cellH = _processed.isEmpty
        ? 0
        : _processed.map((e) => e.height).reduce((a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(Icons.movie, size: 20, color: Colors.teal[700]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _fileName ?? 'GIF',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _pickGif,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('변경'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${_frames.length} 프레임  •  ${_frames.first.width}×${_frames.first.height} px  •  '
          '길이 ${(totalMs / 1000).toStringAsFixed(2)}초',
          style: theme.textTheme.bodySmall,
        ),
        if (_processed.isNotEmpty)
          Text(
            '1컷: $cellW × $cellH px',
            style: theme.textTheme.bodySmall,
          ),
        const Divider(height: 32),

        _label('시트 레이아웃'),
        const SizedBox(height: 8),
        SegmentedButton<SheetLayout>(
          segments: [
            for (final layout in SheetLayout.values)
              ButtonSegment(value: layout, label: Text(layout.label)),
          ],
          selected: {_layout},
          onSelectionChanged: (s) => setState(() => _layout = s.first),
        ),
        const Divider(height: 32),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('투명 영역 자동 제거'),
          subtitle: const Text('모든 프레임의 불투명 영역만 남깁니다'),
          value: _autoTrim,
          onChanged: _busy
              ? null
              : (v) {
                  setState(() => _autoTrim = v);
                  _scheduleProcess();
                },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('단색 배경 제거'),
          subtitle: Text(
            _bgColor == null
                ? '가장자리 색을 자동 감지합니다'
                : '배경색 RGB(${_bgColor!.r}, ${_bgColor!.g}, ${_bgColor!.b})',
          ),
          value: _removeBg,
          onChanged: _busy ? null : _onToggleBackgroundRemoval,
        ),
        if (_removeBg) ...[
          Text('허용 오차: ${(_bgTolerance * 100).round()}%'),
          Slider(
            value: _bgTolerance,
            min: 0.01,
            max: 0.5,
            onChanged: _busy
                ? null
                : (v) {
                    setState(() => _bgTolerance = v);
                    _scheduleProcess();
                  },
          ),
        ],
        const Divider(height: 32),

        _label('저장'),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _saveSheet,
          icon: const Icon(Icons.grid_on),
          label: const Text('스프라이트 시트 (PNG)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _saveZip,
          icon: const Icon(Icons.folder_zip),
          label: const Text('프레임 PNG 모음 (ZIP)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _saveGif,
          icon: const Icon(Icons.gif),
          label: const Text('GIF 다시 저장'),
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: Theme.of(context).textTheme.labelLarge,
      );

  Widget _buildPreview() {
    if (_previewBytes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final cellW = _processed.map((e) => e.width).reduce((a, b) => a > b ? a : b);
    final cellH = _processed.map((e) => e.height).reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.black12,
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _Checkerboard(
                child: _AnimatedPreview(
                  key: ValueKey(_previewBytes.length),
                  frames: _previewBytes,
                  cellSize: (width: cellW, height: cellH),
                ),
              ),
            ),
          ),
        ),
        _buildSheetPreview(),
      ],
    );
  }

  /// 합쳐질 스프라이트 시트 모양을 미리 보여준다.
  Widget _buildSheetPreview() {
    final cellW = _processed.map((e) => e.width).reduce((a, b) => a > b ? a : b);
    final cellH = _processed.map((e) => e.height).reduce((a, b) => a > b ? a : b);
    final count = _processed.length;
    final columns = switch (_layout) {
      SheetLayout.horizontal => count,
      SheetLayout.vertical => 1,
      SheetLayout.grid => (count <= 0 ? 1 : _ceilSqrt(count)),
    };
    final rows = (count / columns).ceil().clamp(1, 1 << 30);

    return Container(
      height: 120,
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.teal[200]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '시트 결과: ${cellW * columns} × ${cellH * rows} px  '
            '($columns×$rows = $count컷)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: CustomPaint(
                size: Size(cellW * columns * 0.15, cellH * rows * 0.15),
                painter: _SheetGridPainter(
                  columns: columns,
                  rows: rows,
                  color: Colors.teal[300]!,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static int _ceilSqrt(int n) {
    var x = 1;
    while (x * x < n) {
      x++;
    }
    return x;
  }
}

/// 화면 상단에 얇게 나타나는 진행 바.
///
/// 슬라이더 드래그를 방해하지 않으면서, 프레임 재계산 중임을 알려준다.
class _SlimProgressBar extends StatelessWidget {
  const _SlimProgressBar();

  @override
  Widget build(BuildContext context) {
    return const LinearProgressIndicator(
      minHeight: 3,
      backgroundColor: Colors.transparent,
    );
  }
}

/// 처리 중 화면 전체를 회색으로 덮고, 중앙에 진행 표시기를 보여주는 오버레이.
///
/// [AbsorbPointer]로 하위 위젯의 모든 터치/포인터 이벤트를 가로막아,
/// 처리 중에는 어떤 버튼도 눌리지 않도록 한다.
class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay({this.message = '처리 중입니다…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          // 하위 UI가 회색으로 비쳐 보이도록 반투명 회색 배경을 덮는다.
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 260, maxWidth: 340),
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
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 16),
                      // 전체 길이의 게이지 바 (진행률은 결정할 수 없으므로 indeterminate)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: const LinearProgressIndicator(minHeight: 6),
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

/// 프레임을 순환 재생하는 미리보기 위젯.
class _AnimatedPreview extends StatefulWidget {
  const _AnimatedPreview({super.key, required this.frames, required this.cellSize});

  final List<Uint8List> frames;
  final ({int width, int height}) cellSize;

  @override
  State<_AnimatedPreview> createState() => _AnimatedPreviewState();
}

class _AnimatedPreviewState extends State<_AnimatedPreview> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant _AnimatedPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frames.length != widget.frames.length) {
      _index = 0;
      _start();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    if (widget.frames.length < 2) return;
    _timer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => setState(() => _index = (_index + 1) % widget.frames.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.frames.isEmpty) return const SizedBox.shrink();

    // 원본 비율을 유지하면서 큰 사이즈로 확대한다 (픽셀 아트 선명화).
    final scale = 400 / (widget.cellSize.width == 0 ? 1 : widget.cellSize.width);
    return Image.memory(
      widget.frames[_index],
      gaplessPlayback: true,
      filterQuality: FilterQuality.none,
      width: widget.cellSize.width * scale,
      height: widget.cellSize.height * scale,
    );
  }
}

/// 투명 배경 확인용 체커보드.
class _Checkerboard extends StatelessWidget {
  const _Checkerboard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE0E0E0), Color(0xFFBDBDBD)],
          tileMode: TileMode.repeated,
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: child,
    );
  }
}

/// 시트 격자 미리보기용 페인터.
class _SheetGridPainter extends CustomPainter {
  _SheetGridPainter({required this.columns, required this.rows, required this.color});

  final int columns;
  final int rows;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / columns;
    final ch = size.height / rows;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var c = 0; c <= columns; c++) {
      canvas.drawLine(Offset(c * cw, 0), Offset(c * cw, size.height), paint);
    }
    for (var r = 0; r <= rows; r++) {
      canvas.drawLine(Offset(0, r * ch), Offset(size.width, r * ch), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SheetGridPainter oldDelegate) =>
      oldDelegate.columns != columns || oldDelegate.rows != rows;
}
