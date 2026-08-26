import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Rounds a raw "range / desired tick count" step to a human-friendly
/// interval (1/2/5 × a power of 10) so axis labels land on round numbers
/// and stay evenly, legibly spaced instead of fl_chart's default auto
/// interval occasionally crowding adjacent labels together.
double _niceInterval(double range, {int targetTicks = 4}) {
  if (range <= 0) return 1;
  final rough = range / targetTicks;
  final magnitude = math
      .pow(10, (math.log(rough) / math.ln10).floor())
      .toDouble();
  final residual = rough / magnitude;
  double niceResidual;
  if (residual < 1.5) {
    niceResidual = 1;
  } else if (residual < 3) {
    niceResidual = 2;
  } else if (residual < 7) {
    niceResidual = 5;
  } else {
    niceResidual = 10;
  }
  return niceResidual * magnitude;
}

/// Same idea as [_niceInterval] but for the calendar-day x-axis: picks the
/// smallest "round" day step (from a calendar-sensible list, not a plain
/// power of 10) that keeps the label count roughly constant regardless of
/// how long the date range is — a multi-year graph gets a multi-month
/// step instead of cramming dozens of month labels into the same width.
const List<double> _kNiceDaySteps = [
  1,
  2,
  3,
  7,
  14,
  30,
  60,
  90,
  180,
  365,
  730,
  1095,
];

double _niceDayInterval(double totalDays, {int targetTicks = 4}) {
  if (totalDays <= 0) return 1;
  final rough = totalDays / targetTicks;
  for (final step in _kNiceDaySteps) {
    if (step >= rough) return step;
  }
  return _kNiceDaySteps.last;
}

/// fl_chart always renders a label at the axis's exact min/max in addition
/// to the regular interval-based ticks — when that edge doesn't land on a
/// clean interval multiple, the forced edge label ends up just a few
/// pixels from the last regular one and visually overlaps it. This is a
/// last line of defense against that: suppress any label that would land
/// too close (as a fraction of the axis's visible range) to the last one
/// actually rendered, regardless of why fl_chart tried to draw it there.
bool _tooCloseToLast(double value, double? lastRendered, double axisRange) {
  if (lastRendered == null || axisRange <= 0) return false;
  return (value - lastRendered).abs() < axisRange * 0.12;
}

class ChartPoint {
  const ChartPoint({
    required this.date,
    required this.value,
    this.label,
    this.note,
    this.setsLabel,
  });
  final DateTime date;
  final double value;
  final String? label;

  /// Free-text note for this point's week (from the sheet's section-header
  /// row), shown in the tooltip under the weight/week.
  final String? note;

  /// Compact "sets × reps" summary for this point (e.g. "3×8"), shown in
  /// the tooltip when known. Null for legacy points logged before reps
  /// were tracked per set, or for non-exercise series (body weight,
  /// muscle-group aggregates).
  final String? setsLabel;
}

/// Compact fallback label (e.g. "Wk20 '24") for chart points whose exact
/// date isn't known — see `HistoryPoint.exactDateKnown`.
String approximateWeekLabel(int isoWeek, int isoYear) =>
    "Wk$isoWeek '${(isoYear % 100).toString().padLeft(2, '0')}";

/// A theme-aware, pinch-zoomable line chart plotted on a real calendar-time
/// x-axis (days since the earliest point), so an optional [secondaryPoints]
/// series (e.g. body weight) lines up correctly with [points] by date even
/// though the two are sampled on completely different schedules.
///
/// Two-finger pinch/pan zooms into a date range; both axes' numbers rescale
/// to whatever's currently visible (reusing the same "center on the
/// rightmost visible point" logic the unzoomed view uses, just fed the
/// visible subset instead of everything). Double-tap resets to full range.
class SimpleLineChart extends StatefulWidget {
  const SimpleLineChart({
    super.key,
    required this.points,
    required this.color,
    this.secondaryPoints,
    this.secondaryColor,
    this.secondaryFloor,
    this.secondaryCeiling,
  });

  final List<ChartPoint> points;
  final Color color;
  final List<ChartPoint>? secondaryPoints;
  final Color? secondaryColor;

  /// Fixed lower bound for the secondary (right) axis, used instead of the
  /// usual data-min-minus-padding when the data's own minimum is at or
  /// above it — e.g. body weight never needs to show all the way down to
  /// its lowest logged value, a sensible floor like 45kg reads better.
  final double? secondaryFloor;

  /// Fixed upper bound for the secondary (right) axis, mirroring
  /// [secondaryFloor] — used instead of data-max-plus-padding when the
  /// data's own maximum is at or below it.
  final double? secondaryCeiling;

  @override
  State<SimpleLineChart> createState() => _SimpleLineChartState();
}

class _SimpleLineChartState extends State<SimpleLineChart> {
  static const double _minVisibleDays = 3;

  /// Null = showing the full range (not zoomed). Both day-offset units,
  /// same as `xFor()` below.
  double? _visibleStart;
  double? _visibleSpan;

  double _chartWidth = 300;

  // Raw two-finger pinch tracking via Listener (not GestureDetector) — a
  // GestureDetector's scale recognizer competes with fl_chart's own
  // internal touch handling for tooltips in the same gesture arena, which
  // made zoom flaky (worked "half the time") and dropped/duplicated
  // updates. Listener never enters the arena — it just observes raw
  // pointer events alongside whatever else is listening — so single-finger
  // touches reach fl_chart untouched and two-finger pinch never has to
  // fight for the gesture.
  final Map<int, Offset> _activePointers = {};
  double? _pinchStartDistance;
  double _pinchGestureStartSpan = 0;
  double _pinchGestureStartValue = 0;

  // Cached each build so the pointer handlers (which run outside build())
  // can read the current range without threading it through closures.
  double _cachedTotalDays = 0;
  double _cachedMinSpan = 1;
  double _cachedVisibleStart = 0;
  double _cachedVisibleSpan = 1;

  void _onPointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    if (_activePointers.length == 2) {
      final pts = _activePointers.values.toList();
      _pinchStartDistance = (pts[0] - pts[1]).distance;
      _pinchGestureStartSpan = _cachedVisibleSpan;
      final focalX = (pts[0].dx + pts[1].dx) / 2;
      final focalFraction = (focalX / _chartWidth).clamp(0.0, 1.0);
      _pinchGestureStartValue =
          _cachedVisibleStart + focalFraction * _cachedVisibleSpan;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) return;
    _activePointers[event.pointer] = event.localPosition;
    if (_activePointers.length != 2 ||
        _pinchStartDistance == null ||
        _pinchStartDistance == 0) {
      return;
    }
    final pts = _activePointers.values.toList();
    final currentDistance = (pts[0] - pts[1]).distance;
    final currentFocalX = (pts[0].dx + pts[1].dx) / 2;
    final scale = currentDistance / _pinchStartDistance!;
    setState(() {
      final newSpan = (_pinchGestureStartSpan / scale).clamp(
        _cachedMinSpan,
        _cachedTotalDays,
      );
      final focalFraction = (currentFocalX / _chartWidth).clamp(0.0, 1.0);
      var newStart = _pinchGestureStartValue - focalFraction * newSpan;
      newStart = newStart.clamp(
        0.0,
        (_cachedTotalDays - newSpan).clamp(0.0, _cachedTotalDays),
      );
      _visibleStart = newStart;
      _visibleSpan = newSpan;
    });
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2) {
      _pinchStartDistance = null;
    }
  }

  void _resetZoom() => setState(() {
    _visibleStart = null;
    _visibleSpan = null;
  });

  @override
  void didUpdateWidget(covariant SimpleLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.points.length != widget.points.length ||
        (widget.points.isNotEmpty &&
            oldWidget.points.isNotEmpty &&
            (oldWidget.points.first.date != widget.points.first.date ||
                oldWidget.points.last.date != widget.points.last.date));
    if (changed) {
      setState(() {
        _visibleStart = null;
        _visibleSpan = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.length < 2) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Not enough data yet — log a few more sessions.'),
        ),
      );
    }

    final color = widget.color;
    final secondaryColor = widget.secondaryColor;
    final secondary = widget.secondaryPoints ?? const [];
    final allDates = [
      ...points.map((p) => p.date),
      ...secondary.map((p) => p.date),
    ]..sort();
    final minDate = allDates.first;
    final maxDate = allDates.last;
    final totalDays = maxDate.difference(minDate).inDays.toDouble();

    double xFor(DateTime date) => date.difference(minDate).inDays.toDouble();

    final minSpanDays = math.min(
      _minVisibleDays,
      totalDays == 0 ? 1.0 : totalDays,
    );
    final visibleStart = (_visibleStart ?? 0.0).clamp(0.0, totalDays);
    final visibleSpan = (_visibleSpan ?? (totalDays == 0 ? 1.0 : totalDays))
        .clamp(minSpanDays, totalDays == 0 ? 1.0 : totalDays);
    final visibleEnd = visibleStart + visibleSpan;

    _cachedTotalDays = totalDays == 0 ? 1.0 : totalDays;
    _cachedMinSpan = minSpanDays;
    _cachedVisibleStart = visibleStart;
    _cachedVisibleSpan = visibleSpan;

    List<ChartPoint> inWindow(List<ChartPoint> all) {
      final windowed = [
        for (final p in all)
          if (xFor(p.date) >= visibleStart - 0.001 &&
              xFor(p.date) <= visibleEnd + 0.001)
            p,
      ];
      return windowed.isEmpty ? all : windowed;
    }

    final visiblePrimary = inWindow(points);
    final visibleSecondary = inWindow(secondary);

    // Center the Y-axis on the rightmost *visible* point instead of a fixed
    // 0-based scale — the range is symmetric around that value, wide
    // enough to still show every visible point, so zooming or a big recent
    // improvement re-centers the window around it rather than just pinning
    // the line near the top.
    final primaryValues = visiblePrimary.map((p) => p.value).toList();
    final dataMin = primaryValues.reduce((a, b) => a < b ? a : b);
    final dataMax = primaryValues.reduce((a, b) => a > b ? a : b);
    final lastValue = visiblePrimary.last.value;
    var halfRange = (lastValue - dataMin).abs() > (dataMax - lastValue).abs()
        ? (lastValue - dataMin).abs()
        : (dataMax - lastValue).abs();
    if (halfRange == 0)
      halfRange = (lastValue.abs() * 0.1).clamp(1.0, double.infinity);
    halfRange *= 1.15; // breathing room so the line/dots don't touch the edges.
    final primaryMin = (lastValue - halfRange).clamp(0.0, double.infinity);
    final primaryMax = lastValue + halfRange;

    double? secondaryMin;
    double? secondaryMax;
    if (visibleSecondary.isNotEmpty) {
      final secondaryValues = visibleSecondary.map((p) => p.value);
      final rawMin = secondaryValues.reduce((a, b) => a < b ? a : b);
      final rawMax = secondaryValues.reduce((a, b) => a > b ? a : b);
      final pad = rawMax == rawMin ? 1.0 : (rawMax - rawMin) * 0.15;
      secondaryMin =
          widget.secondaryFloor != null && widget.secondaryFloor! <= rawMin
          ? widget.secondaryFloor
          : rawMin - pad;
      secondaryMax =
          widget.secondaryCeiling != null && widget.secondaryCeiling! >= rawMax
          ? widget.secondaryCeiling
          : rawMax + pad;
    }

    // Rescales a secondary-series value into the primary series' numeric
    // range so both lines share fl_chart's single Y coordinate system,
    // while the right-axis labels below map back to the real secondary
    // scale — this is what makes the two lines read as independent axes.
    double toPrimaryScale(double secondaryValue) {
      if (secondaryMin == null ||
          secondaryMax == null ||
          secondaryMax == secondaryMin) {
        return (primaryMin + primaryMax) / 2;
      }
      final t = (secondaryValue - secondaryMin) / (secondaryMax - secondaryMin);
      return primaryMin + t * (primaryMax - primaryMin);
    }

    double fromPrimaryScale(double primaryScaleValue) {
      if (secondaryMin == null || secondaryMax == null)
        return primaryScaleValue;
      final t = (primaryScaleValue - primaryMin) / (primaryMax - primaryMin);
      return secondaryMin + t * (secondaryMax - secondaryMin);
    }

    final primarySpots = [
      for (final p in points) FlSpot(xFor(p.date), p.value),
    ];
    final primaryByX = {for (final p in points) xFor(p.date): p};

    final secondarySpots = [
      for (final p in secondary) FlSpot(xFor(p.date), toPrimaryScale(p.value)),
    ];
    final secondaryByX = {for (final p in secondary) xFor(p.date): p};

    final monthFormat = DateFormat('MMM');
    final yearFormat = DateFormat('yyyy');
    final monthInterval = _niceDayInterval(visibleSpan);
    final primaryRange = primaryMax - primaryMin;
    // fl_chart generates ticks in the shared primary Y-coordinate space for
    // both left and right axes (there's only one underlying scale) — so
    // the right axis must use a primary-space interval too, even though
    // its labels are converted to secondary units via fromPrimaryScale.
    // Using a secondary-space interval here would desync the two and
    // produce far more ticks than intended.
    final primaryTickInterval = _niceInterval(primaryRange);

    double? lastLeftTick;
    double? lastRightTick;
    double? lastBottomTick;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 28, 16, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                _chartWidth = constraints.maxWidth > 0
                    ? constraints.maxWidth
                    : _chartWidth;
                return GestureDetector(
                  onDoubleTap: _resetZoom,
                  child: Listener(
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUpOrCancel,
                    onPointerCancel: _onPointerUpOrCancel,
                    child: LineChart(
                      LineChartData(
                        minY: primaryMin,
                        maxY: primaryMax,
                        minX: visibleStart,
                        maxX: visibleEnd,
                        lineBarsData: [
                          if (secondarySpots.length > 1)
                            LineChartBarData(
                              spots: secondarySpots,
                              isCurved: false,
                              color: (secondaryColor ?? color).withValues(
                                alpha: 0.28,
                              ),
                              barWidth: 2,
                              dotData: FlDotData(
                                show: true,
                                getDotPainter: (spot, percent, bar, index) =>
                                    FlDotCirclePainter(
                                      radius: 3,
                                      color: secondaryColor ?? color,
                                      strokeWidth: 0,
                                    ),
                              ),
                              belowBarData: BarAreaData(show: false),
                            ),
                          LineChartBarData(
                            spots: primarySpots,
                            isCurved: false,
                            color: color,
                            barWidth: 3,
                            dotData: const FlDotData(show: true),
                            belowBarData: BarAreaData(
                              show: true,
                              color: color.withValues(alpha: 0.15),
                            ),
                          ),
                        ],
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              interval: primaryTickInterval,
                              getTitlesWidget: (value, meta) {
                                if (_tooCloseToLast(
                                  value,
                                  lastLeftTick,
                                  primaryRange,
                                )) {
                                  return const SizedBox.shrink();
                                }
                                lastLeftTick = value;
                                return Text(
                                  value.toStringAsFixed(0),
                                  style: const TextStyle(fontSize: 11),
                                );
                              },
                            ),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: secondary.isNotEmpty,
                              interval: primaryTickInterval,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                if (_tooCloseToLast(
                                  value,
                                  lastRightTick,
                                  primaryRange,
                                )) {
                                  return const SizedBox.shrink();
                                }
                                lastRightTick = value;
                                final secondaryValue = fromPrimaryScale(value);
                                return Text(
                                  secondaryValue.toStringAsFixed(0),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: secondaryColor ?? color,
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              interval: monthInterval,
                              getTitlesWidget: (value, meta) {
                                if (_tooCloseToLast(
                                  value,
                                  lastBottomTick,
                                  visibleSpan,
                                )) {
                                  return const SizedBox.shrink();
                                }
                                lastBottomTick = value;
                                final date = minDate.add(
                                  Duration(days: value.round()),
                                );
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        monthFormat.format(date),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      Text(
                                        yearFormat.format(date),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        gridData: const FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        borderData: FlBorderData(show: false),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (touchedSpots) => touchedSpots.map((
                              s,
                            ) {
                              final isSecondary =
                                  s.barIndex == 0 && secondarySpots.isNotEmpty;
                              final point = isSecondary
                                  ? secondaryByX[s.x]
                                  : primaryByX[s.x];
                              final label =
                                  point?.label ??
                                  DateFormat('MMM d, yyyy').format(
                                    minDate.add(Duration(days: s.x.round())),
                                  );
                              final displayValue = point?.value ?? s.y;
                              final note = point?.note;
                              final setsLabel = isSecondary
                                  ? null
                                  : point?.setsLabel;
                              var text =
                                  '$label\n${displayValue.toStringAsFixed(1)}';
                              if (setsLabel != null && setsLabel.isNotEmpty) {
                                text += '\n🔁 $setsLabel';
                              }
                              if (note != null && note.isNotEmpty) {
                                text += '\n📝 $note';
                              }
                              return LineTooltipItem(
                                text,
                                const TextStyle(color: Colors.white),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (_visibleSpan != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton.icon(
              onPressed: _resetZoom,
              icon: const Icon(Icons.zoom_out_map, size: 16),
              label: const Text('Reset zoom'),
            ),
          ),
      ],
    );
  }
}
