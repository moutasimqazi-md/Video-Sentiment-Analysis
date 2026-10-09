"""Server-side copy of the site's wellbeing signal (frontend/js/core/wellbeing.js), so alerts can be raised without a browser open.
Keep the weights and thresholds in sync with that file."""

WEIGHTS = {"depressed": 1.5, "heartbroken": 1.2, "sad": 1.2, "lost": 1.0, "angry": 0.8, "tired": 0.5}
WATCH, HIGH = 30, 55


def assess(result):
    """Returns {"level": "calm"|"watch"|"high", "score": int, "drivers": [(mood, pct)...]}."""
    avg = result.get("averages") or {}
    score = 0.0
    drivers = []
    for mood, w in WEIGHTS.items():
        v = avg.get(mood, 0)
        score += v * w
        if v >= 8:
            drivers.append((mood, v))
    drivers.sort(key=lambda d: -d[1])
    level = "high" if score >= HIGH else "watch" if score >= WATCH else "calm"
    dom = result.get("dominant_mood")
    if level == "calm" and dom in WEIGHTS and avg.get(dom, 0) >= 35:
        level = "watch"
    return {"level": level, "score": round(score), "drivers": drivers}
