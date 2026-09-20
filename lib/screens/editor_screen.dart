import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/crop_settings.dart';
import '../services/ai_bg_remover.dart';
import '../services/sprite_cropper.dart';
import '../widgets/control_panel.dart';
import '../widgets/image_canvas.dart';

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

  CropSettings _settings = const CropSettings(
    horizontalCount: 4,
    verticalCount: 1,
  );

  late final TextEditingController _horizontalController =
  TextEditingController(text: '${_settings.horizontalCount}');
  late final TextEditingController _verticalController =
  TextEditingController(text: '${_settings.verticalCount}');
  late final TextEditingController _topPaddingController =
  TextEditingController(text: '${_settings.topPadding.round()}');
  late final TextEditingController _bottomPaddingController =
  TextEditingController(text: '${_settings.bottomPadding.round()}');
late final TextEditingController _leftPaddingController =
  TextEditingController(text: '${_settings.leftPadding.round()}');
late final TextEditingController _rightPaddingController =
  TextEditingController(text: '${_settings.rightPadding.round()}');

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    _topPaddingController.dispose();
    _bottomPaddingController.dispose();
    _leftPaddingController.dispose();
    _rightPaddingController.dispose();
    super.dispose();
  }

  // ── 이미지 업로드 ────────────────────────────────────
  Future<void> _pickImage() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: '스프라이트 시트 이미지 선택',
      );

      if (files == null || files.isEmpty) return;

      final file = files.first;
      final bytes = await file.readAsBytes();
      final decoded = SpriteCropper.decode(bytes);

      if (!mounted) return;

      setState(() {
        _rawOriginalBytes = bytes;
        _sourceBytes = bytes;
        _decoded = decoded;
        _fileName = file.name;
        _removeBg = false;

        _settings = _settings.copyWith(
          topPadding: 0.0,
          bottomPadding: 0.0,
          leftPadding: 0.0,
          rightPadding: 0.0,
        );
        _topPaddingController.text = '0';
        _bottomPaddingController.text = '0';
        _leftPaddingController.text = '0';
        _rightPaddingController.text = '0';
      });
    } on FormatException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('이미지를 불러오지 못했습니다: $e');
    }
  }

  // ── AI 배경 제거 연동 처리 ─────────────────────────────
  Future<void> _toggleAiBackgroundRemoval(bool enable) async {
    final raw = _rawOriginalBytes;
    if (raw == null) return;

    if (!enable) {
      // 배경 제거 해제 시 원본 복원
      final decoded = SpriteCropper.decode(raw);
      setState(() {
        _removeBg = false;
        _sourceBytes = raw;
        _decoded = decoded;
      });
      return;
    }

    setState(() {
      _busy = true;
    });

    _showSnack('AI가 배경을 분석하여 지우는 중입니다… (최초 실행 시 모델 다운로드로 몇 초 소요)');

    try {
      final processedBytes = await AiBgRemover.removeBackground(raw);
      final decoded = SpriteCropper.decode(processedBytes);

      if (!mounted) return;
      setState(() {
        _removeBg = true;
        _sourceBytes = processedBytes;
        _decoded = decoded;
      });
      _showSnack('AI 배경 제거 완료!');
    } catch (e) {
      if (!mounted) return;
      _showSnack('AI 배경 제거 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _updateSettings(CropSettings nextSettings) {
    setState(() {
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
    });
  }

  Future<void> _saveZip() async {
    final bytes = _sourceBytes;
    if (bytes == null) {
      _showSnack('이미지를 먼저 업로드해 주세요.');
      return;
    }

    setState(() => _busy = true);
    try {
      final frames = SpriteCropper.cropFrames(
        sourceBytes: bytes,
        settings: _settings,
      );

      final decoded = _decoded!;
      final sprite = _settings.calcSpriteSize(
        imageWidth: decoded.width,
        imageHeight: decoded.height,
      );

      final zip = SpriteCropper.buildZip(
        frames,
        previewHtml: SpriteCropper.buildPreviewHtml(
          totalCount: _settings.totalCount,
          spriteWidth: sprite.spriteWidth,
          spriteHeight: sprite.spriteHeight,
        ),
      );

      await FileSaver.instance.saveFile(
        name: 'sprites',
        bytes: zip,
        fileExtension: 'zip',
        mimeType: MimeType.zip,
      );

      if (!mounted) return;
      _showSnack('${frames.length}개의 스프라이트를 sprites.zip으로 저장했습니다.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('저장에 실패했습니다: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 스프라이트 시트 분할 도구'),
        centerTitle: false,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
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
              horizontalController: _horizontalController,
              verticalController: _verticalController,
              topPaddingController: _topPaddingController,
              bottomPaddingController: _bottomPaddingController,
              leftPaddingController: _leftPaddingController,
              rightPaddingController: _rightPaddingController,
              onPickImage: _pickImage,
              onRemoveBgChanged: _toggleAiBackgroundRemoval,
              onSettingsChanged: ({
                int? horizontalCount,
                int? verticalCount,
                double? topPadding,
                double? bottomPadding,
                double? leftPadding,
                double? rightPadding,
              }) {
                _updateSettings(
                  _settings.copyWith(
                    horizontalCount: horizontalCount ?? _settings.horizontalCount,
                    verticalCount: verticalCount ?? _settings.verticalCount,
                    topPadding: topPadding ?? _settings.topPadding,
                    bottomPadding: bottomPadding ?? _settings.bottomPadding,
                    leftPadding: leftPadding ?? _settings.leftPadding,
                    rightPadding: rightPadding ?? _settings.rightPadding,
                  ),
                );
              },
              onSave: _saveZip,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildPreview()),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final bytes = _sourceBytes;
    final decoded = _decoded;
    if (bytes == null || decoded == null) {
      return const _EmptyState();
    }

    final sprite = _settings.calcSpriteSize(
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
              onSettingsChanged: _updateSettings,
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              border: Border(
                top: BorderSide(color: Colors.blue[200]!),
              ),
            ),
            child: Text(
              '전체: ${decoded.width} × ${decoded.height} px  •  '
                  '영역: $activeWidth × $activeHeight px (상: ${_settings.topPadding.round()}, 하: ${_settings.bottomPadding.round()}, 좌: ${_settings.leftPadding.round()}, 우: ${_settings.rightPadding.round()})  •  '
                  '1컷: ${sprite.spriteWidth} × ${sprite.spriteHeight} px  •  '
                  '총 ${_settings.totalCount}개 (${_settings.safeHorizontalCount}×${_settings.safeVerticalCount})',
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
          Icon(
            Icons.crop,
            size: 96,
            color: Colors.blue[200],
          ),
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