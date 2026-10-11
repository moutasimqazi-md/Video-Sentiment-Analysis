/// How emotionally heavy a piece of content's tone is. Mirrors the web app (frontend/js/core/wellbeing.js) and the server
/// (backend/neurolens/wellbeing.py): keep the weights and thresholds in sync.
enum WellbeingLevel { calm, watch, high }

class Wellbeing {
  const Wellbeing(this.level, this.score, this.drivers);
  final WellbeingLevel level;
  final int score;
  final List<MapEntry<String, double>> drivers;

  static const _weights = {'depressed': 1.5, 'heartbroken': 1.2, 'sad': 1.2, 'lost': 1.0, 'angry': 0.8, 'tired': 0.5};
  static const _watch = 30.0, _high = 55.0;

  String get label => switch (level) {
        WellbeingLevel.calm => 'Calm',
        WellbeingLevel.watch => 'Worth a look',
        WellbeingLevel.high => 'High concern',
      };

  String get summary {
    final names = drivers.take(3).map((d) => d.key).join(', ');
    return switch (level) {
      WellbeingLevel.high => 'This carries a heavy emotional tone (${names.isEmpty ? 'negative' : names}). Consider watching it together and checking in.',
      WellbeingLevel.watch => 'Some heavier emotions show up (${names.isEmpty ? 'mixed' : names}). Worth a look if it is part of a pattern.',
      WellbeingLevel.calm => 'The overall tone is light or neutral. Nothing stands out.',
    };
  }

  static Wellbeing assess(Map<String, double> averages, String? dominant) {
    var score = 0.0;
    final drivers = <MapEntry<String, double>>[];
    _weights.forEach((mood, w) {
      final v = averages[mood] ?? 0;
      score += v * w;
      if (v >= 8) drivers.add(MapEntry(mood, v));
    });
    drivers.sort((a, b) => b.value.compareTo(a.value));
    var level = score >= _high ? WellbeingLevel.high : score >= _watch ? WellbeingLevel.watch : WellbeingLevel.calm;
    if (level == WellbeingLevel.calm && _weights.containsKey(dominant) && (averages[dominant] ?? 0) >= 35) level = WellbeingLevel.watch;
    return Wellbeing(level, score.round(), drivers);
  }
}

/// A week (or any span) of results for one profile.
class WellbeingRollup {
  WellbeingRollup(this.count, this.calm, this.watch, this.high, this.mix);
  final int count, calm, watch, high;
  final List<MapEntry<String, double>> mix;

  int get heavyShare => count == 0 ? 0 : (((watch + high) / count) * 100).round();
  WellbeingLevel get overall => high >= 1 || heavyShare >= 50 ? WellbeingLevel.high : watch >= 1 ? WellbeingLevel.watch : WellbeingLevel.calm;

  static WellbeingRollup of(Iterable<Map<String, double>> averagesList, Iterable<String?> dominants) {
    final list = averagesList.toList();
    final doms = dominants.toList();
    var calm = 0, watch = 0, high = 0;
    final mood = <String, double>{};
    for (var i = 0; i < list.length; i++) {
      switch (Wellbeing.assess(list[i], doms[i]).level) {
        case WellbeingLevel.calm:
          calm++;
        case WellbeingLevel.watch:
          watch++;
        case WellbeingLevel.high:
          high++;
      }
      list[i].forEach((m, v) => mood[m] = (mood[m] ?? 0) + v / list.length);
    }
    final mix = mood.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return WellbeingRollup(list.length, calm, watch, high, mix);
  }
}
