import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import '../models/system_snapshot.dart';
import '../theme/app_theme.dart';

/// The view selection only changes presentation; every poll samples all CPUs.
class CpuMonitorSection extends StatefulWidget {
  final SystemSnapshot snapshot;
  final List<SystemSnapshot> history;
  const CpuMonitorSection({
    super.key,
    required this.snapshot,
    required this.history,
  });

  @override
  State<CpuMonitorSection> createState() => _CpuMonitorSectionState();
}

class _CpuMonitorSectionState extends State<CpuMonitorSection> {
  static const _overall = 'overall';
  static const _all = 'all';
  String _selected = _overall;
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant CpuMonitorSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected != _overall &&
        _selected != _all &&
        !widget.snapshot.cpuCorePercent.keys.any(
          (id) => _selected == 'core:$id',
        )) {
      _selected = _overall;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final ids = snapshot.cpuCorePercent.keys.toList()..sort();
    final coreId = _selected.startsWith('core:')
        ? int.parse(_selected.substring(5))
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const LText(
              'CPU',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selected,
                  isExpanded: true,
                  isDense: true,
                  menuMaxHeight: 280,
                  dropdownColor: AppColors.card,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary, fontSize: 12),
                  items: [
                    const DropdownMenuItem(
                      value: _overall,
                      child: LText('Overall'),
                    ),
                    const DropdownMenuItem(
                      value: _all,
                      child: LText('All cores'),
                    ),
                    for (final id in ids)
                      DropdownMenuItem(
                        value: 'core:$id',
                        child: LText(LMessage('Core {0}', [id])),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _selected = value);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (ids.isNotEmpty)
          LText(
            LMessage('Logical cores: {0}', [ids.length]),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        const SizedBox(height: 6),
        if (coreId != null)
          _meter(
            snapshot.cpuCorePercent[coreId],
            widget.history.map((s) => s.cpuCorePercent[coreId]).toList(),
          )
        else
          _meter(
            snapshot.cpuPercent,
            widget.history
                .map((s) => s.cpuAvailable ? s.cpuPercent : null)
                .toList(),
          ),
        if (ids.isEmpty)
          const LText(
            'Per-core data unavailable',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        if (_selected == _all && ids.isNotEmpty) ...[
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = math.max(1, (constraints.maxWidth / 140).floor());
              final rows = (ids.length / columns).ceil();
              return SizedBox(
                height: math.min(rows * 90.0, 360.0),
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: GridView.builder(
                    controller: _scroll,
                    primary: false,
                    padding: const EdgeInsets.only(right: 8),
                    itemCount: ids.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: 82,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemBuilder: (_, index) {
                      final id = ids[index];
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: _meter(
                          snapshot.cpuCorePercent[id],
                          widget.history
                              .map((s) => s.cpuCorePercent[id])
                              .toList(),
                          coreId: id,
                          compact: true,
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _meter(
    double? percent,
    List<double?> values, {
    int? coreId,
    bool compact = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (coreId != null) ...[
              Expanded(
                child: LText(
                  LMessage('Core {0}', [coreId]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (percent != null)
              Text(
                '${percent.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: percent > 85 ? AppColors.red : AppColors.textPrimary,
                  fontSize: 11,
                ),
              )
            else
              Flexible(
                child: LText(
                  'Waiting for valid sample',
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: (percent ?? 0).clamp(0.0, 100.0) / 100,
            minHeight: 4,
            backgroundColor: AppColors.border,
            color: (percent ?? 0) > 85 ? AppColors.red : AppColors.accent,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: compact ? 20 : 32,
          width: double.infinity,
          child: CustomPaint(painter: _CpuTrendPainter(values)),
        ),
      ],
    );
  }
}

class _CpuTrendPainter extends CustomPainter {
  final List<double?> values;
  const _CpuTrendPainter(this.values);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = AppColors.border
        ..strokeWidth = 1,
    );
    if (values.length < 2) return;
    final path = Path();
    var connected = false;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null) {
        connected = false;
        continue;
      }
      final x = size.width * i / (values.length - 1);
      final y = size.height * (1 - value.clamp(0.0, 100.0) / 100);
      if (connected) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
      }
      connected = true;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_CpuTrendPainter oldDelegate) =>
      !listEquals(values, oldDelegate.values);
}
