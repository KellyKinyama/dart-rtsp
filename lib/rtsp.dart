import 'dart:io';
import 'dart:convert';

// --- Core RTSP Enums and Constants ---

/// Defines the RTSP methods.
enum RtspMethod {
  OPTIONS,
  DESCRIBE,
  SETUP,
  PLAY,
  PAUSE,
  RECORD,
  TEARDOWN,
  GET_PARAMETER,
  SET_PARAMETER,
  REDIRECT,
  ANNOUNCE,
  UNKNOWN, // For unsupported or unrecognized methods
}

/// Defines the RTSP URL schemes.
enum RtspScheme {
  RTSP, // Reliable transport (TCP)
  RTSPU, // Unreliable transport (UDP)
}

/// Default RTSP port.
const int kDefaultRtspPort = 554;

// --- RTSP URL Representation ---

/// Represents an RTSP URL.
class RtspUrl {
  final RtspScheme scheme;
  final String host;
  final int port;
  final String path;

  RtspUrl({
    required this.scheme,
    required this.host,
    this.port = kDefaultRtspPort,
    this.path = '/',
  });

  /// Parses a string into an RtspUrl object.
  static RtspUrl? parse(String urlString) {
    RegExp urlPattern = RegExp(r'^(rtsp|rtspu)://([^:/]+)(?::(\d+))?(/.*)?$');
    final match = urlPattern.firstMatch(urlString);

    if (match != null) {
      final schemeStr = match.group(1);
      final host = match.group(2)!;
      final portStr = match.group(3);
      final path = match.group(4) ?? '/';

      final scheme = schemeStr == 'rtsp' ? RtspScheme.RTSP : RtspScheme.RTSPU;
      final port = portStr != null
          ? int.tryParse(portStr) ?? kDefaultRtspPort
          : kDefaultRtspPort;

      return RtspUrl(scheme: scheme, host: host, port: port, path: path);
    }
    return null;
  }

  @override
  String toString() {
    final schemeString = scheme == RtspScheme.RTSP ? 'rtsp' : 'rtspu';
    final portString = port == kDefaultRtspPort ? '' : ':$port';
    return '$schemeString://$host$portString$path';
  }
}

// --- RTSP Message Structures ---

/// Base class for RTSP messages (Request and Response).
abstract class RtspMessage {
  String version = 'RTSP/1.0';
  Map<String, String> headers = {};
  String? body;

  @override
  String toString();
}

/// Represents an RTSP Request.
class RtspRequest extends RtspMessage {
  final RtspMethod method;
  final RtspUrl uri;
  String? _cseq; // Client Sequence

  RtspRequest({
    required this.method,
    required this.uri,
    String? cseq,
    Map<String, String>? headers,
    String? body,
  }) : super() {
    _cseq = cseq;
    if (headers != null) {
      this.headers.addAll(headers);
    }
    this.body = body;
    if (_cseq != null) {
      this.headers['CSeq'] = _cseq!;
    }
  }

  /// Sets the CSeq header.
  set cseq(String value) {
    _cseq = value;
    headers['CSeq'] = value;
  }

  /// Gets the CSeq header.
  String? get cseq => _cseq;

  @override
  String toString() {
    final methodString = method.name.toUpperCase();
    final uriString = uri.toString();
    final headerLines = headers.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\r\n');
    return '$methodString $uriString $version\r\n'
        '$headerLines\r\n'
        '${body ?? ''}';
  }
}

/// Represents an RTSP Response.
class RtspResponse extends RtspMessage {
  final int statusCode;
  final String statusPhrase;
  String? _cseq; // Client Sequence

  RtspResponse({
    required this.statusCode,
    required this.statusPhrase,
    String? cseq,
    Map<String, String>? headers,
    String? body,
  }) : super() {
    _cseq = cseq;
    if (headers != null) {
      this.headers.addAll(headers);
    }
    this.body = body;
    if (_cseq != null) {
      this.headers['CSeq'] = _cseq!;
    }
  }

  /// Sets the CSeq header.
  set cseq(String value) {
    _cseq = value;
    headers['CSeq'] = value;
  }

  /// Gets the CSeq header.
  String? get cseq => _cseq;

  @override
  String toString() {
    final headerLines = headers.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\r\n');
    return '$version $statusCode $statusPhrase\r\n'
        '$headerLines\r\n'
        '${body ?? ''}';
  }
}

// --- RTSP Session Management ---

/// Represents an active RTSP session.
class RtspSession {
  final String sessionId;
  final RtspUrl presentationUri;
  final Map<String, dynamic> resources =
      {}; // Stores allocated resources for the session

  RtspSession({required this.sessionId, required this.presentationUri});

  void allocateResource(String key, dynamic value) {
    resources[key] = value;
  }

  void freeResource(String key) {
    resources.remove(key);
  }

  void clearResources() {
    resources.clear();
  }
}

// --- Time Formats ---

/// Base class for RTSP time ranges.
abstract class RtspTimeRange {
  @override
  String toString();
}

/// Represents SMPTE relative timestamps.
class SmptTimeRange implements RtspTimeRange {
  final String type; // e.g., "smpte", "smpte-30-drop", "smpte-25"
  final String start; // hours:minutes:seconds:frames.subframes
  final String? end;

  SmptTimeRange({required this.type, required this.start, this.end});

  @override
  String toString() {
    return '$type=$start${end != null ? '-$end' : ''}';
  }
}

/// Represents Normal Play Time (NPT).
class NptTimeRange implements RtspTimeRange {
  final String start; // e.g., "now", "123.45", "12:05:35.3"
  final String? end;

  NptTimeRange({required this.start, this.end});

  @override
  String toString() {
    return 'npt=$start${end != null ? '-$end' : ''}';
  }
}

/// Represents Absolute Time (UTC).
class UtcTimeRange implements RtspTimeRange {
  final String start; // YYYYMMDDTHHMMSS.fractionZ
  final String? end;

  UtcTimeRange({required this.start, this.end});

  @override
  String toString() {
    return 'clock=$start${end != null ? '-$end' : ''}';
  }
}

// --- Example RTSP Client (Simplified) ---

class RtspClient {
  Socket? _socket;
  RtspSession? _currentSession;
  int _cseqCounter = 1;

  Future<void> connect(RtspUrl serverUrl) async {
    try {
      if (serverUrl.scheme == RtspScheme.RTSP) {
        _socket = await Socket.connect(serverUrl.host, serverUrl.port);
        print(
          'Connected to RTSP server (TCP): ${serverUrl.host}:${serverUrl.port}',
        );
        _socket!.listen(
          _handleResponse,
          onError: (error) => print('Socket error: $error'),
          onDone: () => print('Socket disconnected.'),
        );
      } else {
        // UDP connection would require a different approach for receiving responses
        print('RTSPU (UDP) client not fully implemented in this example.');
      }
    } catch (e) {
      print('Failed to connect: $e');
    }
  }

  Future<void> sendRequest(RtspRequest request) async {
    if (_socket == null) {
      print('Not connected to an RTSP server.');
      return;
    }

    request.cseq = (_cseqCounter++).toString();
    if (_currentSession != null) {
      request.headers['Session'] = _currentSession!.sessionId;
    }

    final requestString = request.toString();
    print('\nSending RTSP Request:\n$requestString');
    _socket!.write(requestString);
  }

  void _handleResponse(List<int> data) {
    final responseString = utf8.decode(data);
    print('\nReceived RTSP Response:\n$responseString');
    // TODO: Implement robust RTSP response parsing here
    // For simplicity, we just print the raw response.
    // A real implementation would parse statusCode, headers, etc.
    // and potentially update session state.

    // Example of parsing CSeq from a response (very basic)
    final cseqMatch = RegExp(r'CSeq: (\d+)').firstMatch(responseString);
    if (cseqMatch != null) {
      print('  Response CSeq: ${cseqMatch.group(1)}');
    }

    // Example of parsing Session ID from a response (for SETUP)
    if (responseString.contains('SETUP')) {
      final sessionMatch = RegExp(
        r'Session: ([^;]+)',
      ).firstMatch(responseString);
      if (sessionMatch != null) {
        final sessionId = sessionMatch.group(1)!;
        _currentSession = RtspSession(
          sessionId: sessionId,
          presentationUri: RtspUrl.parse('rtsp://example.com/stream')!,
        ); // Dummy URI
        print('  New Session ID: $sessionId');
      }
    }
  }

  Future<void> disconnect() async {
    if (_socket != null) {
      await _socket!.close();
      _socket = null;
      _currentSession = null;
      print('Disconnected from RTSP server.');
    }
  }
}

// --- Main Example Usage ---

void main() async {
  final client = RtspClient();
  final serverUrl = RtspUrl.parse('rtsp://media.example.com:554/twister')!;

  await client.connect(serverUrl);

  if (client._socket != null) {
    // 1. Send OPTIONS request
    await client.sendRequest(
      RtspRequest(method: RtspMethod.OPTIONS, uri: serverUrl),
    );

    // Simulate a delay for server response
    await Future.delayed(Duration(seconds: 1));

    // 2. Send DESCRIBE request
    await client.sendRequest(
      RtspRequest(
        method: RtspMethod.DESCRIBE,
        uri: serverUrl,
        headers: {
          'Accept': 'application/sdp',
        }, // Request SDP for presentation description
      ),
    );

    // Simulate a delay
    await Future.delayed(Duration(seconds: 1));

    // 3. Send SETUP request (for an audio track within the presentation)
    // In a real scenario, the URI for the stream would come from the DESCRIBE response (SDP).
    final audioStreamUrl = RtspUrl.parse(
      'rtsp://media.example.com:554/twister/audiotrack',
    )!;
    await client.sendRequest(
      RtspRequest(
        method: RtspMethod.SETUP,
        uri: audioStreamUrl,
        headers: {'Transport': 'RTP/AVP;unicast;client_port=8000-8001'},
      ),
    );

    // Simulate a delay
    await Future.delayed(Duration(seconds: 1));

    // 4. Send PLAY request
    await client.sendRequest(
      RtspRequest(
        method: RtspMethod.PLAY,
        uri: audioStreamUrl,
        headers: {
          'Range': NptTimeRange(start: '0.0').toString(),
        }, // Start from beginning
      ),
    );

    // Simulate playback for a few seconds
    await Future.delayed(Duration(seconds: 5));

    // 5. Send PAUSE request
    await client.sendRequest(
      RtspRequest(method: RtspMethod.PAUSE, uri: audioStreamUrl),
    );

    // Simulate a delay
    await Future.delayed(Duration(seconds: 1));

    // 6. Send TEARDOWN request
    await client.sendRequest(
      RtspRequest(method: RtspMethod.TEARDOWN, uri: audioStreamUrl),
    );

    // Simulate a delay
    await Future.delayed(Duration(seconds: 1));
  }

  await client.disconnect();
}
