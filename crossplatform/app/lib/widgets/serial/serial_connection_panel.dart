import 'dart:async';
import 'package:flutter/material.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import '../../models/serial_models.dart';
import '../../services/serial/platform_serial_backend.dart';
import '../../services/serial/serial_backend.dart';
import '../../services/serial/serial_profile_store.dart';

class SerialConnectionPanel extends StatefulWidget {
  const SerialConnectionPanel({
    super.key,
    this.backend,
    required this.onConnect,
  });
  final SerialBackend? backend;
  final Future<void> Function(SerialDeviceInfo, SerialConfig, SerialBackend)
  onConnect;
  @override
  State<SerialConnectionPanel> createState() => _SerialConnectionPanelState();
}

class _SerialConnectionPanelState extends State<SerialConnectionPanel> {
  late final _backend = widget.backend ?? createSerialBackend();
  final _store = SerialProfileStore();
  final _baud = TextEditingController(text: '115200');
  final _name = TextEditingController();
  List<SerialDeviceInfo> _devices = [];
  List<SerialProfile> _profiles = [];
  String? _deviceId, _profileId;
  String? _errorKey, _errorDetail;
  var _loading = true, _connecting = false, _saving = false;
  var _bits = 8, _stop = 1;
  var _parity = SerialParity.none;
  var _flow = SerialFlowControl.none;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _baud.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _refresh();
    try {
      final profiles = await _store.load();
      if (mounted) setState(() => _profiles = profiles);
    } catch (error) {
      _error('Saved serial profiles are damaged', error);
    }
  }

  void _error(String key, Object error) {
    if (mounted) {
      setState(() {
        _errorKey = key;
        _errorDetail = error.toString();
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _errorKey = null;
      _errorDetail = null;
    });
    try {
      final devices = await _backend.listDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        if (!devices.any((d) => d.id == _deviceId)) {
          _deviceId = devices.firstOrNull?.id;
        }
      });
    } catch (error) {
      _error('Cannot list serial devices', error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  SerialConfig _config() {
    final config = SerialConfig(
      baudRate: int.tryParse(_baud.text.trim()) ?? 0,
      dataBits: _bits,
      stopBits: _stop,
      parity: _parity,
      flowControl: _flow,
    );
    config.validate();
    return config;
  }

  Future<void> _connect() async {
    final device = _devices.where((d) => d.id == _deviceId).firstOrNull;
    if (device == null || _connecting) return;
    setState(() {
      _connecting = true;
      _errorKey = null;
    });
    try {
      await widget.onConnect(device, _config(), _backend);
    } on FormatException catch (error) {
      _error('Invalid serial parameters', error);
    } catch (error) {
      _error(
        error is SerialException ? error.key : 'Cannot open serial port',
        error,
      );
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _save({bool delete = false}) async {
    setState(() => _saving = true);
    try {
      if (delete) {
        await _store.delete(_profileId!);
      } else {
        final profile = SerialProfile(
          id: _profileId,
          name: _name.text.trim(),
          config: _config(),
        );
        await _store.save(profile);
        _profileId = profile.id;
      }
      final profiles = await _store.load();
      if (mounted) {
        setState(() {
          _profiles = profiles;
          if (delete) {
            _profileId = null;
            _name.clear();
          }
          _errorKey = null;
        });
      }
    } catch (error) {
      _error('Cannot save serial profiles', error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, Widget child, {double width = 175}) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LText(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        child,
      ],
    ),
  );
  Widget _choice<T>(
    T value,
    List<T> values,
    String Function(T) label,
    ValueChanged<T> change,
  ) => DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    key: ValueKey('${T.toString()}:$value'),
    decoration: const InputDecoration(
      isDense: true,
      border: OutlineInputBorder(),
    ),
    items: values
        .map((v) => DropdownMenuItem(value: v, child: LText(label(v))))
        .toList(),
    onChanged: _connecting
        ? null
        : (v) {
            if (v != null) setState(() => change(v));
          },
  );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LText(
              'Serial debugger',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const LText(
              'Connect a serial adapter, select its port and configure the connection.',
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(child: LText('Serial device')),
                TextButton.icon(
                  onPressed: _loading || _connecting ? null : _refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const LText('Refresh'),
                ),
              ],
            ),
            if (_loading)
              const LinearProgressIndicator()
            else if (_devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LText(
                  'No serial devices found. Connect an adapter and refresh. Android requires USB OTG.',
                ),
              )
            else
              DropdownButtonFormField<String>(
                key: ValueKey('serial-device:$_deviceId'),
                initialValue: _deviceId,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: _devices
                    .map(
                      (d) => DropdownMenuItem(
                        value: d.id,
                        child: Text(
                          '${d.label} · ${d.path}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _connecting
                    ? null
                    : (value) => setState(() => _deviceId = value),
              ),
            if (_deviceId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(
                  _devices
                          .where((d) => d.id == _deviceId)
                          .firstOrNull
                          ?.description ??
                      '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _field(
                  'Baud rate',
                  TextField(
                    controller: _baud,
                    enabled: !_connecting,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                _field(
                  'Data bits',
                  _choice(_bits, [5, 6, 7, 8], (v) => '$v', (v) => _bits = v),
                ),
                _field(
                  'Parity',
                  _choice(
                    _parity,
                    SerialParity.values,
                    (v) => switch (v) {
                      SerialParity.none => 'None',
                      SerialParity.odd => 'Odd',
                      SerialParity.even => 'Even',
                    },
                    (v) => _parity = v,
                  ),
                ),
                _field(
                  'Stop bits',
                  _choice(_stop, [1, 2], (v) => '$v', (v) => _stop = v),
                ),
                _field(
                  'Flow control',
                  _choice(
                    _flow,
                    SerialFlowControl.values,
                    (v) => switch (v) {
                      SerialFlowControl.none => 'None',
                      SerialFlowControl.rtsCts => 'RTS/CTS',
                      SerialFlowControl.xonXoff => 'XON/XOFF',
                    },
                    (v) => _flow = v,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const LText(
              'Opening a port may change control lines. Unsupported parameters are reported by the driver.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('serial-connect'),
              onPressed: _deviceId == null || _loading || _connecting
                  ? null
                  : _connect,
              icon: const Icon(Icons.cable),
              label: LText(_connecting ? 'Connecting…' : 'Connect serial port'),
            ),
            const Divider(height: 40),
            const LText(
              'Serial profiles',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (_profiles.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _profileId,
                key: ValueKey('profile:$_profileId:${_profiles.length}'),
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr(context, 'Load profile'),
                  border: const OutlineInputBorder(),
                ),
                items: _profiles
                    .map(
                      (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                    )
                    .toList(),
                onChanged: _connecting || _saving
                    ? null
                    : (id) {
                        final profile = _profiles.firstWhere((p) => p.id == id);
                        setState(() {
                          _profileId = id;
                          _name.text = profile.name;
                          _baud.text = '${profile.config.baudRate}';
                          _bits = profile.config.dataBits;
                          _stop = profile.config.stopBits;
                          _parity = profile.config.parity;
                          _flow = profile.config.flowControl;
                        });
                      },
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: tr(context, 'Profile name'),
                border: const OutlineInputBorder(),
              ),
            ),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  onPressed: _saving ? null : () => _save(),
                  child: const LText('Save profile'),
                ),
                TextButton(
                  onPressed: _saving || _profileId == null
                      ? null
                      : () => setState(() {
                          _profileId = null;
                          _name.clear();
                        }),
                  child: const LText('New profile'),
                ),
                if (_profileId != null)
                  TextButton(
                    onPressed: _saving ? null : () => _save(delete: true),
                    child: const LText('Delete profile'),
                  ),
              ],
            ),
            if (_errorKey != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText(
                      _errorKey!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (_errorDetail != null)
                      SelectableText(
                        _errorDetail!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
