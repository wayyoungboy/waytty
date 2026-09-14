import 'dart:convert';

/// Incremental RFC 854 framing, with RFC 1073 NAWS and RFC 1091 TTYPE.
/// Negotiation is reactive, so an acknowledgement cannot create a request loop.
class TelnetCodec {
  TelnetCodec({required this.send, this.terminalType = 'xterm-256color'});

  final void Function(List<int>) send;
  final String terminalType;
  final Set<int> _local = {}, _remote = {};
  final List<int> _sub = [];
  int _state = 0, _verb = 0, _width = 80, _height = 24;
  bool _afterCR = false;

  bool get remoteEcho => _remote.contains(1);

  List<int> receive(List<int> bytes) {
    final output = <int>[];
    for (final byte in bytes) {
      switch (_state) {
        case 0:
          if (byte == 255) {
            _state = 1;
          } else {
            if (!_remote.contains(0) && _afterCR && byte == 0) {
              _afterCR = false;
              continue;
            }
            output.add(byte);
            _afterCR = byte == 13;
          }
        case 1:
          if (byte == 255) {
            output.add(255);
            _state = 0;
          } else if (byte >= 251 && byte <= 254) {
            _verb = byte;
            _state = 2;
          } else if (byte == 250) {
            _sub.clear();
            _state = 3;
          } else {
            _state = 0;
          }
        case 2:
          _negotiate(_verb, byte);
          _state = 0;
        case 3:
          if (byte == 255) {
            _state = 4;
          } else if (_sub.length < 1024) {
            _sub.add(byte);
          }
        case 4:
          if (byte == 240) {
            if (_local.contains(24) &&
                _sub.length == 2 &&
                _sub[0] == 24 &&
                _sub[1] == 1) {
              _subnegotiation(24, [0, ...ascii.encode(terminalType)]);
            }
            _sub.clear();
            _state = 0;
          } else {
            if (byte == 255 && _sub.length < 1024) _sub.add(255);
            _state = 3;
          }
      }
    }
    return output;
  }

  void _negotiate(int verb, int option) {
    if (verb == 253) {
      // DO
      if ({0, 3, 24, 31}.contains(option)) {
        if (_local.add(option)) {
          send([255, 251, option]);
          if (option == 31) resize(_width, _height);
        }
      } else {
        send([255, 252, option]);
      }
    } else if (verb == 254) {
      // DONT
      if (_local.remove(option)) send([255, 252, option]);
    } else if (verb == 251) {
      // WILL
      if ({0, 1, 3}.contains(option)) {
        if (_remote.add(option)) send([255, 253, option]);
      } else {
        send([255, 254, option]);
      }
    } else if (_remote.remove(option)) {
      send([255, 254, option]);
    }
  }

  void resize(int width, int height) {
    _width = width.clamp(1, 65535);
    _height = height.clamp(1, 65535);
    if (_local.contains(31)) {
      _subnegotiation(31, [
        _width >> 8,
        _width & 255,
        _height >> 8,
        _height & 255,
      ]);
    }
  }

  void write(String text) {
    // Terminal Return produces CR. NVT represents a new line as CR LF.
    final nvt = _local.contains(0)
        ? text
        : text
              .replaceAll('\r\n', '\n')
              .replaceAll('\r', '\n')
              .replaceAll('\n', '\r\n');
    send(_escape(utf8.encode(nvt)));
  }

  void _subnegotiation(int option, List<int> data) =>
      send([255, 250, option, ..._escape(data), 255, 240]);

  List<int> _escape(List<int> data) => [
    for (final b in data) ...[b, if (b == 255) 255],
  ];
}
