import 'dart:io';

import 'package:flutter/services.dart';

/// Serves only bundled fixtures on this phone, never arbitrary filesystem paths.
class AssetServer {
  AssetServer._(this._server, this._assets);
  final HttpServer _server;
  final Map<String, Uint8List> _assets;
  Uri get origin => Uri.parse('http://127.0.0.1:${_server.port}');
  Uri media(String quality) => origin.resolve('/media/demo-$quality.mp4');
  static const files = {
    '/h5/index.html': 'text/html; charset=utf-8',
    '/h5/app.js': 'text/javascript',
    '/h5/bridge.js': 'text/javascript',
    '/h5/style.css': 'text/css',
    '/h5/captions.vtt': 'text/vtt',
    '/media/demo-720.mp4': 'video/mp4',
    '/media/demo-360.mp4': 'video/mp4',
  };
  static Future<AssetServer> start({
    Future<Uint8List> Function(String)? load,
  }) async {
    final assets = <String, Uint8List>{};
    // shortcut: preload only these small demo files; use CDN URLs for real catalogs.
    for (final path in files.keys) {
      if (load != null) {
        assets[path] = await load('assets$path');
      } else {
        final data = await rootBundle.load('assets$path');
        assets[path] = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      }
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = AssetServer._(server, assets);
    server.listen(instance._serve);
    return instance;
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      if (!['GET', 'HEAD'].contains(request.method)) {
        response.statusCode = 405;
        response.headers.set('Allow', 'GET, HEAD');
        return;
      }
      final bytes = _assets[request.uri.path];
      if (bytes == null) {
        response.statusCode = 404;
        return;
      }
      response.headers.set('Content-Type', files[request.uri.path]!);
      response.headers.set('Accept-Ranges', 'bytes');
      response.headers.set('Cache-Control', 'no-store');
      response.headers.set('X-Content-Type-Options', 'nosniff');
      int start = 0, end = bytes.length - 1;
      final range = request.headers.value('range');
      if (range != null) {
        final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
        if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
          response.statusCode = 416;
        } else if (match[1]!.isEmpty) {
          final suffix = int.tryParse(match[2]!);
          if (suffix == null || suffix <= 0) {
            response.statusCode = 416;
          } else {
            start = (bytes.length - suffix).clamp(0, bytes.length);
          }
        } else {
          start = int.tryParse(match[1]!) ?? bytes.length;
          if (match[2]!.isNotEmpty) {
            end = (int.tryParse(match[2]!) ?? -1).clamp(-1, end);
          }
          if (start > end || start >= bytes.length) response.statusCode = 416;
        }
        if (response.statusCode == 416) {
          response.headers.set('Content-Range', 'bytes */${bytes.length}');
          return;
        }
        response.statusCode = 206;
        response.headers.set(
          'Content-Range',
          'bytes $start-$end/${bytes.length}',
        );
      }
      response.contentLength = end - start + 1;
      if (request.method == 'GET') {
        response.add(Uint8List.sublistView(bytes, start, end + 1));
      }
    } on IOException {
      // A disposed player may close a range request early.
    } finally {
      try {
        await response.close();
      } on IOException {
        /* Client disconnected. */
      }
    }
  }

  Future<void> close() => _server.close(force: true);
}
