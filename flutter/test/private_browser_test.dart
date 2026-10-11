import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurolens/ui/screens/private_browser.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'helpers.dart';

class FakeSocket with StreamChannelMixin<dynamic> implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  final sent = <dynamic>[];
  bool closed = false;
  late final _FakeSink _sink = _FakeSink(this);

  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  Future<void> get ready => Future.value();
  @override
  String? get protocol => null;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;

  void push(Map<String, dynamic> j) => incoming.add(jsonEncode(j));
  List<Map<String, dynamic>> get sentJson => sent.map((e) => jsonDecode(e as String) as Map<String, dynamic>).toList();
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this.s);
  final FakeSocket s;
  @override
  void add(dynamic data) => s.sent.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.forEach(add);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async => s.closed = true;
  @override
  Future<void> get done => Future.value();
}

void main() {
  late FakeSocket socket;
  late Uri connectedTo;

  Future<PrivateBrowserController> make(Future<dynamic> Function(String path)? onPath) async {
    final (api, _, _) = await fakeApi((r) async {
      if (onPath != null) {
        final custom = await onPath(r.url.path);
        if (custom != null) return custom;
      }
      if (r.url.path.endsWith('/view-token')) return json({'token': 'tok123'});
      return json({'state': 'starting'});
    }, token: 'owner');
    socket = FakeSocket();
    return PrivateBrowserController(api: api, profileId: 'me', connector: (u) {
      connectedTo = u;
      return socket;
    });
  }

  test('starts the login, gets a single-use key and opens the socket', () async {
    final c = await make(null);
    await c.start();
    expect(connectedTo.toString(), 'ws://192.168.1.5:8000/api/sessions/me/view?t=tok123');
    expect(c.state, 'starting');
    c.dispose();
  });

  test('shows frames, the address, hints and the connected state', () async {
    final c = await make(null);
    await c.start();
    socket.push({'type': 'state', 'state': 'live', 'error': null});
    socket.incoming.add(Uint8List.fromList([255, 216, 1, 2, 3]));
    socket.push({'type': 'url', 'host': 'www.instagram.com'});
    socket.push({'type': 'hint', 'text': 'Instagram is asking for a security check.'});
    await Future<void>.delayed(Duration.zero);
    expect(c.state, 'live');
    expect(c.frame, isNotNull);
    expect(c.host, 'www.instagram.com');
    expect(c.hint, contains('security check'));
    socket.push({'type': 'hint', 'text': ''});
    socket.push({'type': 'state', 'state': 'connected'});
    await Future<void>.delayed(Duration.zero);
    expect(c.hint, isNull);
    expect(c.state, 'connected');
    expect(c.done, isTrue);
    c.dispose();
  });

  test('taps, scrolling, typing and keys are sent in the protocol the server expects', () async {
    final c = await make(null);
    await c.start();
    c.tapDown(220, 142);
    c.tapUp(220, 142);
    c.scroll(200, 300, 40);
    c.text('tester');
    c.key('Backspace');
    c.key('Enter');
    final sent = socket.sentJson;
    expect(sent[0], {'t': 'mouse', 'type': 'down', 'x': 220.0, 'y': 142.0, 'button': 'left', 'clicks': 1});
    expect(sent[1]['type'], 'up');
    expect(sent[2], {'t': 'mouse', 'type': 'wheel', 'x': 200.0, 'y': 300.0, 'dx': 0, 'dy': 40.0});
    expect(sent[3], {'t': 'text', 'text': 'tester'});
    expect(sent[4], {'t': 'key', 'key': 'Backspace'});
    expect(sent[5], {'t': 'key', 'key': 'Enter'});
    c.dispose();
  });

  test('a closed browser and a server error are reported', () async {
    final c = await make(null);
    await c.start();
    socket.push({'type': 'state', 'state': 'closed'});
    await Future<void>.delayed(Duration.zero);
    expect(c.state, 'closed');

    final e = await make((p) async => p.endsWith('/login') ? json({'detail': 'Confirm that your child knows before connecting their account.'}, 400) : null);
    await e.start();
    expect(e.state, 'error');
    expect(e.error, contains('child knows'));
    c.dispose();
    e.dispose();
  });

  test('cancel tells the server and closes the socket', () async {
    final c = await make(null);
    await c.start();
    await c.cancel();
    expect(socket.closed, isTrue);
    c.dispose();
  });
}
