import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurolens/core/share_intake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the link is pulled out of what Instagram and YouTube share', () {
    expect(extractLink('https://www.instagram.com/reel/AbC123/?igsh=xyz'), 'https://www.instagram.com/reel/AbC123/?igsh=xyz');
    expect(extractLink('Watch this on YouTube: https://youtube.com/shorts/abcdefghijk?si=1 (so good)'), 'https://youtube.com/shorts/abcdefghijk?si=1');
    expect(extractLink('no link here'), isNull);
    expect(extractLink(null), isNull);
  });

  test('a shared link waits until it is taken, once', () async {
    const ch = MethodChannel('neurolens/share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async => call.method == 'initial' ? 'Look https://youtu.be/abcdefghijk' : null);
    final c = ShareController(channel: ch);
    await c.start();
    expect(c.pendingLink, 'https://youtu.be/abcdefghijk');
    expect(c.take(), 'https://youtu.be/abcdefghijk');
    expect(c.take(), isNull);
  });

  test('a share without a link explains itself', () async {
    const ch = MethodChannel('neurolens/share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async => 'just words');
    final c = ShareController(channel: ch);
    await c.start();
    expect(c.pendingLink, isNull);
    expect(c.takeProblem(), contains("didn't contain a link"));
  });
}
