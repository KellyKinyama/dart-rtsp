import 'dart:io';
import 'dart:convert';

// --- Core RTSP 2.0 Enums and Constants ---

/// Defines the RTSP 2.0 methods.
enum Rtsp2Method {
  OPTIONS,
  DESCRIBE,
  SETUP,
  PLAY,
  PLAY_NOTIFY, // New method in RTSP 2.0 (server-to-client)
  PAUSE,
  RECORD, // Still present, though not explicitly detailed in intro
  TEARDOWN,
  GET_PARAMETER,
  SET_PARAMETER,
  REDIRECT, // New method in RTSP 2.0 (server-to-client)
  ANNOUNCE, // Still present
  UNKNOWN, // For unsupported or unrecognized methods
}

/// Defines the RTSP 2.0 URL schemes.
enum Rtsp2Scheme {
  RTSP, // Reliable transport (TCP)
  RTSPS, // Secure reliable transport (TLS over TCP)
}

/// Default RTSP port.
const int kDefaultRtspPort = 554;

// --- RTSP 2.0 URL Representation ---

/// Represents an RTSP 2.0 URL.
class Rtsp2Url {
  final Rtsp2Scheme scheme;
  final String host;
  final int port;
  final String path;

  Rtsp2Url({
    required this.scheme,
    required this.host,
    this.port = kDefaultRtspPort,
    this.path = '/',
  });

  /// Parses a string into an Rtsp2Url object.
  static Rtsp2Url? parse(String urlString) {
    RegExp urlPattern =
        RegExp(r'^(rtsp|rtsps)://([^:/]+)(?::(\d+))?(/.*)?$');
    final match = urlPattern.firstMatch(urlString);

    if (match != null) {
      final schemeStr = match.group(1);
      final host = match.group(2)!;
      final portStr = match.group(3);
      final path = match.group(4) ?? '/';

      final scheme = schemeStr == 'rtsp' ? Rtsp2Scheme.RTSP : Rtsp2Scheme.RTSPS;
      final port = portStr != null ? int.tryParse(portStr) ?? kDefaultRtspPort : kDefaultRtspPort;

      return Rtsp2Url(scheme: scheme, host: host, port: port, path: path);
    }
    return null;
  }

  @override
  String toString() {
    final schemeString = scheme == Rtsp2Scheme.RTSP ? 'rtsp' : 'rtsps';
    final portString = port == kDefaultRtspPort ? '' : ':$port';
    return '$schemeString://$host$portString$path';
  }
}

// --- RTSP 2.0 Message Structures ---

/// Base class for RTSP 2.0 messages (Request and Response).
abstract class Rtsp2Message {
  String version = 'RTSP/2.0'; // Updated version
  Map<String, String> headers = {};
  String? body;

  @override
  String toString();
}

/// Represents an RTSP 2.0 Request.
class Rtsp2Request extends Rtsp2Message {
  final Rtsp2Method method;
  final Rtsp2Url uri;
  String? _cseq; // Client Sequence

  Rtsp2Request({
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
    final headerLines = headers.entries.map((e) => '${e.key}: ${e.value}').join('\r\n');
    return '$methodString $uriString $version\r\n'
        '$headerLines\r\n'
        '${body ?? ''}';
  }
}

/// Represents an RTSP 2.0 Response.
class Rtsp2Response extends Rtsp2Message {
  final int statusCode;
  final String statusPhrase;
  String? _cseq; // Client Sequence

  Rtsp2Response({
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

  /// Convenience getter for the Session ID.
  String? get sessionId => headers['session'];

  /// Convenience getter for the Public header (list of supported methods).
  List<Rtsp2Method> get publicMethods {
    final publicHeader = headers['public']; // Headers stored in lowercase
    if (publicHeader == null) return [];
    return publicHeader.split(',').map((m) {
      try {
        return Rtsp2Method.values.firstWhere(
            (e) => e.name.toUpperCase() == m.trim().toUpperCase(),
            orElse: () => Rtsp2Method.UNKNOWN);
      } catch (e) {
        return Rtsp2Method.UNKNOWN;
      }
    }).toList();
  }

  /// Convenience getter for the Media-Properties header.
  String? get mediaProperties => headers['media-properties'];

  /// Convenience getter for the Accept-Ranges header.
  String? get acceptRanges => headers['accept-ranges'];

  /// Convenience getter for the Media-Range header.
  String? get mediaRange => headers['media-range'];

  @override
  String toString() {
    final headerLines = headers.entries.map((e) => '${e.key}: ${e.value}').join('\r\n');
    return '$version $statusCode $statusPhrase\r\n'
        '$headerLines\r\n'
        '${body ?? ''}';
  }
}

// --- RTSP 2.0 Response Parser (Adapted from previous version) ---

class Rtsp2ResponseParser {
  static const String _crlf = '\r\n';
  static const String _doubleCrlf = '\r\n\r\n';

  static Rtsp2Response? parse(List<int> bytes) {
    final rawString = utf8.decode(bytes);

    final parts = rawString.split(_doubleCrlf);
    if (parts.length < 1) return null;

    final headerPart = parts[0];
    final bodyPart = parts.length > 1 ? parts.sublist(1).join(_doubleCrlf) : null;

    final lines = LineSplitter.split(headerPart).toList();
    if (lines.isEmpty) return null;

    // 1. Parse Status Line
    final statusLine = lines[0];
    final statusLineParts = statusLine.split(' ');
    if (statusLineParts.length < 3) return null;

    final version = statusLineParts[0];
    final statusCode = int.tryParse(statusLineParts[1]);
    final statusPhrase = statusLineParts.sublist(2).join(' ');

    if (statusCode == null || !version.startsWith('RTSP/2.0')) { // Check for RTSP/2.0
      print('Warning: Expected RTSP/2.0, got $version');
      return null; // Or handle version negotiation if necessary
    }

    // 2. Parse Headers
    final Map<String, String> headers = {};
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i];
      final colonIndex = line.indexOf(':');
      if (colonIndex > 0) {
        final key = line.substring(0, colonIndex).trim();
        final value = line.substring(colonIndex + 1).trim();
        headers[key.toLowerCase()] = value; // Store keys in lowercase
      }
    }

    // 3. Handle Content Body (similar to previous)
    String? responseBody = bodyPart;
    final contentLengthStr = headers['content-length'];
    if (contentLengthStr != null) {
      final contentLength = int.tryParse(contentLengthStr);
      if (contentLength != null) {
        if (responseBody != null && utf8.encode(responseBody).length != contentLength) {
          print('Warning: Content-Length mismatch. Expected $contentLength, got ${utf8.encode(responseBody).length}');
        }
      }
    }

    final cseq = headers['cseq'];

    return Rtsp2Response(
      statusCode: statusCode,
      statusPhrase: statusPhrase,
      version: version,
      cseq: cseq,
      headers: headers,
      body: responseBody,
    );
  }
}

// --- RTSP 2.0 Session Management (same logic, updated types) ---

/// Represents an active RTSP 2.0 session.
class Rtsp2Session {
  final String sessionId;
  final Rtsp2Url presentationUri; // Changed to Rtsp2Url
  final Map<String, dynamic> resources = {};

  Rtsp2Session({
    required this.sessionId,
    required this.presentationUri,
  });

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

// --- Time Formats (re-use the same structure, apply to RTSP 2.0 context) ---

// (Keep SmptTimeRange, NptTimeRange, UtcTimeRange as they are,
// they are format definitions, not protocol versions themselves)
abstract class RtspTimeRange {
  @override
  String toString();
}

class SmptTimeRange implements RtspTimeRange {
  final String type;
  final String start;
  final String? end;
  SmptTimeRange({required this.type, required this.start, this.end});
  @override
  String toString() => '$type=$start${end != null ? '-$end' : ''}';
}

class NptTimeRange implements RtspTimeRange {
  final String start;
  final String? end;
  NptTimeRange({required this.start, this.end});
  @override
  String toString() => 'npt=$start${end != null ? '-$end' : ''}';
}

class UtcTimeRange implements RtspTimeRange {
  final String start;
  final String? end;
  UtcTimeRange({required this.start, this.end});
  @override
  String toString() => 'clock=$start${end != null ? '-$end' : ''}';
}

// --- RTSP 2.0 Client ---

class Rtsp2Client {
  Socket? _socket;
  TlsCertificate? _serverCertificate; // For RTSPS
  Rtsp2Session? _currentSession;
  int _cseqCounter = 1;

  final List<int> _receiveBuffer = [];

  Future<void> connect(Rtsp2Url serverUrl) async {
    try {
      if (serverUrl.scheme == Rtsp2Scheme.RTSP) {
        _socket = await Socket.connect(serverUrl.host, serverUrl.port);
        print('Connected to RTSP 2.0 server (TCP): ${serverUrl.host}:${serverUrl.port}');
      } else if (serverUrl.scheme == Rtsp2Scheme.RTSPS) {
        // Implement TLS over TCP for RTSPS
        // Requires more advanced TLS setup
        _socket = await SecureSocket.connect(
          serverUrl.host,
          serverUrl.port,
          onBadCertificate: (X509Certificate certificate) {
            // For production, you'd want proper certificate validation.
            // For testing, you might accept self-signed certificates.
            print('Warning: Bad certificate. Accepting for demo.');
            _serverCertificate = certificate;
            return true;
          },
        );
        print('Connected to RTSP 2.0 server (TLS over TCP): ${serverUrl.host}:${serverUrl.port}');
      }

      _socket!.listen(
        _handleIncomingData,
        onError: (error) => print('Socket error: $error'),
        onDone: () {
          print('Socket disconnected.');
          _currentSession = null;
        },
      );
    } catch (e) {
      print('Failed to connect: $e');
    }
  }

  Future<void> sendRequest(Rtsp2Request request) async {
    if (_socket == null) {
      print('Not connected to an RTSP 2.0 server.');
      return;
    }

    request.cseq = (_cseqCounter++).toString();
    // In RTSP 2.0, Session header is primarily for stateful operations
    // after SETUP has established it.
    if (_currentSession != null && request.method != Rtsp2Method.SETUP) {
      request.headers['Session'] = _currentSession!.sessionId;
    }

    final requestString = request.toString();
    print('\n--- Sending RTSP 2.0 Request (CSeq: ${request.cseq}) ---\n$requestString');
    _socket!.write(requestString);
  }

  void _handleIncomingData(List<int> data) {
    _receiveBuffer.addAll(data);

    final String bufferString = utf8.decode(_receiveBuffer, allowError: true);
    final int endOfHeaders = bufferString.indexOf(Rtsp2ResponseParser._doubleCrlf);

    if (endOfHeaders != -1) {
      String fullMessageCandidate = bufferString;
      int contentLength = 0;

      final headerLines = bufferString.substring(0, endOfHeaders).split(Rtsp2ResponseParser._crlf);
      for (var line in headerLines) {
        if (line.toLowerCase().startsWith('content-length:')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            contentLength = int.tryParse(parts[1].trim()) ?? 0;
            break;
          }
        }
      }

      final expectedTotalLength = endOfHeaders + Rtsp2ResponseParser._doubleCrlf.length + contentLength;

      if (_receiveBuffer.length >= expectedTotalLength) {
        final completeMessageBytes = _receiveBuffer.sublist(0, expectedTotalLength);
        final Rtsp2Response? response = Rtsp2ResponseParser.parse(completeMessageBytes);

        if (response != null) {
          print('\n--- Received RTSP 2.0 Response (CSeq: ${response.cseq}) ---');
          print('Status: ${response.statusCode} ${response.statusPhrase}');
          print('Headers: ${response.headers}');
          if (response.body != null && response.body!.isNotEmpty) {
            print('Body:\n${response.body}');
          }

          _processParsedResponse(response);
        } else {
          print('Failed to parse RTSP 2.0 response.');
        }

        _receiveBuffer.removeRange(0, expectedTotalLength);

        if (_receiveBuffer.isNotEmpty) {
          _handleIncomingData([]);
        }
      }
    }
  }

  void _processParsedResponse(Rtsp2Response response) {
    // Logic based on the parsed RTSP 2.0 response
    switch (response.statusCode) {
      case 200: // OK
        // Check for session ID and update _currentSession on successful SETUP
        if (response.cseq == _cseqCounter.toString() && response.headers['session'] != null) {
          // This assumes CSeq increments for each request-response pair
          if (_currentSession == null) {
            _currentSession = Rtsp2Session(
              sessionId: response.headers['session']!,
              presentationUri: Rtsp2Url.parse('rtsp://example.com/dummy')!, // Placeholder
            );
            print('RTSP 2.0 Session Established: ID = ${_currentSession!.sessionId}');
            print('  Media Properties: ${response.mediaProperties}');
            print('  Accept Ranges: ${response.acceptRanges}');
            print('  Media Range: ${response.mediaRange}');
          }
        }

        // Handle specific method responses (using CSeq for clarity, though it's not the primary identifier)
        switch (response.cseq) {
          case '1': // Corresponds to the OPTIONS request
            print('Server Supported Methods (from OPTIONS): ${response.publicMethods}');
            break;
          case '2': // Corresponds to the DESCRIBE request
            if (response.headers['content-type'] == 'application/sdp' && response.body != null) {
              print('Received SDP Presentation Description:\n${response.body}');
              // TODO: Parse SDP using an SDP parser to get stream info and control URIs
            }
            break;
          case '3': // Corresponds to the SETUP request
            if (response.headers['transport'] != null) {
              print('SETUP successful. Transport: ${response.headers['transport']}');
              // Extract negotiated client/server ports for RTP/RTCP here
            }
            break;
          case '4': // Corresponds to the PLAY request
            print('PLAY command acknowledged. Stream should be starting.');
            if (response.mediaRange != null) {
              print('  Current Media Range: ${response.mediaRange}');
            }
            break;
          case '5': // Corresponds to the PAUSE request
            print('PAUSE command acknowledged. Stream should be paused.');
            break;
          case '6': // Corresponds to the TEARDOWN request
            print('TEARDOWN command acknowledged. Session resources freed.');
            _currentSession = null; // Session is terminated
            break;
          // No specific handling for PLAY_NOTIFY or REDIRECT as client doesn't send them
        }
        break;
      case 401: // Unauthorized
        print('Authentication Required. Challenge: ${response.headers['www-authenticate']}');
        // Implement RTSP 2.0 authentication logic (could be different from 1.0)
        break;
      case 404: // Not Found
        print('Error: Resource Not Found.');
        break;
      case 501: // Not Implemented
        print('Error: Server does not implement this method/feature.');
        break;
      default:
        print('Unhandled status code: ${response.statusCode} ${response.statusPhrase}');
        break;
    }
  }

  // Handle incoming server-initiated requests like PLAY_NOTIFY or REDIRECT
  // This would require modifying _handleIncomingData to distinguish requests from responses.
  // For simplicity, this example client only handles responses.
  // A full RTSP 2.0 implementation would have a request parser for the server side,
  // and clients would also implement a basic server to handle these.

  Future<void> disconnect() async {
    if (_socket != null) {
      await _socket!.close();
      _socket = null;
      _currentSession = null;
      print('Disconnected from RTSP 2.0 server.');
    }
  }
}

// --- Main Example Usage (updated for RTSP 2.0) ---

void main() async {
  final client = Rtsp2Client();
  // Example for RTSPS (TLS over TCP)
  // final serverUrl = Rtsp2Url.parse('rtsps://media.example.com:554/twister')!;
  final serverUrl = Rtsp2Url.parse('rtsp://media.example.com:554/twister')!; // Using RTSP for simple demo

  await client.connect(serverUrl);

  if (client._socket != null) {
    // 1. Send OPTIONS request
    await client.sendRequest(Rtsp2Request(
      method: Rtsp2Method.OPTIONS,
      uri: serverUrl,
    ));

    await Future.delayed(Duration(seconds: 1));

    // 2. Send DESCRIBE request
    await client.sendRequest(Rtsp2Request(
      method: Rtsp2Method.DESCRIBE,
      uri: serverUrl,
      headers: {'Accept': 'application/sdp'},
    ));

    await Future.delayed(Duration(seconds: 1));

    // 3. Send SETUP request (for an audio track within the presentation)
    // The URI for the stream would typically come from parsing the SDP response.
    final audioStreamUrl = Rtsp2Url.parse('rtsp://media.example.com:554/twister/audiotrack')!;
    await client.sendRequest(Rtsp2Request(
      method: Rtsp2Method.SETUP,
      uri: audioStreamUrl,
      headers: {'Transport': 'RTP/AVP;unicast;client_port=8000-8001'},
      // No Pipelined-Requests header in this simple demo, but would go here
    ));

    await Future.delayed(Duration(seconds: 1));

    // 4. Send PLAY request
    await client.sendRequest(Rtsp2Request(
      method: Rtsp2Method.PLAY,
      uri: audioStreamUrl,
      headers: {
        'Range': NptTimeRange(start: '0.0').toString(),
        'Scale': '1.5', // Example: Request fast forward
        'Speed': '1.0-2.0', // Example: Request adaptive speed
      },
    ));

    await Future.delayed(Duration(seconds: 5));

    // 5. Send PAUSE request
    await client.sendRequest(Rtsp2Request(
      method: Rtsp2Method.PAUSE,
      uri: audioStreamUrl,
    ));

    await Future.delayed(Duration(seconds: 1));

    // 6. Send TEARDOWN request
    await client.sendRequest(Rtsp2Request(
      method: Rtsp2Method.TEARDOWN,
      uri: audioStreamUrl,
    ));

    await Future.delayed(Duration(seconds: 1));
  }

  await client.disconnect();
}