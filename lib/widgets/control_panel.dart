import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/crop_settings.dart';

class ControlPanel extends StatelessWidget {
  const ControlPanel({
    super.key,
    required this.fileName,
    required this.imageWidth,
    required this.imageHeight,
    required this.settings,
    required this.busy,
    required this.removeBg,
    required this.horizontalController,
    required this.verticalController,
    required this.topPaddingController,
    required this.bottomPaddingController,
    required this.leftPaddingController,
    required this.rightPaddingController,
    required this.onPickImage,
    required this.onRemoveBgChanged,
    required this.onSettingsChanged,
    required this.onManualModeChanged,
    required this.onResetBoundaries,
    required this.onSave,
    required this.colBoundaryControllers,
    required this.rowBoundaryControllers,
  });

  final String? fileName;
  final int? imageWidth;
  final int? imageHeight;
  final CropSettings settings;
  final bool busy;
  final bool removeBg;

  final TextEditingController horizontalController;
  final TextEditingController verticalController;
  final TextEditingController topPaddingController;
  final TextEditingController bottomPaddingController;
  final TextEditingController leftPaddingController;
  final TextEditingController rightPaddingController;

  final VoidCallback onPickImage;
  final ValueChanged<bool> onRemoveBgChanged;
  final void Function({
  int? horizontalCount,
  int? verticalCount,
  double? topPadding,
  double? bottomPadding,
  double? leftPadding,
  double? rightPadding,
  List<int>? columnBoundaries,
  List<int>? rowBoundaries,
  }) onSettingsChanged;
  final ValueChanged<bool> onManualModeChanged;
  final VoidCallback onResetBoundaries;
  final VoidCallback onSave;
  final List<TextEditingController> colBoundaryControllers;
  final List<TextEditingController> rowBoundaryControllers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = Colors.blue[700]!;
    final hasImage = imageWidth != null && imageHeight != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 이미지 업로드 ────────────────────────────────
          FilledButton.icon(
            onPressed: busy ? null : onPickImage,
            icon: const Icon(Icons.upload_file),
            label: Text(hasImage ? '다른 이미지 선택' : '이미지 업로드'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          if (hasImage)
            _InfoTile(
              icon: Icons.image_outlined,
              title: fileName ?? '이미지',
              subtitle: '$imageWidth × $imageHeight px',
              iconColor: primaryColor,
            )
          else
            _InfoTile(
              icon: Icons.info_outline,
              title: 'PNG / JPG 스프라이트 시트를 불러오세요',
              subtitle: '이미지 전체가 가이드 박스가 되어 분할됩니다.',
              iconColor: primaryColor,
            ),
          const SizedBox(height: 12),
          const Divider(),

          // ── AI 배경 투명화 ────────────────────────────────
          Text('AI 배경 처리', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('AI 배경 제거 (누끼 따기)', style: TextStyle(fontSize: 14)),
            subtitle: const Text('브라우저 AI가 캐릭터 외의 배경을 자동으로 분석해 지웁니다.',
                style: TextStyle(fontSize: 11)),
            value: removeBg,
            onChanged: busy || !hasImage ? null : onRemoveBgChanged,
          ),
          const SizedBox(height: 8),
          const Divider(),

          // ── 분할 수 입력 ─────────────────────────────────
          Text('분할 수 (가로 × 세로)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  controller: horizontalController,
                  label: '가로 분할',
                  icon: Icons.grid_on,
                  suffixText: '개',
                  primaryColor: primaryColor,
                  onChanged: (v) => onSettingsChanged(horizontalCount: v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  controller: verticalController,
                  label: '세로 분할',
                  icon: Icons.grid_on,
                  suffixText: '개',
                  primaryColor: primaryColor,
                  onChanged: (v) => onSettingsChanged(verticalCount: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 분할 모드 ─────────────────────────────────
          Text('분할 모드', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('균등 분할'),
                icon: Icon(Icons.grid_on, size: 18),
              ),
              ButtonSegment(
                value: true,
                label: Text('수동 조절'),
                icon: Icon(Icons.tune, size: 18),
              ),
            ],
            selected: {settings.useManualBoundaries},
            onSelectionChanged: busy || !hasImage
                ? null
                : (selection) => onManualModeChanged(selection.first),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 12),

          // ── 균등 분할: 영역 여백 입력 ────────────────
          if (!settings.useManualBoundaries) ...[
            Text('영역 여백 (상단 / 하단)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    controller: topPaddingController,
                    label: '상단 여백',
                    icon: Icons.vertical_align_top,
                    suffixText: 'px',
                    primaryColor: primaryColor,
                    onChanged: (v) => onSettingsChanged(topPadding: v.toDouble()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NumberField(
                    controller: bottomPaddingController,
                    label: '하단 여백',
                    icon: Icons.vertical_align_bottom,
                    suffixText: 'px',
                    primaryColor: primaryColor,
                    onChanged: (v) => onSettingsChanged(bottomPadding: v.toDouble()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('영역 여백 (좌측 / 우측)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    controller: leftPaddingController,
                    label: '좌측 여백',
                    icon: Icons.arrow_left,
                    suffixText: 'px',
                    primaryColor: primaryColor,
                    onChanged: (v) => onSettingsChanged(leftPadding: v.toDouble()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NumberField(
                    controller: rightPaddingController,
                    label: '우측 여백',
                    icon: Icons.arrow_right,
                    suffixText: 'px',
                    primaryColor: primaryColor,
                    onChanged: (v) => onSettingsChanged(rightPadding: v.toDouble()),
                  ),
                ),
              ],
            ),
          ]

          // ── 수동 조절: 경계선 위치 입력 ───────────────
          else ...[
            Text(
              '가로 경계선 위치 (px)',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              '세로선 1개당 절대 좌표  •  0 ~ 이미지 폭',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < colBoundaryControllers.length; i++)
                  SizedBox(
                    width: 128,
                    child: _NumberField(
                      controller: colBoundaryControllers[i],
                      label: '가로 경계 ${i + 1}',
                      icon: Icons.swap_horiz,
                      suffixText: 'px',
                      primaryColor: primaryColor,
                      onChanged: (v) {
                        final updated = settings.withUpdatedColumnBoundary(
                          i,
                          v,
                          imageWidth: imageWidth!,
                        );
                        onSettingsChanged(
                          columnBoundaries: updated.columnBoundaries,
                          rowBoundaries: updated.rowBoundaries,
                        );
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '세로 경계선 위치 (px)',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              '가로선 1개당 절대 좌표  •  0 ~ 이미지 높이',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < rowBoundaryControllers.length; i++)
                  SizedBox(
                    width: 128,
                    child: _NumberField(
                      controller: rowBoundaryControllers[i],
                      label: '세로 경계 ${i + 1}',
                      icon: Icons.swap_vert,
                      suffixText: 'px',
                      primaryColor: primaryColor,
                      onChanged: (v) {
                        final updated = settings.withUpdatedRowBoundary(
                          i,
                          v,
                          imageHeight: imageHeight!,
                        );
                        onSettingsChanged(
                          columnBoundaries: updated.columnBoundaries,
                          rowBoundaries: updated.rowBoundaries,
                        );
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy ? null : onResetBoundaries,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('균등 간격으로 초기화'),
            ),
          ],
          const SizedBox(height: 12),

          // ── 미리보기 정보 ──────────────────────────────
          if (hasImage) ...[
            _InfoTile(
              icon: Icons.check_circle_outline,
              title: '전체 이미지: $imageWidth × $imageHeight px',
              subtitle: '1컷 크기: ${_spriteSizeInfo(imageWidth!, imageHeight!)}  •  '
                  '총 ${settings.totalCount}개',
              iconColor: primaryColor,
            ),
            const SizedBox(height: 12),
          ],
          const Divider(),

          // ── 저장 ───────────────────────────────────────
          FilledButton.icon(
            onPressed: busy || !hasImage ? null : onSave,
            icon: busy
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.download),
            label: Text(busy ? '처리 중…' : '저장 및 다운로드 (ZIP)'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'sprite_1.png ~ sprite_${settings.totalCount}.png 로 ZIP 저장',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 1컷 크기 문자열 (수동 모드면 최소~최대 범위 표시).
  String _spriteSizeInfo(int w, int h) {
    if (settings.useManualBoundaries) {
      final range = settings.frameSizeRange(imageWidth: w, imageHeight: h);
      if (range.minWidth == range.maxWidth && range.minHeight == range.maxHeight) {
        return '${range.maxWidth} × ${range.maxHeight} px';
      }
      return '${range.minWidth}×${range.minHeight} ~ ${range.maxWidth}×${range.maxHeight} px';
    }
    final sprite = settings.calcSpriteSize(imageWidth: w, imageHeight: h);
    return '${sprite.spriteWidth} × ${sprite.spriteHeight} px';
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.suffixText,
    required this.primaryColor,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String suffixText;
  final Color primaryColor;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffixText,
        prefixIcon: Icon(icon, size: 18, color: primaryColor),
        border: const OutlineInputBorder(),
        isDense: true,
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
      ),
      onChanged: (text) {
        final value = int.tryParse(text.trim());
        if (value != null) {
          onChanged(value);
        } else if (text.isEmpty) {
          onChanged(0);
        }
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.blue.withOpacity(0.15) : Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.blue.withOpacity(0.3) : Colors.blue[200]!,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor ?? Colors.blue[700]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}