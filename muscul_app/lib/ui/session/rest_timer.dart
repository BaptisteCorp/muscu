import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Visible rest countdown: starts when [start] is called via the controller.
/// Vibrates / displays "GO!" when finished.
class RestTimer extends StatefulWidget {
  final RestTimerController controller;
  const RestTimer({super.key, required this.controller});

  @override
  State<RestTimer> createState() => _RestTimerState();
}

class RestTimerController extends ChangeNotifier {
  int _remaining = 0;
  int _total = 0;
  int _lastTotal = 0;
  Timer? _timer;
  DateTime? _startedAt;
  DateTime? _finishedAt;

  int get remaining => _remaining;
  int get total => _total;
  int get lastTotal => _lastTotal;
  bool get isRunning => _timer != null;
  bool get justFinished {
    final f = _finishedAt;
    if (f == null) return false;
    return DateTime.now().difference(f).inSeconds < 10;
  }
  Duration? get elapsedSinceStart => _startedAt == null
      ? null
      : DateTime.now().difference(_startedAt!);

  /// Returns the rest seconds completed for the previous set when called.
  int captureAndStart(int seconds) {
    final prev = _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inSeconds;
    _stopTimerOnly();
    _total = seconds;
    _lastTotal = seconds;
    _remaining = seconds;
    _startedAt = DateTime.now();
    _finishedAt = null;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _remaining = (_remaining - 1).clamp(0, _total);
      if (_remaining == 0) {
        _stopTimerOnly();
        _finishedAt = DateTime.now();
        _onRestFinished();
      }
      notifyListeners();
    });
    notifyListeners();
    return prev;
  }

  /// Restart the timer with the previously used duration (or fallback).
  void restart([int? seconds]) {
    final s = seconds ?? (_lastTotal > 0 ? _lastTotal : 0);
    if (s <= 0) return;
    captureAndStart(s);
  }

  /// Skip the current countdown (jump to GO!).
  void skip() {
    _stopTimerOnly();
    _remaining = 0;
    _finishedAt = DateTime.now();
    notifyListeners();
  }

  /// Hide / clear the timer entirely.
  void stop() {
    _stopTimerOnly();
    _total = 0;
    _remaining = 0;
    _finishedAt = null;
    notifyListeners();
  }

  void _stopTimerOnly() {
    _timer?.cancel();
    _timer = null;
  }

  /// Strong haptic + system click when the rest timer hits zero, so the
  /// user notices even if their phone is screen-off in their gym bag.
  void _onRestFinished() {
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 250),
        HapticFeedback.heavyImpact);
    Future.delayed(const Duration(milliseconds: 500),
        HapticFeedback.heavyImpact);
    SystemSound.play(SystemSoundType.alert);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _RestTimerState extends State<RestTimer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncPulseAnimation();
  }

  void _onChange() {
    setState(() {});
    _syncPulseAnimation();
  }

  /// Pulse only when the timer is in a state that needs visual urgency:
  /// final 10 seconds, or just-finished "GO!" state. Otherwise stop the
  /// animation entirely so it doesn't burn battery during long rests or
  /// when idle.
  void _syncPulseAnimation() {
    final c = widget.controller;
    final isDone = c.total > 0 && c.remaining == 0;
    final isUrgent = c.remaining > 0 && c.remaining <= 10;
    final shouldPulse = isUrgent || (isDone && c.justFinished);
    if (shouldPulse) {
      if (!_pulseCtrl.isAnimating) {
        _pulseCtrl.repeat(reverse: true);
      }
    } else {
      if (_pulseCtrl.isAnimating) {
        _pulseCtrl.stop();
        _pulseCtrl.value = 0;
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final cs = Theme.of(context).colorScheme;

    // Idle (no rest in flight, no recent finish): compact strip with replay.
    if (c.total == 0 && !c.justFinished) {
      return _IdleStrip(
        canReplay: c.lastTotal > 0,
        onReplay: () => c.restart(),
      );
    }

    final isDone = c.remaining == 0;
    final pct = c.total == 0 ? 0.0 : 1.0 - c.remaining / c.total;
    final mm = (c.remaining ~/ 60).toString();
    final ss = (c.remaining % 60).toString().padLeft(2, '0');
    final tmm = (c.total ~/ 60).toString();
    final tss = (c.total % 60).toString().padLeft(2, '0');
    final isUrgent = c.remaining > 0 && c.remaining <= 10;

    final ringColor = isDone
        ? cs.tertiary
        : (isUrgent ? cs.secondary : cs.primary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) {
              final pulse = isUrgent || isDone
                  ? 1 + 0.06 * math.sin(_pulseCtrl.value * math.pi * 2)
                  : 1.0;
              return Transform.scale(
                scale: pulse,
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: CustomPaint(
                    painter: _RingPainter(
                      progress: isDone ? 1.0 : pct,
                      color: ringColor,
                      track: cs.surfaceContainerHigh,
                      strokeWidth: 5,
                    ),
                    child: Center(
                      child: isDone
                          ? Text(
                              'GO',
                              style: TextStyle(
                                color: ringColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            )
                          : Text(
                              '$mm:$ss',
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 16,
                                height: 1.0,
                                fontWeight: FontWeight.w900,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isDone ? 'PRÊT POUR LA SUIVANTE' : 'REPOS',
                  style: TextStyle(
                    color: isDone ? ringColor : cs.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isDone
                      ? 'Reprise — go !'
                      : 'sur $tmm:$tss',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (c.isRunning)
            _CircleIconButton(
              icon: Icons.skip_next_rounded,
              tooltip: 'Passer le repos',
              onPressed: c.skip,
            )
          else if (c.lastTotal > 0)
            _CircleIconButton(
              icon: Icons.replay_rounded,
              tooltip: 'Relancer le repos',
              onPressed: () => c.restart(),
            ),
        ],
      ),
    );
  }
}

class _IdleStrip extends StatelessWidget {
  final bool canReplay;
  final VoidCallback onReplay;
  const _IdleStrip({required this.canReplay, required this.onReplay});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.timer_outlined,
              size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              canReplay
                  ? 'Repos prêt — relance après ta série'
                  : 'Repos auto au prochain VALIDER',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (canReplay)
            _CircleIconButton(
              icon: Icons.replay_rounded,
              tooltip: 'Relancer le repos',
              onPressed: onReplay,
            ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.surfaceContainerHigh,
          ),
          child: Icon(icon, size: 22, color: cs.onSurface),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  final double strokeWidth;
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);
    if (progress <= 0) return;
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.track != track ||
      old.strokeWidth != strokeWidth;
}
