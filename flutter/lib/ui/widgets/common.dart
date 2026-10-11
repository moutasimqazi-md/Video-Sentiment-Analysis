import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/moods.dart';
import '../../core/wellbeing.dart';
import '../theme.dart';

class NlCard extends StatelessWidget {
  const NlCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap, this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final card = Card(color: color, child: Padding(padding: padding, child: child));
    if (onTap == null) return card;
    // one tappable item for screen readers, labelled by everything inside it
    return MergeSemantics(child: Semantics(button: true, child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: card)));
  }
}

enum Tone { neutral, green, amber, coral, blue }

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = Tone.neutral, this.icon});
  final String text;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg) = switch (tone) {
      Tone.green => (dark ? const Color(0xFF16342D) : NlColors.greenSoft, dark ? const Color(0xFF4CC9A0) : NlColors.green),
      Tone.amber => (dark ? const Color(0xFF3A3020) : NlColors.amberSoft, dark ? const Color(0xFFF0C068) : NlColors.amber),
      Tone.coral => (dark ? const Color(0xFF3A2328) : NlColors.coralSoft, dark ? const Color(0xFFFF9487) : NlColors.coralInk),
      Tone.blue => (dark ? const Color(0xFF1D2B52) : NlColors.blueSoft, dark ? const Color(0xFF9BB8FF) : const Color(0xFF2F5FD0)),
      Tone.neutral => (Theme.of(context).colorScheme.surfaceContainerHighest, Theme.of(context).colorScheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

Tone toneFor(WellbeingLevel l) => switch (l) { WellbeingLevel.calm => Tone.green, WellbeingLevel.watch => Tone.amber, WellbeingLevel.high => Tone.coral };

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            if (subtitle != null) Text(subtitle!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ]),
        ),
        if (trailing != null) ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.4), child: FittedBox(fit: BoxFit.scaleDown, child: trailing)),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title, text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(24)), child: Icon(icon, size: 34, color: t.colorScheme.primary)),
          const SizedBox(height: 18),
          Text(title, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(text, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

class ErrorNote extends StatelessWidget {
  const ErrorNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline, size: 20, color: t.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: t.colorScheme.onSecondaryContainer, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// A network image with the mood emoji underneath, shown if the image can't load.
class NetThumb extends StatelessWidget {
  const NetThumb({super.key, required this.url, required this.emoji, this.aspect = 3 / 4, this.radius = 16});
  final String? url;
  final String emoji;
  final double aspect, radius;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fallback = Container(color: t.colorScheme.surfaceContainerHighest, alignment: Alignment.center, child: Text(emoji, style: const TextStyle(fontSize: 34)));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: aspect,
        child: url == null
            ? fallback
            : Image.network(
                url!,
                fit: BoxFit.cover,
                headers: kIsWeb ? null : const {'ngrok-skip-browser-warning': '1'},
                loadingBuilder: (c, child, p) => p == null ? child : fallback,
                errorBuilder: (c, e, s) => fallback,
              ),
      ),
    );
  }
}

class MoodBars extends StatelessWidget {
  const MoodBars({super.key, required this.entries, this.labels, this.highlightFirst = true});
  final List<MapEntry<String, double>> entries;
  final Map<String, dynamic>? labels;
  final bool highlightFirst;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: MergeSemantics(child: Semantics(label: '${cap(entries[i].key)}, ${entries[i].value.toStringAsFixed(1)} percent', child: ExcludeSemantics(child: Row(children: [
              SizedBox(width: 30, child: Text(moodEmoji(entries[i].key), style: const TextStyle(fontSize: 20))),
              Expanded(
                flex: 5,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cap(entries[i].key), style: TextStyle(fontWeight: i == 0 && highlightFirst ? FontWeight.w800 : FontWeight.w600)),
                  Text(moodLabel(entries[i].key, labels), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              Expanded(
                flex: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(value: (entries[i].value / 100).clamp(0.0, 1.0), minHeight: 9, color: moodColor(entries[i].key), backgroundColor: t.colorScheme.surfaceContainerHighest),
                ),
              ),
              SizedBox(width: 52, child: Text('${entries[i].value.toStringAsFixed(1)}%', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            ])))),
          ),
      ],
    );
  }
}

/// A circular gauge with a big label in the middle.
class Ring extends StatelessWidget {
  const Ring({super.key, required this.fraction, required this.center, this.sub, this.size = 104, this.color});
  final double fraction;
  final String center;
  final String? sub;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      label: sub == null ? center : '$center $sub',
      child: ExcludeSemantics(
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.1, // the number has to fit inside the ring
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _RingPainter(fraction.clamp(0, 1), color ?? t.colorScheme.primary, t.colorScheme.surfaceContainerHighest),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(center, style: TextStyle(fontSize: size * 0.26, fontWeight: FontWeight.w800, height: 1)),
                  if (sub != null) Text(sub!, style: TextStyle(fontSize: size * 0.11, color: t.colorScheme.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.f, this.color, this.track);
  final double f;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.1;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = track);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * f, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.f != f || o.color != color;
}

/// The top moods over the length of a video.
class TimelineChart extends StatelessWidget {
  const TimelineChart({super.key, required this.timeline, required this.moodsToShow});
  final List<Map<String, double>> timeline;
  final List<String> moodsToShow;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(label: 'Emotion timeline chart for ${moodsToShow.map(cap).join(', ')}', image: true, child: SizedBox(height: 170, width: double.infinity, child: CustomPaint(painter: _TimelinePainter(timeline, moodsToShow, t.colorScheme.outlineVariant, t.colorScheme.onSurfaceVariant)))),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 6, children: [
        for (final m in moodsToShow)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: moodColor(m), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(cap(m), style: t.textTheme.bodySmall),
          ]),
      ]),
    ]);
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.tl, this.moodsToShow, this.grid, this.label);
  final List<Map<String, double>> tl;
  final List<String> moodsToShow;
  final Color grid, label;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0, bottom = 20.0, top = 8.0;
    final w = size.width - left - 6, h = size.height - bottom - top;
    final maxT = tl.isEmpty ? 1.0 : math.max(0.1, tl.last['t'] ?? 1);
    var maxV = 0.1;
    for (final f in tl) {
      for (final m in moodsToShow) {
        maxV = math.max(maxV, f[m] ?? 0);
      }
    }
    double x(double t) => left + (t / maxT) * w;
    double y(double v) => top + (1 - v / maxV) * h;
    final gp = Paint()..color = grid..strokeWidth = 1;
    for (final k in [0.0, 0.5, 1.0]) {
      final yy = y(maxV * k);
      canvas.drawLine(Offset(left, yy), Offset(size.width - 6, yy), gp);
      _text(canvas, '${(maxV * k * 100).round()}%', Offset(0, yy - 6), 11);
    }
    for (final k in [0.0, 0.5, 1.0]) {
      _text(canvas, '${(maxT * k).round()}s', Offset(x(maxT * k) - 8, size.height - 14), 11);
    }
    for (final m in moodsToShow) {
      final path = Path();
      var first = true;
      for (final f in tl) {
        final px = x(f['t'] ?? 0), py = y(f[m] ?? 0);
        if (first) {
          path.moveTo(px, py);
          first = false;
        } else {
          path.lineTo(px, py);
        }
      }
      canvas.drawPath(path, Paint()..color = moodColor(m)..style = PaintingStyle.stroke..strokeWidth = 2.6..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round);
    }
  }

  void _text(Canvas c, String s, Offset o, double size) {
    final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(color: label, fontSize: size)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(_TimelinePainter o) => o.tl != tl;
}
