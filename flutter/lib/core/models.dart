import 'wellbeing.dart';

Map<String, double> _numMap(dynamic m) {
  final out = <String, double>{};
  if (m is Map) {
    m.forEach((k, v) {
      if (v is num) out[k.toString()] = v.toDouble();
    });
  }
  return out;
}

/// One key moment (an evidence frame saved with an analysis). [url] is server-relative, e.g. `api/keyframes/<id>/0.jpg`.
class Keyframe {
  Keyframe({required this.url, required this.t, this.mood, this.score, this.flag});
  final String url;
  final double t;
  final String? mood;
  final double? score;
  final String? flag;

  factory Keyframe.fromJson(Map<String, dynamic> j) => Keyframe(
        url: j['url'] as String? ?? '',
        t: (j['t'] as num?)?.toDouble() ?? 0,
        mood: j['mood'] as String?,
        score: (j['score'] as num?)?.toDouble(),
        flag: j['flag'] as String?,
      );
}

class SafetyFlag {
  SafetyFlag({required this.label, required this.frames, required this.of, required this.score, required this.t});
  final String label;
  final int frames, of;
  final double score, t;
}

class Safety {
  Safety({required this.checked, required this.level, required this.flags, required this.framesChecked});
  final bool checked;
  final String level;
  final List<SafetyFlag> flags;
  final int framesChecked;
  bool get flagged => flags.isNotEmpty;
}

/// The analysis result the backend returns for a video or image. Kept as a thin typed view over the raw JSON.
class AnalysisResult {
  AnalysisResult(this.raw);
  final Map<String, dynamic> raw;

  String get kind => raw['kind'] as String? ?? 'video';
  bool get isImage => kind == 'image';
  String get dominant => raw['dominant_mood'] as String? ?? (averages.isEmpty ? '' : (averages.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key);
  Map<String, double> get averages => _numMap(raw['averages']);
  Map<String, double> get visualAverages => raw['visual_averages'] == null ? averages : _numMap(raw['visual_averages']);
  Map<String, dynamic> get moodLabels => (raw['mood_labels'] as Map?)?.cast<String, dynamic>() ?? const {};
  String get verdict => raw['verdict'] as String? ?? '';
  double get duration => (raw['duration_seconds'] as num?)?.toDouble() ?? 0;
  int get frames => (raw['frames_analyzed'] as num?)?.toInt() ?? 0;
  String? get sourceTitle => (raw['source'] as Map?)?['title'] as String?;
  String? get sourceUrl => (raw['source'] as Map?)?['url'] as String?;

  /// Sorted high to low.
  List<MapEntry<String, double>> ranked([Map<String, double>? from]) => (from ?? averages).entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  String? get confidenceLevel => (raw['confidence'] as Map?)?['level'] as String?;
  Map<String, dynamic> get audio => (raw['audio'] as Map?)?.cast<String, dynamic>() ?? const {'available': false};
  bool get audioAvailable => audio['available'] == true;
  Map<String, double> get audioAverages => _numMap(audio['averages']);
  Map<String, double> get colorMetrics => _numMap(raw['color_metrics']);

  /// Per-frame scores over time: each map has the mood keys plus `t` (seconds).
  List<Map<String, double>> get timeline => ((raw['timeline'] as List?) ?? const []).map((e) => _numMap(e)).toList();

  List<Keyframe> get keyframes => ((raw['keyframes'] as List?) ?? const []).whereType<Map>().map((e) => Keyframe.fromJson(e.cast<String, dynamic>())).toList();

  Safety? get safety {
    final s = raw['safety'];
    if (s is! Map) return null;
    return Safety(
      checked: s['checked'] == true,
      level: s['level'] as String? ?? 'clear',
      framesChecked: (s['frames_checked'] as num?)?.toInt() ?? 0,
      flags: ((s['flags'] as List?) ?? const [])
          .whereType<Map>()
          .map((f) => SafetyFlag(
                label: f['label'] as String? ?? 'Flagged',
                frames: (f['frames'] as num?)?.toInt() ?? 1,
                of: (f['of'] as num?)?.toInt() ?? 1,
                score: (f['score'] as num?)?.toDouble() ?? 0,
                t: (f['t'] as num?)?.toDouble() ?? 0,
              ))
          .toList(),
    );
  }

  Wellbeing get wellbeing => Wellbeing.assess(averages, dominant);

  /// Pacing from cuts per minute: Slow / Medium / Fast.
  String get pace {
    final cuts = colorMetrics['cuts_per_minute'] ?? 0;
    return cuts < 12 ? 'Slow' : cuts < 30 ? 'Medium' : 'Fast';
  }
}

/// One saved analysis in History.
class HistoryEntry {
  HistoryEntry({required this.id, required this.createdAt, required this.title, required this.profileId, required this.result, this.sourceUrl, this.feedback});
  final String id; // the server job id; the thumbnail lives at api/thumbnails/<id>.jpg
  final int createdAt; // ms since epoch
  final String title;
  final String profileId; // "me" or a child profile id
  final Map<String, dynamic> result;
  final String? sourceUrl;
  String? feedback;

  AnalysisResult get analysis => AnalysisResult(result);

  Map<String, dynamic> toJson() => {'id': id, 'createdAt': createdAt, 'title': title, 'profileId': profileId, 'result': result, 'sourceUrl': sourceUrl, 'feedback': feedback};

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id'] as String,
        createdAt: (j['createdAt'] as num).toInt(),
        title: j['title'] as String? ?? 'Untitled',
        profileId: j['profileId'] as String? ?? 'me',
        result: (j['result'] as Map).cast<String, dynamic>(),
        sourceUrl: j['sourceUrl'] as String?,
        feedback: j['feedback'] as String?,
      );
}

class ChildProfile {
  ChildProfile({required this.id, required this.name, this.age});
  final String id;
  final String name;
  final int? age;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'age': age};
  factory ChildProfile.fromJson(Map<String, dynamic> j) => ChildProfile(id: j['id'] as String, name: j['name'] as String, age: (j['age'] as num?)?.toInt());
}

enum JobState { uploading, queued, running, done, error }

/// A server analysis in progress.
class Job {
  Job({required this.localId, required this.title, required this.profileId, this.url, this.isImage = false});
  final String localId;
  String title;
  final String profileId;
  final String? url;
  final bool isImage;
  String? serverId;
  JobState state = JobState.queued;
  String stage = 'Starting';
  double progress = 0;
  String? error;
  String? entryId;
  bool get active => state == JobState.uploading || state == JobState.queued || state == JobState.running;
}

class AlertItem {
  AlertItem({required this.id, required this.profile, required this.createdAt, required this.level, required this.kind, required this.title, required this.body, this.link, this.jobId, required this.seen, this.platform = 'ig'});
  final String id, profile, level, kind, title, body, platform;
  final double createdAt;
  final String? link, jobId;
  final bool seen;

  factory AlertItem.fromJson(Map<String, dynamic> j) => AlertItem(
        id: j['id'] as String,
        profile: j['profile'] as String? ?? 'me',
        createdAt: (j['createdAt'] as num?)?.toDouble() ?? 0,
        level: j['level'] as String? ?? 'info',
        kind: j['kind'] as String? ?? 'item',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        link: j['link'] as String?,
        jobId: j['jobId'] as String?,
        seen: j['seen'] == true,
        platform: j['platform'] as String? ?? 'ig',
      );
}

/// One item found by a Feed check.
class ScanItem {
  ScanItem({required this.url, required this.kind, this.source, required this.ok, this.jobId, this.mood, this.level, this.safety});
  final String url, kind;
  final String? source, jobId, mood, level, safety;
  final bool ok;

  factory ScanItem.fromJson(Map<String, dynamic> j) => ScanItem(
        url: j['url'] as String? ?? '',
        kind: j['kind'] as String? ?? 'reel',
        source: j['source'] as String?,
        ok: j['ok'] == true,
        jobId: j['jobId'] as String?,
        mood: j['mood'] as String?,
        level: j['level'] as String?,
        safety: j['safety'] as String?,
      );
}

class ScanReport {
  ScanReport({required this.id, required this.profile, required this.kind, required this.createdAt, this.finishedAt, required this.status, required this.stage, required this.progress, this.error, required this.items, required this.summary, this.platform = 'ig'});
  final String id, profile, kind, status, stage, platform;
  final double createdAt, progress;
  final double? finishedAt;
  final String? error;
  final List<ScanItem> items;
  final Map<String, dynamic> summary;

  bool get running => status == 'running';
  List<String> get lines => ((summary['lines'] as List?) ?? const []).map((e) => e.toString()).toList();
  List<String> get review => ((summary['review'] as List?) ?? const []).map((e) => e.toString()).toList();
  List<MapEntry<String, num>> get moodMix => ((summary['moods'] as List?) ?? const []).whereType<List>().map((e) => MapEntry(e[0].toString(), e[1] as num)).toList();
  int get analyzed => (summary['analyzed'] as num?)?.toInt() ?? 0;
  String? get username => summary['username'] as String?;

  /// The scans list endpoint returns `items` as a count; the detail endpoint returns a list.
  factory ScanReport.fromJson(Map<String, dynamic> j) {
    final rawItems = j['items'];
    return ScanReport(
      id: j['id'] as String,
      profile: j['profile'] as String? ?? 'me',
      platform: j['platform'] as String? ?? 'ig',
      kind: j['kind'] as String? ?? 'explore',
      createdAt: (j['createdAt'] as num?)?.toDouble() ?? 0,
      finishedAt: (j['finishedAt'] as num?)?.toDouble(),
      status: j['status'] as String? ?? 'running',
      stage: j['stage'] as String? ?? '',
      progress: (j['progress'] as num?)?.toDouble() ?? 0,
      error: j['error'] as String?,
      items: rawItems is List ? rawItems.whereType<Map>().map((e) => ScanItem.fromJson(e.cast<String, dynamic>())).toList() : const [],
      summary: (j['summary'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

class MonitorSettings {
  MonitorSettings({required this.profileId, required this.enabled, required this.intervalMin, required this.consent, required this.connected, this.lastScan, this.status, this.platform = 'ig'});
  final String profileId, platform;
  final bool enabled, consent, connected;
  final int intervalMin;
  final double? lastScan;
  final String? status;

  factory MonitorSettings.fromJson(Map<String, dynamic> j) => MonitorSettings(
        profileId: j['profile_id'] as String,
        platform: j['platform'] as String? ?? 'ig',
        enabled: (j['enabled'] as num?) == 1 || j['enabled'] == true,
        intervalMin: (j['interval_min'] as num?)?.toInt() ?? 120,
        consent: j['consent'] == true,
        connected: j['connected'] == true,
        lastScan: (j['last_scan'] as num?)?.toDouble(),
        status: j['status'] as String?,
      );
}
