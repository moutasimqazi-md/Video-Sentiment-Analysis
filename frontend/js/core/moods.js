/* Mood catalogue — keys match backend analyzer.CATEGORY_PROMPTS */
window.NL = window.NL || {};

NL.MOODS = {
  confident:   { emoji: "😎", label: "Attitude videos" },
  motivated:   { emoji: "🔥", label: "Motivation videos" },
  focused:     { emoji: "🎯", label: "Gym / Goals videos" },
  inspired:    { emoji: "✨", label: "Transformation videos" },
  excited:     { emoji: "🎉", label: "Celebration videos" },
  happy:       { emoji: "😄", label: "Fun / Trending videos" },
  funny:       { emoji: "😂", label: "Comedy / Relatable videos" },
  romantic:    { emoji: "💞", label: "Love / Couple videos" },
  hungry:      { emoji: "😋", label: "Food / Cravings videos" },
  peaceful:    { emoji: "🌿", label: "Aesthetic / Nature videos" },
  heartbroken: { emoji: "💔", label: "Breakup / Emotional videos" },
  sad:         { emoji: "😢", label: "Sad-song / Feeling-low videos" },
  angry:       { emoji: "😠", label: "Savage / Rage videos" },
  lost:        { emoji: "🧭", label: "Deep-thought / Alone videos" },
  tired:       { emoji: "😴", label: "Burnout / Tired videos" },
  depressed:   { emoji: "🌑", label: "Dark / Numb videos" },
};

NL.moodEmoji = (m) => (NL.MOODS[m] && NL.MOODS[m].emoji) || "🎬";
NL.moodLabel = (m, labels) => (labels && labels[m]) || (NL.MOODS[m] && NL.MOODS[m].label) || "";
NL.cap = (s) => (s ? s[0].toUpperCase() + s.slice(1) : "");
NL.esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
