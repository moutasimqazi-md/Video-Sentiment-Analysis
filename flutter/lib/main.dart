import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';

import 'core/alerts.dart';
import 'core/api.dart';
import 'core/auth.dart';
import 'core/imports/import_store.dart';
import 'core/share_intake.dart';
import 'core/settings.dart';
import 'core/stores.dart';
import 'ui/screens/launch.dart';
import 'ui/screens/signed_in_gate.dart';
import 'ui/shell_nav.dart';
import 'ui/theme.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding); // keep the system splash until the app has its first full-size frame
  runApp(NeuroLensApp(settings: await AppSettings.load()));
  WidgetsBinding.instance.addPostFrameCallback((_) => Future<void>.delayed(const Duration(milliseconds: 350), FlutterNativeSplash.remove));
}

class NeuroLensApp extends StatelessWidget {
  const NeuroLensApp({super.key, required this.settings, this.api, this.launch = true});
  final AppSettings settings;
  final ApiClient? api; // injected by tests
  final bool launch; // false in tests that start straight in the app

  @override
  Widget build(BuildContext context) {
    final client = api ?? ApiClient(settings);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        Provider<ApiClient>.value(value: client),
        ChangeNotifierProvider(create: (_) => HistoryStore(settings.prefs)),
        ChangeNotifierProvider(create: (_) => ProfilesStore(settings.prefs)),
        ChangeNotifierProvider(create: (c) => JobQueue(client, c.read<HistoryStore>())),
        ChangeNotifierProvider(create: (_) => ShareController()..start()),
        ChangeNotifierProvider(create: (_) => ImportStore(settings.prefs)),
        ChangeNotifierProvider(create: (c) => AuthController(client, settings, c.read<HistoryStore>(), c.read<ProfilesStore>(), c.read<JobQueue>(), imports: c.read<ImportStore>())),
        ChangeNotifierProvider(create: (_) => AlertsController(client, settings)),
        ChangeNotifierProvider(create: (_) => ShellNav()),
      ],
      child: Consumer<AppSettings>(
        builder: (context, s, _) => MaterialApp(
          title: 'NeuroLens',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: s.themeMode,
          home: launch ? const Launcher() : const SignedInGate(),
        ),
      ),
    );
  }
}
