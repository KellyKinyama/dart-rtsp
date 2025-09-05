import 'dart:typed_data';
import 'dart:convert';

// --- ENUMS ---

/// Enum for RTSP methods for type safety and convenience.
enum RtspMethod {
  DESCRIBE,
  ANNOUNCE,
  GET_PARAMETER,
  OPTIONS,
  PAUSE,
  PLAY,
  RECORD,
  REDIRECT,
  SETUP,
  SET_PARAMETER,
  TEARDOWN,
}

// --- HELPER CLASSES ---

/// Represents a parsed RTSP Transport header.
class RtspTransportHeader {
  final String transportProtocol;
  final String profile;
  final String? lowerTransport;
  final bool isUnicast;
  final String? destination;
  final String? source;
  final int? layers;
  final String? mode;
  final int? ttl;
  final String? clientPort;
  final String? serverPort;
  final String? ssrc;
  final String? interleaved;

  RtspTransportHeader({
    this.transportProtocol = 'RTP',
    this.profile = 'AVP',
    this.lowerTransport = 'UDP',
    this.isUnicast = true,
    this.destination,
    this.source,
    this.layers,
    this.mode,
    this.ttl,
    this.clientPort,
    this.serverPort,
    this.ssrc,
    this.interleaved,
  });

  /// Factory to parse a raw header string into an RtspTransportHeader object.
  factory RtspTransportHeader.parse(String rawHeader) {
    final parts = rawHeader.split(';');
    final spec = parts[0].split('/');

    final params = <String, String>{};
    for (var i = 1; i < parts.length; i++) {
      final p = parts[i].split('=');
      if (p.length == 2) {
        params[p[0].trim()] = p[1].trim();
      } else if (p.length == 1 && p[0].isNotEmpty) {
        // For flags like "unicast"
        params[p[0].trim()] = '';
      }
    }

    return RtspTransportHeader(
      transportProtocol: spec.isNotEmpty ? spec[0] : 'RTP',
      profile: spec.length > 1 ? spec[1] : 'AVP',
      lowerTransport: spec.length > 2 ? spec[2] : 'UDP',
      isUnicast: params.containsKey('unicast'),
      destination: params['destination'],
      source: params['source'],
      layers: params.containsKey('layers')
          ? int.tryParse(params['layers']!)
          : null,
      mode: params['mode']?.replaceAll('"', ''),
      ttl: params.containsKey('ttl') ? int.tryParse(params['ttl']!) : null,
      clientPort: params['client_port'],
      serverPort: params['server_port'],
      ssrc: params['ssrc'],
      interleaved: params['interleaved'],
    );
  }

  /// Builds the string representation of the transport header.
  @override
  String toString() {
    final parts = <String>[
      '$transportProtocol/$profile/${lowerTransport ?? 'UDP'}',
    ];
    parts.add(isUnicast ? 'unicast' : 'multicast');
    if (clientPort != null) parts.add('client_port=$clientPort');
    if (serverPort != null) parts.add('server_port=$serverPort');
    if (destination != null) parts.add('destination=$destination');
    if (source != null) parts.add('source=$source');
    if (ssrc != null) parts.add('ssrc=$ssrc');
    if (mode != null) parts.add('mode="$mode"');
    if (interleaved != null) parts.add('interleaved=$interleaved');
    if (ttl != null) parts.add('ttl=$ttl');
    return parts.join(';');
  }
}

// --- MESSAGE MODELS ---

/// Abstract base class for RTSP messages.
abstract class RtspMessage {
  final String version;
  final Map<String, String> headers;
  final Uint8List? body;

  RtspMessage({
    this.version = 'RTSP/1.0',
    Map<String, String>? headers,
    this.body,
  }) : this.headers = headers ?? {};

  int get cSeq => int.parse(headers['CSeq'] ?? '0');
  String? get session => headers['Session']?.split(';')[0].trim();
  int? get contentLength => headers['Content-Length'] != null
      ? int.parse(headers['Content-Length']!)
      : null;
  String? get contentType => headers['Content-Type'];

  /// Parses the 'Transport' header into a structured object.
  RtspTransportHeader? get transport {
    final rawHeader = headers['Transport'];
    return rawHeader != null ? RtspTransportHeader.parse(rawHeader) : null;
  }

  String? get bodyAsString => body != null ? utf8.decode(body!) : null;

  /// Builds the raw RTSP message as a byte list.
  Uint8List buildMessageBytes();

  @override
  String toString() => utf8.decode(buildMessageBytes());
}

/// Represents an RTSP Request message with specialized builders.
class RtspRequest extends RtspMessage {
  final RtspMethod method;
  final String uri;

  // Private constructor for internal use by factories.
  RtspRequest._({
    required this.method,
    required this.uri,
    required int cSeq,
    String version = 'RTSP/1.0',
    Map<String, String>? headers,
    Uint8List? body,
  }) : super(version: version, headers: headers, body: body) {
    this.headers['CSeq'] = cSeq.toString();
    if (body != null) {
      this.headers['Content-Length'] = body.length.toString();
    }
  }

  // Factory Constructors for each RTSP Method
  factory RtspRequest.options({required String uri, required int cSeq}) {
    return RtspRequest._(method: RtspMethod.OPTIONS, uri: uri, cSeq: cSeq);
  }

  factory RtspRequest.describe({
    required String uri,
    required int cSeq,
    String accept = 'application/sdp',
  }) {
    return RtspRequest._(
      method: RtspMethod.DESCRIBE,
      uri: uri,
      cSeq: cSeq,
      headers: {'Accept': accept},
    );
  }

  factory RtspRequest.setup({
    required String uri,
    required int cSeq,
    required RtspTransportHeader transport,
    String? session,
  }) {
    final headers = {'Transport': transport.toString()};
    if (session != null) headers['Session'] = session;
    return RtspRequest._(
      method: RtspMethod.SETUP,
      uri: uri,
      cSeq: cSeq,
      headers: headers,
    );
  }

  factory RtspRequest.play({
    required String uri,
    required int cSeq,
    required String session,
    String? range,
  }) {
    final headers = {'Session': session};
    if (range != null) headers['Range'] = range;
    return RtspRequest._(
      method: RtspMethod.PLAY,
      uri: uri,
      cSeq: cSeq,
      headers: headers,
    );
  }

  factory RtspRequest.pause({
    required String uri,
    required int cSeq,
    required String session,
  }) {
    return RtspRequest._(
      method: RtspMethod.PAUSE,
      uri: uri,
      cSeq: cSeq,
      headers: {'Session': session},
    );
  }

  factory RtspRequest.teardown({
    required String uri,
    required int cSeq,
    required String session,
  }) {
    return RtspRequest._(
      method: RtspMethod.TEARDOWN,
      uri: uri,
      cSeq: cSeq,
      headers: {'Session': session},
    );
  }

  factory RtspRequest.getParameter({
    required String uri,
    required int cSeq,
    required String session,
    Uint8List? body,
  }) {
    return RtspRequest._(
      method: RtspMethod.GET_PARAMETER,
      uri: uri,
      cSeq: cSeq,
      headers: {'Session': session},
      body: body,
    );
  }

  factory RtspRequest.setParameter({
    required String uri,
    required int cSeq,
    required String session,
    required Uint8List body,
    String contentType = 'text/parameters',
  }) {
    return RtspRequest._(
      method: RtspMethod.SET_PARAMETER,
      uri: uri,
      cSeq: cSeq,
      headers: {'Session': session, 'Content-Type': contentType},
      body: body,
    );
  }

  @override
  Uint8List buildMessageBytes() {
    final buffer = StringBuffer();
    buffer.write('${method.name} $uri $version\r\n');
    headers.forEach((key, value) {
      buffer.write('$key: $value\r\n');
    });
    buffer.write('\r\n');

    final headerBytes = utf8.encode(buffer.toString());

    if (body != null) {
      return Uint8List.fromList([...headerBytes, ...body!]);
    }
    return headerBytes;
  }
}

/// Represents an RTSP Response message from a server.
class RtspResponse extends RtspMessage {
  final int statusCode;
  final String reasonPhrase;

  RtspResponse({
    required this.statusCode,
    required this.reasonPhrase,
    required String cSeq,
    String version = 'RTSP/1.0',
    Map<String, String>? headers,
    Uint8List? body,
  }) : super(version: version, headers: headers, body: body) {
    this.headers['CSeq'] = cSeq;
    if (body != null) {
      this.headers['Content-Length'] = body.length.toString();
    }
  }

  @override
  Uint8List buildMessageBytes() {
    final buffer = StringBuffer();
    buffer.write('$version $statusCode $reasonPhrase\r\n');
    headers.forEach((key, value) {
      buffer.write('$key: $value\r\n');
    });
    buffer.write('\r\n');

    final headerBytes = utf8.encode(buffer.toString());

    if (body != null) {
      return Uint8List.fromList([...headerBytes, ...body!]);
    }
    return headerBytes;
  }
}

// --- PARSER ---

/// A parser for converting raw bytes into RtspMessage objects.
class RtspParser {
  /// Normalizes a header key to Title-Case for consistency.
  static String _normalizeHeaderKey(String key) {
    if (key.isEmpty) return '';
    return key
        .toLowerCase()
        .split('-')
        .map(
          (part) => part.isNotEmpty
              ? '${part[0].toUpperCase()}${part.substring(1)}'
              : '',
        )
        .join('-');
  }

  /// Parses a Uint8List into an RtspRequest or RtspResponse.
  static RtspMessage parse(Uint8List rawData) {
    final separator = [13, 10, 13, 10]; // CRLFCRLF
    int separatorIndex = -1;
    for (int i = 0; i <= rawData.length - separator.length; i++) {
      if (rawData[i] == separator[0] &&
          rawData[i + 1] == separator[1] &&
          rawData[i + 2] == separator[2] &&
          rawData[i + 3] == separator[3]) {
        separatorIndex = i;
        break;
      }
    }

    if (separatorIndex == -1) {
      throw FormatException(
        'Invalid RTSP message: no header/body separator found.',
      );
    }

    final headerPart = utf8.decode(rawData.sublist(0, separatorIndex));
    final lines = headerPart.split('\r\n');
    if (lines.isEmpty)
      throw FormatException('Invalid RTSP message: empty header.');

    final headers = <String, String>{};
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i];
      final colonIndex = line.indexOf(':');
      if (colonIndex != -1) {
        final key = _normalizeHeaderKey(line.substring(0, colonIndex).trim());
        final value = line.substring(colonIndex + 1).trim();

        // The Fix: Only add the header if it doesn't already exist.
        // This makes the first occurrence the definitive one.
        headers.putIfAbsent(key, () => value);
      }
    }

    Uint8List? body;
    final contentLengthStr = headers['Content-Length'];
    if (contentLengthStr != null) {
      final contentLength = int.tryParse(contentLengthStr) ?? 0;
      if (contentLength > 0) {
        final bodyStartIndex = separatorIndex + separator.length;
        if (rawData.length >= bodyStartIndex + contentLength) {
          body = rawData.sublist(
            bodyStartIndex,
            bodyStartIndex + contentLength,
          );
        }
      }
    }

    final startLine = lines[0];
    final startLineParts = startLine.split(' ');
    if (startLineParts.length < 3)
      throw FormatException('Invalid start line: $startLine');

    final cSeq = headers['CSeq'] ?? '0';

    if (startLineParts[0].startsWith('RTSP/')) {
      return RtspResponse(
        version: startLineParts[0],
        statusCode: int.parse(startLineParts[1]),
        reasonPhrase: startLineParts.sublist(2).join(' '),
        cSeq: cSeq,
        headers: headers,
        body: body,
      );
    } else {
      return RtspRequest._(
        method: RtspMethod.values.firstWhere(
          (e) => e.name == startLineParts[0],
        ),
        uri: startLineParts[1],
        version: startLineParts[2],
        cSeq: int.parse(cSeq),
        headers: headers,
        body: body,
      );
    }
  }
}
