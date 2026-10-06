/* Wellbeing signal: how emotionally heavy a video's tone is.
   This is derived from the analyzer's emotion scores only. It does NOT detect explicit, violent or self-harm
   content, and it does not read captions, comments or messages — treat it as a prompt to look and talk, not a verdict. */
window.NL = window.NL || {};

NL.wellbeing = (() => {
  const WEIGHTS = { depressed: 1.5, heartbroken: 1.2, sad: 1.2, lost: 1.0, angry: 0.8, tired: 0.5 };
  const WATCH = 30, HIGH = 55;

  const LEVELS = {
    calm:  { key: "calm",  label: "Calm",         icon: "check", cls: "green" },
    watch: { key: "watch", label: "Worth a look", icon: "eye", cls: "warn" },
    high:  { key: "high",  label: "High concern", icon: "alert", cls: "err" },
  };

  /** result = backend analysis result. Returns {level, score, drivers[], summary}. */
  function assess(result) {
    const avg = result.averages || {};
    let score = 0;
    const drivers = [];
    for (const [m, w] of Object.entries(WEIGHTS)) {
      const v = avg[m] || 0;
      score += v * w;
      if (v >= 8) drivers.push([m, v]);
    }
    drivers.sort((a, b) => b[1] - a[1]);
    const dominant = result.dominant_mood;
    let key = score >= HIGH ? "high" : score >= WATCH ? "watch" : "calm";
    if (key === "calm" && WEIGHTS[dominant] && (avg[dominant] || 0) >= 35) key = "watch";

    const names = drivers.slice(0, 3).map(([m]) => m).join(", ");
    const summary =
      key === "high" ? `This video carries a heavy emotional tone (${names || "negative"}). Consider watching it together and checking in.`
      : key === "watch" ? `Some heavier emotions show up (${names || "mixed"}). Worth a look if it's part of a pattern.`
      : "The overall tone is light or neutral — nothing stands out.";
    return { level: LEVELS[key], score: Math.round(score), drivers, summary };
  }

  /** Summarize several history entries (a week for one profile). */
  function aggregate(entries) {
    const n = entries.length;
    const mood = {};
    const levels = { calm: 0, watch: 0, high: 0 };
    const flagged = [];
    entries.forEach((h) => {
      const a = assess(h.result);
      levels[a.level.key]++;
      if (a.level.key !== "calm") flagged.push({ entry: h, assessment: a });
      for (const [m, v] of Object.entries(h.result.averages)) mood[m] = (mood[m] || 0) + v / n;
    });
    const mix = Object.entries(mood).sort((a, b) => b[1] - a[1]);
    const heavyShare = n ? Math.round(((levels.watch + levels.high) / n) * 100) : 0;
    const overall = levels.high >= 1 || heavyShare >= 50 ? "high" : levels.watch >= 1 ? "watch" : "calm";
    return { count: n, levels, flagged, mix, heavyShare, overall: LEVELS[overall] };
  }

  const TIPS = [
    "Ask open questions: \"What did you like about that one?\" works better than \"Why are you watching that?\"",
    "Watch a few Reels together and talk about how they make you both feel.",
    "Agree on screen-free times (for example, the hour before bed). Heavy content hits hardest late at night.",
    "Use Instagram's Sensitive Content Control and Time Limit settings together.",
    "If you're worried about your child's safety, talk to them directly and contact a school counselor, doctor or local crisis service.",
  ];

  const iconSvg = (level, size = 18) => NL.icon(level.icon, size);

  return { assess, aggregate, LEVELS, TIPS, iconSvg };
})();
