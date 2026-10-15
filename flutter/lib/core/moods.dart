import 'package:flutter/material.dart';

/// The 16 moods the analysis engine scores. Keys match backend `CATEGORY_PROMPTS`.
class MoodInfo {
  const MoodInfo(this.key, this.emoji, this.label, this.color);
  final String key;
  final String emoji;
  final String label;
  final Color color;
}

const Map<String, MoodInfo> moods = {
  'confident': MoodInfo('confident', '😎', 'Attitude videos', Color(0xFF7C5CE6)),
  'motivated': MoodInfo('motivated', '🔥', 'Motivation videos', Color(0xFFF08A24)),
  'focused': MoodInfo('focused', '🎯', 'Gym / Goals videos', Color(0xFF2F8F6B)),
  'inspired': MoodInfo('inspired', '✨', 'Transformation videos', Color(0xFFE0A800)),
  'excited': MoodInfo('excited', '🎉', 'Celebration videos', Color(0xFFE5518D)),
  'happy': MoodInfo('happy', '😄', 'Fun / Trending videos', Color(0xFFF4B400)),
  'funny': MoodInfo('funny', '😂', 'Comedy / Relatable videos', Color(0xFFEF7B3D)),
  'romantic': MoodInfo('romantic', '💞', 'Love / Couple videos', Color(0xFFD6457A)),
  'hungry': MoodInfo('hungry', '😋', 'Food / Cravings videos', Color(0xFFD9822B)),
  'peaceful': MoodInfo('peaceful', '🌿', 'Aesthetic / Nature videos', Color(0xFF3FA37A)),
  'heartbroken': MoodInfo('heartbroken', '💔', 'Breakup / Emotional videos', Color(0xFFB4408F)),
  'sad': MoodInfo('sad', '😢', 'Sad-song / Feeling-low videos', Color(0xFF4A7CF0)),
  'angry': MoodInfo('angry', '😠', 'Savage / Rage videos', Color(0xFFD94A3D)),
  'lost': MoodInfo('lost', '🧭', 'Deep-thought / Alone videos', Color(0xFF6C7A99)),
  'tired': MoodInfo('tired', '😴', 'Burnout / Tired videos', Color(0xFF8A8F9E)),
  'depressed': MoodInfo('depressed', '🌑', 'Dark / Numb videos', Color(0xFF3C4560)),
};

String moodEmoji(String? m) => moods[m]?.emoji ?? '🎬';
String moodLabel(String? m, [Map<String, dynamic>? fromServer]) => (fromServer?[m] as String?) ?? moods[m]?.label ?? '';
Color moodColor(String? m) => moods[m]?.color ?? const Color(0xFF8A8F9E);
String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
