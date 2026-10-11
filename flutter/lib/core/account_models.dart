/// A subscription plan, as the server defines it (GET /api/plans).
class Plan {
  Plan({required this.id, required this.name, required this.monthly, required this.yearly, required this.quota, required this.history, required this.children, required this.weekly, required this.seats, required this.blurb, required this.features, required this.off, this.featured = false});
  final String id, name, blurb;
  final int monthly, yearly, quota, history, children, seats;
  final bool weekly, featured;
  final List<String> features, off;

  bool get free => monthly == 0;

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
        id: j['id'] as String,
        name: j['name'] as String,
        monthly: (j['monthly'] as num?)?.toInt() ?? 0,
        yearly: (j['yearly'] as num?)?.toInt() ?? 0,
        quota: (j['quota'] as num?)?.toInt() ?? 0,
        history: (j['history'] as num?)?.toInt() ?? 0,
        children: (j['children'] as num?)?.toInt() ?? 0,
        weekly: j['weekly'] == true,
        seats: (j['seats'] as num?)?.toInt() ?? 1,
        blurb: j['blurb'] as String? ?? '',
        features: ((j['features'] as List?) ?? const []).map((e) => e.toString()).toList(),
        off: ((j['off'] as List?) ?? const []).map((e) => e.toString()).toList(),
        featured: j['featured'] == true,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'monthly': monthly, 'yearly': yearly, 'quota': quota, 'history': history, 'children': children, 'weekly': weekly, 'seats': seats, 'blurb': blurb, 'features': features, 'off': off, 'featured': featured};
}

/// The signed-in account: who they are, which plan, and this month's usage.
class Me {
  Me({required this.userId, this.name, this.email, required this.plan, required this.cycle, required this.used, required this.quota, required this.remaining, required this.resetsOn, required this.childrenUsed, required this.childrenAllowed});
  final String userId;
  final String? name, email;
  final Plan plan;
  final String cycle, resetsOn;
  final int used, quota, remaining, childrenUsed, childrenAllowed;

  double get usedFraction => quota == 0 ? 0 : (used / quota).clamp(0, 1).toDouble();
  bool get outOfAnalyses => remaining <= 0;
  String get displayName => (name != null && name!.trim().isNotEmpty) ? name!.trim() : (email ?? 'You').split('@').first;

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        userId: j['userId'] as String,
        name: j['name'] as String?,
        email: j['email'] as String?,
        plan: Plan.fromJson((j['plan'] as Map).cast<String, dynamic>()),
        cycle: j['cycle'] as String? ?? 'monthly',
        used: (j['used'] as num?)?.toInt() ?? 0,
        quota: (j['quota'] as num?)?.toInt() ?? 0,
        remaining: (j['remaining'] as num?)?.toInt() ?? 0,
        resetsOn: j['resetsOn'] as String? ?? '',
        childrenUsed: (j['childrenUsed'] as num?)?.toInt() ?? 0,
        childrenAllowed: (j['childrenAllowed'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'userId': userId, 'name': name, 'email': email, 'plan': plan.toJson(), 'cycle': cycle, 'used': used, 'quota': quota, 'remaining': remaining, 'resetsOn': resetsOn, 'childrenUsed': childrenUsed, 'childrenAllowed': childrenAllowed};
}
