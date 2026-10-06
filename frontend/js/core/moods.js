/* Mood catalogue — keys match backend analyzer.CATEGORY_PROMPTS */
window.NL = window.NL || {};

NL.MOODS = {
  confident:   { emoji: "😎", label: "Attitude Reels" },
  motivated:   { emoji: "🔥", label: "Motivation Reels" },
  focused:     { emoji: "🎯", label: "Gym / Goals Reels" },
  inspired:    { emoji: "✨", label: "Transformation Reels" },
  excited:     { emoji: "🎉", label: "Celebration Reels" },
  happy:       { emoji: "😄", label: "Fun / Trending Reels" },
  funny:       { emoji: "😂", label: "Comedy / Relatable Reels" },
  romantic:    { emoji: "💞", label: "Love / Couple Reels" },
  hungry:      { emoji: "😋", label: "Food / Cravings Reels" },
  peaceful:    { emoji: "🌿", label: "Aesthetic / Nature Reels" },
  heartbroken: { emoji: "💔", label: "Breakup / Emotional Reels" },
  sad:         { emoji: "😢", label: "Sad-song / Feeling-low Reels" },
  angry:       { emoji: "😠", label: "Savage / Rage Reels" },
  lost:        { emoji: "🧭", label: "Deep-thought / Alone Reels" },
  tired:       { emoji: "😴", label: "Burnout / Tired Reels" },
  depressed:   { emoji: "🌑", label: "Dark / Numb Reels" },
};

NL.moodEmoji = (m) => (NL.MOODS[m] && NL.MOODS[m].emoji) || "🎬";
NL.moodLabel = (m, labels) => (labels && labels[m]) || (NL.MOODS[m] && NL.MOODS[m].label) || "";
NL.cap = (s) => (s ? s[0].toUpperCase() + s.slice(1) : "");
NL.esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
