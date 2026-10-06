/* Built-in sample analysis so the results page can be demoed without running the backend. */
window.NL = window.NL || {};

NL.SAMPLE = {
  id: "sample",
  createdAt: Date.now(),
  title: "Sunset time-lapse (sample)",
  thumb: "assets/img/sample-thumb.svg",
  source: { kind: "sample" },
  result: {
    duration_seconds: 27.4,
    frames_analyzed: 12,
    dominant_mood: "peaceful",
    averages: {
      peaceful: 61.4, inspired: 9.0, happy: 6.1, romantic: 5.2, motivated: 3.0, lost: 3.4, sad: 2.2, confident: 1.5,
      excited: 1.8, funny: 0.9, hungry: 0.8, focused: 1.1, heartbroken: 1.0, tired: 1.2, angry: 0.2, depressed: 0.6,
    },
    visual_averages: {
      peaceful: 72.5, inspired: 8.4, happy: 4.8, romantic: 4.6, motivated: 1.6, lost: 2.2, sad: 1.1, confident: 0.9,
      excited: 1.0, funny: 0.5, hungry: 0.4, focused: 0.6, heartbroken: 0.5, tired: 0.6, angry: 0.1, depressed: 0.2,
    },
    audio: {
      available: true, dominant: "peaceful", loudness_db: -21.8, windows_analyzed: 3,
      averages: {
        peaceful: 45.9, inspired: 9.9, happy: 8.1, romantic: 6.2, motivated: 5.1, lost: 5.3, sad: 3.8, confident: 2.5,
        excited: 2.9, funny: 1.5, hungry: 1.4, focused: 1.8, heartbroken: 1.7, tired: 2.0, angry: 0.4, depressed: 1.2,
      },
    },
    color_metrics: { avg_brightness: 58.2, avg_saturation: 47.5, cuts_per_minute: 9.4 },
    verdict: "This video mostly feels peaceful (Aesthetic / Nature Reels). Soft, warm light and slow cuts create a calm mood, and the gentle soundtrack reinforces it.",
    timeline: [0, 2.3, 4.6, 6.9, 9.1, 11.4, 13.7, 16, 18.3, 20.6, 22.8, 25.1].map((t, i) => ({
      t,
      peaceful: [58, 66, 71, 74, 72, 77, 70, 75, 79, 73, 68, 74][i] / 100,
      inspired: [12, 10, 9, 8, 9, 7, 10, 8, 6, 8, 9, 7][i] / 100,
      happy: [7, 6, 5, 4, 5, 4, 6, 4, 4, 5, 5, 4][i] / 100,
    })),
  },
};
