import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'playback.dart';

bool allowedPage(Uri uri, Uri origin) =>
    uri.scheme == origin.scheme &&
    uri.host == origin.host &&
    uri.port == origin.port &&
    uri.userInfo.isEmpty &&
    ['/', '/home'].contains(uri.path);

bool allowedMedia(Uri uri, Uri origin) =>
    uri.scheme == origin.scheme &&
    uri.host == origin.host &&
    uri.port == origin.port &&
    uri.userInfo.isEmpty &&
    !uri.hasQuery &&
    !uri.hasFragment &&
    ['/lab-media/demo-360.mp4', '/lab-media/demo-720.mp4'].contains(uri.path);

// WebKit can finish a navigation before deferred application modules register the bridge.
String remoteConnectScript(String session) =>
    """
(() => {
  const connect = () => window.VideoLabRemote?.connect(${jsonEncode(session)});
  if (typeof window.VideoLabRemote?.connect === 'function') connect();
  else window.addEventListener('video-lab-ready', connect, {once: true});
})();
""";

class RemoteMedia {
  RemoteMedia({
    required this.id,
    required this.version,
    required this.url,
    required this.title,
    required this.quality,
    required this.qualities,
    required this.ready,
    required this.state,
  });
  final String id, version, url, title, quality;
  final List<String> qualities;
  final bool ready;
  final PlaybackSnapshot state;
  bool get canHandoff => ready && url.isNotEmpty;
  factory RemoteMedia.fromJson(Object? raw, Uri origin) {
    if (raw is! Map) throw const FormatException('INVALID_MEDIA');
    String text(String key, int limit) {
      final value = raw[key];
      if (value is! String || value.length > limit) {
        throw const FormatException('INVALID_TEXT');
      }
      return value;
    }

    final id = text('videoId', 128), version = text('sourceVersion', 160);
    final url = text('url', 1024),
        title = text('title', 160),
        quality = text('quality', 32);
    final qualities = raw['qualities'];
    if (id.isEmpty ||
        version.isEmpty ||
        raw['ready'] is! bool ||
        qualities is! List ||
        qualities.length > 8 ||
        qualities.any((q) => q is! String || q.length > 32) ||
        (url.isNotEmpty && !allowedMedia(Uri.parse(url), origin))) {
      throw const FormatException('INVALID_MEDIA');
    }
    final state = PlaybackSnapshot.fromJson(raw);
    if (state.duration > 86400 || state.position > 86400) {
      throw const FormatException('INVALID_DURATION');
    }
    return RemoteMedia(
      id: id,
      version: version,
      url: url,
      title: title,
      quality: quality,
      qualities: qualities.cast<String>(),
      ready: raw['ready'],
      state: state,
    );
  }
  Map<String, Object> restore(PlaybackSnapshot value) => {
    ...value.toJson(),
    'videoId': id,
    'sourceVersion': version,
  };
  bool sameVideo(RemoteMedia other) =>
      id == other.id && version == other.version;
}

class RemoteBridge {
  RemoteBridge({
    required this.send,
    required this.onEvent,
    this.timeout = const Duration(seconds: 8),
  }) {
    _ready.future.ignore();
  }
  final Future<void> Function(String) send;
  final void Function(String, Object?) onEvent;
  final Duration timeout;
  final String session = base64Url.encode(
    List.generate(18, (_) => Random.secure().nextInt(256)),
  );
  final _ready = Completer<void>();
  final _pending = <String, Completer<Map<String, dynamic>?>>{};
  int _sequence = 0;
  bool _closed = false;
  Future<void> get ready => _ready.future.timeout(const Duration(seconds: 30));

  void receive(String raw) {
    if (_closed || raw.length > 16384) return;
    try {
      final value = jsonDecode(raw);
      if (value is! Map || value['v'] != 2 || value['session'] != session) {
        return;
      }
      final type = value['type'];
      if (type == 'ready' &&
          value['data'] is Map &&
          value['data']['protocol'] == 2) {
        if (!_ready.isCompleted) _ready.complete();
      } else if (type == 'reply') {
        final pending = _pending[value['id']];
        if (pending == null || pending.isCompleted) return;
        final error = value['error'];
        if (error is String) {
          pending.completeError(
            StateError(error.length <= 120 ? error : 'REMOTE_ERROR'),
          );
        } else if (value['data'] == null ||
            value['data'] is Map<String, dynamic>) {
          pending.complete(value['data']);
        }
      } else if ([
        'state',
        'handoff',
        'fullscreen',
        'practice',
      ].contains(type)) {
        onEvent(type as String, value['data']);
      }
    } on FormatException {
      /* Malformed page messages do not complete pending requests. */
    }
  }

  Future<Map<String, dynamic>?> request(String method, [Object? data]) async {
    if (_closed) throw StateError('REMOTE_CLOSED');
    final id = (++_sequence).toString();
    final result = Completer<Map<String, dynamic>?>();
    result.future.ignore();
    _pending[id] = result;
    try {
      await Future.any<void>([
        send(
          jsonEncode({
            'v': 2,
            'session': session,
            'id': id,
            'method': method,
            'data': data,
          }),
        ).timeout(timeout),
        result.future.then<void>((_) {}),
      ]);
      return await result.future.timeout(timeout);
    } finally {
      _pending.remove(id);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (!_ready.isCompleted) _ready.completeError(StateError('REMOTE_CLOSED'));
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('REMOTE_CLOSED'));
      }
    }
    _pending.clear();
  }
}
