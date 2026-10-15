import 'package:flutter/material.dart';

/// One kind of check a site offers. The server (backend/neurolens/platforms.py) is the authority on which exist.
class FeedMode {
  const FeedMode(this.id, this.label, this.desc, this.icon);
  final String id, label, desc;
  final IconData icon;
}

/// A site the Feed check can read: Instagram, YouTube, TikTok or Facebook.
class Site {
  const Site({
    required this.code,
    required this.name,
    required this.icon,
    required this.home,
    required this.loginPath,
    required this.cookieDomain,
    required this.session,
    required this.pending,
    required this.modes,
    this.phoneSignIn = true,
    this.note,
  });

  final String code, name, home, loginPath, cookieDomain;
  final IconData icon;

  /// Signed in when every group has at least one of its cookies with a value.
  final List<List<String>> session;

  /// Parts of an address that mean the sign-in isn't finished (still on the login page, or a security step).
  final List<String> pending;
  final List<FeedMode> modes;

  /// False when the site refuses to sign in inside an app's web view (Google does), so the server's streamed private browser is used.
  final bool phoneSignIn;

  /// Something the person should know before signing in.
  final String? note;

  String get loginUrl => home + loginPath;
  bool signedIn(Iterable<String> cookieNamesWithValue) => session.every((group) => group.any(cookieNamesWithValue.contains));
  bool isPending(String url) => pending.any(url.contains);
  FeedMode mode(String id) => modes.firstWhere((m) => m.id == id, orElse: () => modes.first);
}

const sites = <Site>[
  Site(
    code: 'ig',
    name: 'Instagram',
    icon: Icons.camera_alt_outlined,
    home: 'https://www.instagram.com/',
    loginPath: 'accounts/login/',
    cookieDomain: '.instagram.com',
    session: [['sessionid']],
    pending: ['/challenge', '/accounts/login', '/accounts/suspended'],
    modes: [
      FeedMode('explore', 'Explore', 'What Instagram suggests to this account', Icons.explore_outlined),
      FeedMode('foryou', 'For You reels', 'The reels feed, scrolled a few times', Icons.movie_outlined),
      FeedMode('terms', 'Search topics', 'Top posts for topics you enter', Icons.search),
      FeedMode('profile', 'Account review', "How the account's own posts come across", Icons.insights_outlined),
    ],
  ),
  Site(
    code: 'yt',
    name: 'YouTube',
    icon: Icons.play_circle_outline,
    home: 'https://www.youtube.com/',
    loginPath: '',
    cookieDomain: '.youtube.com',
    session: [['SAPISID', '__Secure-3PAPISID', '__Secure-3PSID']],
    pending: ['/signin', 'accounts.google.com', '/ServiceLogin'],
    phoneSignIn: false,
    note: 'Google sometimes refuses to let a browser it thinks is automated sign in. If that happens, YouTube checks cannot run for this account.',
    modes: [
      FeedMode('foryou', 'Home recommendations', "The videos YouTube puts on this account's home page", Icons.explore_outlined),
      FeedMode('history', 'Watch history', 'What this account actually watched recently', Icons.history),
      FeedMode('terms', 'Search topics', 'Top videos for topics you enter', Icons.search),
    ],
  ),
  Site(
    code: 'tt',
    name: 'TikTok',
    icon: Icons.music_note_outlined,
    home: 'https://www.tiktok.com/',
    loginPath: 'login',
    cookieDomain: '.tiktok.com',
    session: [['sessionid', 'sid_tt']],
    pending: ['/login', '/captcha', '/verify'],
    note: 'TikTok may ask you to solve a puzzle while signing in.',
    modes: [
      FeedMode('foryou', 'For You', 'The For You feed', Icons.movie_outlined),
      FeedMode('explore', 'Explore', 'What TikTok suggests to this account', Icons.explore_outlined),
      FeedMode('terms', 'Search topics', 'Top videos for topics you enter', Icons.search),
    ],
  ),
  Site(
    code: 'fb',
    name: 'Facebook',
    icon: Icons.facebook,
    home: 'https://www.facebook.com/',
    loginPath: 'login/',
    cookieDomain: '.facebook.com',
    session: [['c_user'], ['xs']],
    pending: ['/login', '/checkpoint', 'two_step_verification', '/recover'],
    note: 'Facebook may ask for a security check or a code the first time.',
    modes: [
      FeedMode('foryou', 'Watch feed', 'The videos Facebook Watch recommends', Icons.movie_outlined),
      FeedMode('explore', 'Reels', 'The Reels Facebook recommends', Icons.explore_outlined),
      FeedMode('terms', 'Search topics', 'Top videos for topics you enter', Icons.search),
    ],
  ),
];

Site siteOf(String? code) => sites.firstWhere((s) => s.code == code, orElse: () => sites.first);
