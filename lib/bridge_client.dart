import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'playback.dart';

class BridgeClient {
  BridgeClient({
    required this.send,
    required this.onState,
    required this.onHandoff,
    this.timeout = const Duration(seconds: 8),
  }) {
    _ready.future.ignore();
  }
  final Future<void> Function(String) send;
  final void Function(PlaybackSnapshot) onState;
  final void Function() onHandoff;
  final Duration timeout;
  final String session = base64Url.encode(
    List.generate(18, (_) => Random.secure().nextInt(256)),
  );
  final _ready = Completer<void>();
  final _pending = <String, Completer<PlaybackSnapshot>>{};
  int _sequence = 0;
  bool _closed = false;
  // WebView cold start can exceed the deadline for an individual command.
  Future<void> get ready => _ready.future.timeout(const Duration(seconds: 30));

  void receive(String raw) {
    if (_closed || raw.length > 16384) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['v'] != 1 || data['session'] != session) return;
      switch (data['type']) {
        case 'ready':
          if (!_ready.isCompleted) _ready.complete();
        case 'reply':
          final pending = _pending[data['id']];
          if (pending == null || pending.isCompleted) return;
          if (data['error'] is String) {
            pending.completeError(StateError(data['error'] as String));
          } else {
            pending.complete(PlaybackSnapshot.fromJson(data['data']));
          }
        case 'state':
          onState(PlaybackSnapshot.fromJson(data['data']));
        case 'handoff':
          onHandoff();
      }
    } on FormatException {
      // Invalid or truncated page messages are ignored; requests still time out.
    }
  }

  Future<PlaybackSnapshot> request(String method, [Object? data]) async {
    if (_closed) throw StateError('BRIDGE_CLOSED');
    final id = (++_sequence).toString();
    final pending = Completer<PlaybackSnapshot>();
    pending.future.ignore();
    _pending[id] = pending;
    try {
      await send(
        jsonEncode({
          'v': 1,
          'session': session,
          'id': id,
          'method': method,
          'data': data,
        }),
      ).timeout(timeout);
      return await pending.future.timeout(timeout);
    } finally {
      _pending.remove(id);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (!_ready.isCompleted) _ready.completeError(StateError('BRIDGE_CLOSED'));
    for (final request in _pending.values) {
      if (!request.isCompleted) {
        request.completeError(StateError('BRIDGE_CLOSED'));
      }
    }
    _pending.clear();
  }
}
