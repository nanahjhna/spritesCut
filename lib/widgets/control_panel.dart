import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/crop_settings.dart';

/// 좌측 설정 패널: 파란색 검수 테마, 업로드, 분할 수 입력, 저장 버튼.
class ControlPanel extends StatelessWidget {
  const ControlPanel({
    super.key,
    required this.fileName,
    required this.imageWidth,
    required this.imageHeight,
    required this.settings,
    required this.busy,
    required this.horizontalController,
    required this.verticalController,
    required this.onPickImage,
    required this.onSettingsChanged,
    required this.onSave,
  });

  final String? fileName;
  final int? imageWidth;
  final int? imageHeight;
  final CropSettings settings;
  final bool busy;

  final TextEditingController horizontalController;
  final TextEditingController verticalController;

  final VoidCallback onPickImage;
  final void Function({int? horizontalCount, int? verticalCount}) onSettingsChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            label: const Text('이미지 업로드'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 8),
          if (hasImage)
            _InfoTile(
              icon: Icons.image_outlined,
              title: fileName ?? '이미지',
              subtitle: '$imageWidth × $imageHeight px',
              iconColor: Colors.blue[700],
            )
          else
            _InfoTile(
              icon: Icons.info_outline,
              title: 'PNG / JPG 스프라이트 시트를 불러오세요',
              subtitle: '이미지 전체가 가이드 박스가 되어 분할됩니다.',
              iconColor: Colors.blue[700],
            ),
          const SizedBox(height: 12),
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
                  onChanged: (v) => onSettingsChanged(verticalCount: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 미리보기 정보 ──────────────────────────────
          if (hasImage) ...[
            _InfoTile(
              icon: Icons.check_circle_outline,
              title: '전체 이미지: $imageWidth × $imageHeight px',
              subtitle: '1컷 크기: ${_spriteWidth(imageWidth!)} × ${_spriteHeight(imageHeight!)} px  •  총 ${settings.totalCount}개',
              iconColor: Colors.blue[700],
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
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download),
            label: Text(busy ? '처리 중…' : '저장 및 다운로드 (ZIP)'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'sprite_1.png ~ sprite_${settings.totalCount}.png 로 ZIP 저장',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  int _spriteWidth(int w) => (w / settings.horizontalCount).round();
  int _spriteHeight(int h) => (h / settings.verticalCount).round();
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.suffixText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String suffixText;
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
        icon: Icon(icon, size: 18, color: Colors.blue[700]),
        border: const OutlineInputBorder(),
        isDense: true,
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
        ),
      ),
      onChanged: (text) {
        final value = int.tryParse(text.trim());
        if (value != null && value > 0) {
          onChanged(value);
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor ?? Colors.blue[700]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
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