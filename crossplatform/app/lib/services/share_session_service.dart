import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import '../models/share_event.dart';

/// Transport contract retained for a future self-hosted sharing service.
/// No realtime transport is enabled in this build.
abstract class ShareTransport {
  Future<void> connect(String code, {required void Function(Map<String, dynamic>) onMessage, void Function(String)? onLeave});
  Future<void> send(Map<String, dynamic> payload);
  Future<void> trackGuest(String guestId);
  Future<void> close();
}

class ShareSessionService {
  static const maxBufferLength = 500 * 1024;
  static const _chunkSize = 80 * 1024;
  static const _pluginId = 'yourssh_share_service';

  final _outputBuffer = StringBuffer();
  int _bufferLength = 0;

  HookBus? _hookBus;
  String? _sessionId;

  /// The SSH session ID currently being shared, or null when not sharing.
  String? get activeSessionId => _sessionId;

  final ShareTransport? _transport;

  Terminal? _guestTerminal;
  final _chunkAccumulator = <int, String>{};
  int _expectedChunks = 0;

  final _events = StreamController<ShareEvent>.broadcast();
  Stream<ShareEvent> get events => _events.stream;

  /// Callback fired when a guest leaves (presence leave). Provides [guestId].
  void Function(String guestId)? onPresenceLeave;

  // ─── Constructor ─────────────────────────────────────

  // ignore: prefer_initializing_formals
  ShareSessionService({ShareTransport? transport}) : _transport = transport;

  /// Named constructor for unit tests — no external dependencies required.
  ShareSessionService.forTest() : _transport = null;

  // ─── Helpers ─────────────────────────────────────────

  static String generateShareCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  void _appendToBuffer(String text) {
    _outputBuffer.write(text);
    _bufferLength += text.length;
    if (_bufferLength > maxBufferLength) {
      final s = _outputBuffer.toString();
      final trimmed = s.substring(s.length - maxBufferLength ~/ 2);
      _outputBuffer.clear();
      _outputBuffer.write(trimmed);
      _bufferLength = trimmed.length;
    }
  }

  // ─── Host API ─────────────────────────────────────────

  Future<String> startSharing(
    String sessionId,
    HookBus hookBus,
  ) async {
    final transport = _transport;
    if (transport == null) throw StateError('Realtime sharing is unavailable in this build.');
    final code = generateShareCode();
    await transport.connect(code, onMessage: _onHostReceived, onLeave: (id) => onPresenceLeave?.call(id));
    _sessionId = sessionId;
    _hookBus = hookBus;
    _outputBuffer.clear();
    _bufferLength = 0;

    hookBus.register('terminal.output', _pluginId, (event) {
      if (event.sessionId == sessionId) {
        _appendToBuffer(event.data);
        _broadcastOutput(event.data);
      }
      return event.data;
    });

    return code;
  }

  void _onHostReceived(Map<String, dynamic> payload) {
    try {
      final event = ShareEvent.fromJson(payload);
      _events.add(event);
    } catch (e) {
      debugPrint('[ShareSessionService] host received unknown event: $e');
    }
  }

  void _broadcastOutput(String text) {
    _transport?.send(ShareEvent.output(text).toJson(),
    );
  }

  Future<void> sendSnapshot(String guestId) async {
    if (_transport == null) return;
    final snapshot = _outputBuffer.toString();
    if (snapshot.length <= _chunkSize) {
      final payload = ShareEvent.snapshot(snapshot).toJson()
        ..['targetGuestId'] = guestId;
      await _transport.send(payload,
      );
    } else {
      final chunks = <String>[];
      for (var i = 0; i < snapshot.length; i += _chunkSize) {
        chunks.add(snapshot.substring(i, (i + _chunkSize).clamp(0, snapshot.length)));
      }
      for (var i = 0; i < chunks.length; i++) {
        final payload = ShareEvent.snapshotChunk(chunks[i], i, chunks.length).toJson()
          ..['targetGuestId'] = guestId;
        await _transport.send(payload,
        );
      }
    }
  }

  Future<void> sendRejected(String guestId, String reason) async {
    await _transport?.send(ShareEvent.rejected(reason).toJson(),
    );
  }

  Future<void> grantControl(String guestId) async {
    await _transport?.send(ShareEvent.controlGrant(guestId).toJson(),
    );
  }

  Future<void> revokeControl() async {
    await _transport?.send(ShareEvent.controlRevoke().toJson(),
    );
  }

  Future<void> stopSharing() async {
    _hookBus?.unregisterAll(_pluginId);
    _hookBus = null;
    _sessionId = null;
    await _transport?.send(ShareEvent.ended().toJson(),
    );
    await _transport?.close();
    _outputBuffer.clear();
    _bufferLength = 0;
  }

  // ─── Guest API ────────────────────────────────────────

  final _guestId = const Uuid().v4();
  String get guestId => _guestId;

  Future<void> joinSession(
    String shareCode,
    Terminal localTerminal,
  ) async {
    final transport = _transport;
    if (transport == null) throw StateError('Realtime sharing is unavailable in this build.');
    await transport.connect(shareCode, onMessage: _onGuestReceived);
    _guestTerminal = localTerminal;
    await transport.trackGuest(_guestId);
    await transport.send(ShareEvent.joinRequest(_guestId).toJson());
  }

  void _onGuestReceived(Map<String, dynamic> payload) {
    ShareEvent event;
    try {
      event = ShareEvent.fromJson(payload);
    } catch (e) {
      debugPrint('[ShareSessionService] guest received unknown event: $e');
      return;
    }

    // For snapshot events, only process if targeted at this guest
    final targetGuestId = payload['targetGuestId'] as String?;
    final isSnapshotEvent = event.type == ShareEventType.snapshot ||
        event.type == ShareEventType.snapshotChunk;
    if (isSnapshotEvent && targetGuestId != null && targetGuestId != _guestId) {
      return; // Not for us
    }

    switch (event.type) {
      case ShareEventType.output:
        if (event.data != null) _guestTerminal?.write(event.data!);
      case ShareEventType.snapshot:
        _chunkAccumulator.clear();
        _expectedChunks = 0;
        if (event.data != null) _guestTerminal?.write(event.data!);
        _events.add(event);
      case ShareEventType.snapshotChunk:
        final index = event.chunkIndex ?? 0;
        final total = event.chunkTotal ?? 1;
        if (total <= 0 || index >= total) break;
        _expectedChunks = total;
        _chunkAccumulator[index] = event.data ?? '';
        if (_chunkAccumulator.length == _expectedChunks) {
          // Verify all expected indices are present before reassembly
          final allPresent = List.generate(_expectedChunks, (i) => _chunkAccumulator.containsKey(i)).every((v) => v);
          if (!allPresent) break;
          final full = List.generate(_expectedChunks, (i) => _chunkAccumulator[i]!).join();
          _guestTerminal?.write(full);
          _chunkAccumulator.clear();
          _events.add(ShareEvent.snapshot(full));
        }
      case ShareEventType.controlGrant:
        _events.add(event);
      case ShareEventType.controlRevoke:
        _events.add(event);
      case ShareEventType.rejected:
        _events.add(event);
      case ShareEventType.ended:
        _events.add(event);
      case ShareEventType.input:
        break;
      case ShareEventType.joinRequest:
        break;
    }
  }

  Future<void> sendGuestInput(String data) async {
    await _transport?.send(ShareEvent.input(data).toJson(),
    );
  }

  Future<void> leaveSession() async {
    await _transport?.close();
    _guestTerminal = null;
    _chunkAccumulator.clear();
  }

  // ─── Test helpers ────────────────────────────────────

  void appendToBufferForTest(String text) => _appendToBuffer(text);
  int get bufferLengthForTest => _bufferLength;
  String get bufferSnapshotForTest => _outputBuffer.toString();

  // ─── Dispose ─────────────────────────────────────────

  Future<void> dispose() async {
    if (_hookBus != null) await stopSharing();
    if (_guestTerminal != null) await leaveSession();
    await _events.close();
  }
}
