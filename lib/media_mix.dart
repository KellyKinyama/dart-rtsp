import 'dart:io';
import 'dart:convert';
import 'dart:async';

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

  /// Convenience getter for the Public header (list of supported methods).
  List<RtspMethod> get publicMethods {
    final publicHeader = headers['Public'];
    if (publicHeader == null) return [];
    return publicHeader.split(',').map((m) {
      try {
        return RtspMethod.values.firstWhere(
          (e) => e.name.toUpperCase() == m.trim().toUpperCase(),
          orElse: () => RtspMethod.UNKNOWN,
        );
      } catch (e) {
        return RtspMethod.UNKNOWN;
      }
    }).toList();
  }

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

  RtspSession({required this.sessionId, required this.presentationUri});
}

// --- RTSP Response Parser ---

class RtspResponseParser {
  static const String _crlf = '\r\n';
  static const String _doubleCrlf = '\r\n\r\n';

  /// Parses raw bytes into an RtspResponse object.
  static RtspResponse? parse(List<int> bytes) {
    final rawString = utf8.decode(bytes);

    final parts = rawString.split(_doubleCrlf);
    if (parts.length < 1) {
      return null;
    }

    final headerPart = parts[0];
    final bodyPart = parts.length > 1
        ? parts.sublist(1).join(_doubleCrlf)
        : null;

    final lines = LineSplitter.split(headerPart).toList();
    if (lines.isEmpty) {
      return null;
    }

    final statusLine = lines[0];
    final statusLineParts = statusLine.split(' ');

    if (statusLineParts.length < 3) {
      return null;
    }

    final statusCode = int.tryParse(statusLineParts[1]);
    final statusPhrase = statusLineParts.sublist(2).join(' ');

    if (statusCode == null || !statusLineParts[0].startsWith('RTSP/')) {
      return null;
    }

    final Map<String, String> headers = {};
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i];
      final colonIndex = line.indexOf(':');
      if (colonIndex > 0) {
        final key = line.substring(0, colonIndex).trim();
        final value = line.substring(colonIndex + 1).trim();
        headers[key.toLowerCase()] = value;
      }
    }

    String? responseBody = bodyPart;
    final contentLengthStr = headers['content-length'];
    if (contentLengthStr != null) {
      final contentLength = int.tryParse(contentLengthStr);
      if (contentLength != null && responseBody != null) {
        if (utf8.encode(responseBody).length != contentLength) {
          // This is a simple parser, in a real scenario you would handle partial messages
        }
      }
    }

    final cseq = headers['cseq'];

    return RtspResponse(
      statusCode: statusCode,
      statusPhrase: statusPhrase,
      cseq: cseq,
      headers: headers,
      body: responseBody,
    );
  }
}

// --- Enhanced RtspClient to use the parser ---

class RtspClient {
  Socket? _socket;
  RtspSession? _currentSession;
  final List<int> _receiveBuffer = [];
  final Map<String, Completer<RtspResponse>> _pendingRequests = {};
  int _cseqCounter = 1;

  Future<void> connect(RtspUrl serverUrl) async {
    try {
      if (serverUrl.scheme == RtspScheme.RTSP) {
        _socket = await Socket.connect(serverUrl.host, serverUrl.port);
        print(
          'Connected to RTSP server (TCP): ${serverUrl.host}:${serverUrl.port}',
        );
        _socket!.listen(
          _handleIncomingData,
          onError: (error) => print('Socket error: $error'),
          onDone: () {
            print('Socket disconnected.');
            _currentSession = null;
          },
        );
      } else {
        print('RTSPU (UDP) client not fully implemented in this example.');
      }
    } catch (e) {
      print('Failed to connect: $e');
    }
  }

  Future<RtspResponse> sendRequest(RtspRequest request) async {
    if (_socket == null) {
      throw Exception('Not connected to an RTSP server.');
    }

    request.cseq = (_cseqCounter++).toString();
    if (_currentSession != null && request.method != RtspMethod.SETUP) {
      request.headers['Session'] = _currentSession!.sessionId;
    }

    final completer = Completer<RtspResponse>();
    _pendingRequests[request.cseq!] = completer;

    final requestString = request.toString();
    print(
      '\n--- Sending RTSP Request (CSeq: ${request.cseq}) ---\n$requestString',
    );
    _socket!.write(requestString);

    return completer.future;
  }

  /// Handles incoming data from the socket. It appends the data to a buffer
  /// and then attempts to parse one or more complete RTSP responses from the buffer.
  void _handleIncomingData(List<int> data) {
    print('--> Received raw data chunk: ${data.length} bytes');
    _receiveBuffer.addAll(data);

    // Loop to process any number of complete responses that may have arrived.
    while (true) {
      // Decode the buffer to a string to easily find the header delimiter.
      final bufferString = utf8.decode(_receiveBuffer, allowMalformed: true);
      final doubleCrlfIndex = bufferString.indexOf('\r\n\r\n');

      if (doubleCrlfIndex == -1) {
        // Not a complete message yet, wait for more data.
        print(
          '    <-- Incomplete headers, waiting. Buffer size: ${_receiveBuffer.length}',
        );
        return;
      }

      // We have at least a full header. Now check for the body.
      final headerString = bufferString.substring(0, doubleCrlfIndex);
      int contentLength = 0;
      final headerLines = headerString.split('\r\n');
      for (var line in headerLines) {
        if (line.toLowerCase().startsWith('content-length:')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            contentLength = int.tryParse(parts[1].trim()) ?? 0;
            break;
          }
        }
      }

      final endOfHeaders = doubleCrlfIndex + 4;
      final expectedTotalLength = endOfHeaders + contentLength;

      print(
        '    <-- Found end of headers. Content-Length: $contentLength. Expected total length: $expectedTotalLength. Current buffer size: ${_receiveBuffer.length}',
      );

      if (_receiveBuffer.length >= expectedTotalLength) {
        // We have a complete message.
        final completeMessageBytes = _receiveBuffer.sublist(
          0,
          expectedTotalLength,
        );
        final RtspResponse? response = RtspResponseParser.parse(
          completeMessageBytes,
        );

        if (response != null) {
          print(
            '\n--- Received RTSP Response (CSeq: ${response.cseq}, Status: ${response.statusCode}) ---\n${response.toString()}\n------------------------\n',
          );
          final cseq = response.cseq;
          if (cseq != null && _pendingRequests.containsKey(cseq)) {
            // Found a matching pending request, complete its future.
            _pendingRequests[cseq]!.complete(response);
            _pendingRequests.remove(cseq);
          } else {
            print('Received an unhandled response. CSeq: $cseq');
          }
        } else {
          print('Failed to parse a complete message.');
        }

        // Remove the processed message from the buffer.
        _receiveBuffer.removeRange(0, expectedTotalLength);
      } else {
        // Not enough data for the full message (e.g., body is missing). Wait for more.
        print(
          '    <-- Partial message received. Waiting for the rest of the body.',
        );
        return;
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
  final serverUrl = RtspUrl.parse('rtsp://localhost:8554/test')!;

  try {
    await client.connect(serverUrl);

    if (client._socket != null) {
      // 1. Send OPTIONS request to see what the server supports.
      final optionsResponse = await client.sendRequest(
        RtspRequest(method: RtspMethod.OPTIONS, uri: serverUrl),
      );
      print('Public methods: ${optionsResponse.publicMethods}');

      // 2. Send DESCRIBE request to get the stream's details (SDP).
      final describeResponse = await client.sendRequest(
        RtspRequest(
          method: RtspMethod.DESCRIBE,
          uri: serverUrl,
          headers: {'Accept': 'application/sdp'},
        ),
      );

      // Print the full response for inspection.
      print(
        '\n--- Received Full DESCRIBE Response ---\n${describeResponse.toString()}\n------------------------\n',
      );

      // Specifically print the response body (the SDP data).
      if (describeResponse.body != null) {
        print(
          '\n--- Received SDP Data ---\n${describeResponse.body}\n------------------------\n',
        );
      }
    }
  } catch (e) {
    stderr.writeln('Error: $e');
  } finally {
    await client.disconnect();
  }
}
