import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/alerts.dart';
import '../screens/alerts_screen.dart';
import '../screens/more_screen.dart';

/// The header every main screen shares: the logo and screen name on the left, alerts and the account on the right,
/// so notifications and settings are one tap away from anywhere.
class NlTabBar extends StatelessWidget implements PreferredSizeWidget {
  const NlTabBar({super.key, required this.title});
  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final unread = context.select<AlertsController, int>((a) => a.unread);
    return AppBar(
      title: Row(children: [
        ExcludeSemantics(child: Image.asset('assets/logo.png', width: 28, height: 28)),
        const SizedBox(width: 10),
        Flexible(child: Semantics(header: true, child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis))),
      ]),
      actions: [
        IconButton(
          tooltip: unread > 0 ? 'Alerts, $unread unread' : 'Alerts',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AlertsScreen())),
          icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_outlined)),
        ),
        IconButton(tooltip: 'Account and settings', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoreScreen())), icon: const Icon(Icons.account_circle_outlined)),
        const SizedBox(width: 4),
      ],
    );
  }
}
