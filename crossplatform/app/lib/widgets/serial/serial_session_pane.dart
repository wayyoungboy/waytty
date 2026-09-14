import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import '../../models/serial_models.dart';
import '../../models/serial_session.dart';

class SerialSessionPane extends StatefulWidget {
  const SerialSessionPane({super.key, required this.session});
  final SerialSession session;
  @override
  State<SerialSessionPane> createState() => _SerialSessionPaneState();
}

class _SerialSessionPaneState extends State<SerialSessionPane>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _interval = TextEditingController(text: '1000');
  final _scroll = ScrollController();
  final _history = <String>[];
  bool _hex = false,
      _sendHex = false,
      _log = false,
      _paused = false,
      _autoScroll = true;
  bool _dtr = false, _rts = false, _signalBusy = false, _fileSending = false;
  SerialNewline _newline = SerialNewline.none;
  String _snapshot = '';
  String? _error, _detail;
  Timer? _repeat;
  bool _repeating = false;
  int _sendGeneration = 0, _fileProgress = 0;
  SerialSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant SerialSessionPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != s) {
      oldWidget.session.removeListener(_changed);
      _stop();
      _input.clear();
      _snapshot = '';
      _paused = false;
      _dtr = false;
      _rts = false;
      _error = null;
      s.addListener(_changed);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stop();
    }
  }

  void _changed() {
    if (!mounted) return;
    if (!s.connected) _stop();
    setState(() {});
    if (_autoScroll && !_paused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.removeListener(_changed);
    _stop();
    _input.dispose();
    _interval.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _stop() {
    s.cancelSend();
    _sendGeneration++;
    _repeat?.cancel();
    _repeat = null;
    _repeating = false;
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() {
      _error = error is SerialException
          ? error.key
          : error is FormatException
          ? 'Invalid HEX input'
          : 'Serial operation failed';
      _detail = error is SerialException ? error.detail : error.toString();
    });
  }

  Future<void> _send() async {
    try {
      final bytes = encodeSerialInput(
        _input.text,
        hex: _sendHex,
        newline: _newline,
      );
      if (bytes.isEmpty) return;
      await s.send(bytes);
      if (mounted) {
        setState(() {
          _error = null;
          if (_input.text.isNotEmpty) {
            _history.remove(_input.text);
            _history.insert(0, _input.text);
            if (_history.length > 30) _history.removeLast();
          }
        });
      }
    } catch (error) {
      _stop();
      _showError(error);
    }
  }

  void _startRepeat() {
    final interval = int.tryParse(_interval.text);
    if (interval == null || interval < 100 || interval > 3600000) {
      _showError(
        const SerialException('Repeat interval must be 100–3600000 ms'),
      );
      return;
    }
    try {
      // Freeze the bytes when starting; edits require Stop and Start again.
      final bytes = encodeSerialInput(
        _input.text,
        hex: _sendHex,
        newline: _newline,
      );
      if (bytes.isEmpty) return;
      final generation = ++_sendGeneration;
      setState(() => _repeating = true);
      Future<void> tick() async {
        if (!mounted || generation != _sendGeneration || !s.connected) return;
        try {
          await s.send(bytes);
        } catch (error) {
          _stop();
          _showError(error);
          return;
        }
        if (mounted && generation == _sendGeneration && s.connected) {
          _repeat = Timer(Duration(milliseconds: interval), tick);
        }
      }

      unawaited(tick());
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _sendFile() async {
    final generation = ++_sendGeneration;
    final session = s;
    setState(() {
      _fileSending = true;
      _fileProgress = 0;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(withReadStream: true);
      if (!mounted ||
          generation != _sendGeneration ||
          !session.connected ||
          picked == null) {
        return;
      }
      final file = picked.files.single;
      if (file.size > 16 * 1024 * 1024) {
        throw const SerialException('Serial file exceeds 16 MiB');
      }
      final stream =
          file.readStream ??
          (file.path == null ? null : File(file.path!).openRead());
      if (stream == null) {
        throw const SerialException('Cannot read selected file');
      }
      await for (final chunk in stream) {
        for (var offset = 0; offset < chunk.length; offset += 256) {
          if (!mounted || generation != _sendGeneration || !session.connected) {
            return;
          }
          final bytes = Uint8List.fromList(
            chunk.sublist(offset, (offset + 256).clamp(0, chunk.length)),
          );
          await session.send(bytes);
          if (mounted) setState(() => _fileProgress += bytes.length);
        }
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _fileSending = false);
    }
  }

  Future<void> _export(bool raw) async {
    try {
      final bytes = raw
          ? s.rawReceived
          : Uint8List.fromList(
              utf8.encode(
                s.records
                    .map(
                      (r) => jsonEncode({
                        'time': r.time.toIso8601String(),
                        'direction': r.transmitted ? 'TX' : 'RX',
                        'hex': serialHex(r.bytes),
                      }),
                    )
                    .join('\n'),
              ),
            );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: tr(context, 'Export serial capture'),
        fileName: raw ? 'serial-rx.bin' : 'serial-log.jsonl',
        bytes: bytes,
      );
      if (path != null && !Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes);
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _signal(SerialSignal signal, bool enabled) async {
    final session = s;
    setState(() => _signalBusy = true);
    try {
      await session.setSignal(signal, enabled);
      if (signal == SerialSignal.breakSignal) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (session.connected) await session.setSignal(signal, false);
      } else if (mounted && session == s) {
        setState(() {
          if (signal == SerialSignal.dtr) {
            _dtr = enabled;
          } else {
            _rts = enabled;
          }
        });
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _signalBusy = false);
    }
  }

  String _display() {
    if (_log) {
      return s.records.reversed
          .take(256)
          .toList()
          .reversed
          .map(
            (r) =>
                '${r.time.toIso8601String()} ${r.transmitted ? 'TX' : 'RX'}  ${serialHex(r.bytes)}',
          )
          .join('\n');
    }
    final bytes = s.rawReceived;
    final visible = bytes.length > 65536
        ? Uint8List.sublistView(bytes, bytes.length - 65536)
        : bytes;
    return _hex
        ? serialHex(visible)
        : utf8.decode(visible, allowMalformed: true);
  }

  @override
  Widget build(BuildContext context) {
    final active = s.connected;
    final busy = s.sending || _fileSending || _repeating;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.cable, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.device.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${s.device.path} · ${s.config.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              LText(switch (s.status) {
                SerialStatus.idle => 'Ready',
                SerialStatus.connecting => 'Connecting…',
                SerialStatus.connected => 'Connected',
                SerialStatus.disconnected => 'Disconnected',
                SerialStatus.error => 'Error',
                SerialStatus.closed => 'Closed',
              }),
              IconButton(
                tooltip: tr(context, 'Disconnect'),
                onPressed: active || s.status == SerialStatus.connecting
                    ? () {
                        _stop();
                        unawaited(s.close());
                      }
                    : null,
                icon: const Icon(Icons.link_off),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('HEX'),
                selected: _hex,
                onSelected: (v) => setState(() => _hex = v),
              ),
              FilterChip(
                label: const LText('TX/RX log'),
                selected: _log,
                onSelected: (v) => setState(() => _log = v),
              ),
              FilterChip(
                key: const ValueKey('serial-pause'),
                label: LText(_paused ? 'Resume display' : 'Pause display'),
                selected: _paused,
                onSelected: (v) => setState(() {
                  if (v) _snapshot = _display();
                  _paused = v;
                }),
              ),
              FilterChip(
                label: const LText('Auto scroll'),
                selected: _autoScroll,
                onSelected: (v) => setState(() => _autoScroll = v),
              ),
              IconButton(
                tooltip: tr(context, 'Clear display'),
                onPressed: () {
                  s.clearCapture();
                  setState(() => _snapshot = '');
                },
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
              PopupMenuButton<bool>(
                tooltip: tr(context, 'Export serial capture'),
                onSelected: _export,
                icon: const Icon(Icons.save_alt),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: true,
                    child: LText('Export raw RX bytes'),
                  ),
                  PopupMenuItem(value: false, child: LText('Export TX/RX log')),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: LText(
            LMessage('RX {0} B · TX {1} B · discarded {2} B', [
              s.receivedBytes,
              s.sentBytes,
              s.discardedBytes,
            ]),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            color: const Color(0xFF101412),
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  _paused ? _snapshot : _display(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Color(0xFFD7E2DA),
                  ),
                ),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: LText(
            'Display: latest 64 KiB / 256 log entries. Export includes the retained capture.',
            style: TextStyle(fontSize: 10),
          ),
        ),
        if (_error != null || s.errorKey != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Tooltip(
              message: _detail ?? s.errorDetail ?? '',
              child: LText(
                _error ?? s.errorKey!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('serial-send-input'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 3,
                      enabled: !busy,
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        hintText: tr(
                          context,
                          _sendHex
                              ? 'HEX bytes, e.g. 00 FF 41'
                              : 'Text to send',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('serial-send'),
                    onPressed: active && !busy ? _send : null,
                    child: const LText('Send'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    key: const ValueKey('serial-send-hex'),
                    label: const LText('Send HEX'),
                    selected: _sendHex,
                    onSelected: busy
                        ? null
                        : (v) => setState(() => _sendHex = v),
                  ),
                  DropdownButton<SerialNewline>(
                    value: _newline,
                    items: SerialNewline.values
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: LText(
                              v == SerialNewline.none
                                  ? 'No newline'
                                  : v.name.toUpperCase(),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: busy
                        ? null
                        : (v) => setState(() => _newline = v!),
                  ),
                  PopupMenuButton<String>(
                    tooltip: tr(context, 'Send history'),
                    enabled: _history.isNotEmpty && !busy,
                    icon: const Icon(Icons.history),
                    onSelected: (v) => _input.text = v,
                    itemBuilder: (_) => _history
                        .map(
                          (v) => PopupMenuItem(
                            value: v,
                            child: SizedBox(
                              width: 220,
                              child: Text(
                                v,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  OutlinedButton(
                    onPressed: active && !busy ? _sendFile : null,
                    child: const LText('Send file'),
                  ),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _interval,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        suffixText: 'ms',
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: active && !busy ? _startRepeat : null,
                    child: const LText('Repeat send'),
                  ),
                  if (_repeating || _fileSending)
                    TextButton(
                      onPressed: () => setState(_stop),
                      child: const LText('Stop sending'),
                    ),
                  if (_fileSending) Text('$_fileProgress B'),
                  FilterChip(
                    label: const Text('DTR'),
                    selected: _dtr,
                    onSelected: active && !_signalBusy
                        ? (v) => _signal(SerialSignal.dtr, v)
                        : null,
                  ),
                  FilterChip(
                    label: const Text('RTS'),
                    selected: _rts,
                    onSelected:
                        active &&
                            !_signalBusy &&
                            s.config.flowControl != SerialFlowControl.rtsCts
                        ? (v) => _signal(SerialSignal.rts, v)
                        : null,
                  ),
                  OutlinedButton(
                    onPressed: active && !_signalBusy
                        ? () => _signal(SerialSignal.breakSignal, true)
                        : null,
                    child: const LText('BREAK 200 ms'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
