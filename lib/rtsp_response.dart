import 'dart:io';
import 'dart:convert';

import 'rtsp.dart';

// (Keep all previous enums and classes: RtspMethod, RtspScheme, RtspUrl,
// RtspMessage, RtspRequest, RtspSession, SmptTimeRange, NptTimeRange, UtcTimeRange)

// --- ENHANCED RTSP Response Structure ---

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

  /// Convenience getter for the Session ID.
  String? get sessionId => headers['Session'];

  /// Convenience getter for the Public header (list of supported methods).
  List<RtspMethod> get publicMethods {
    final publicHeader = headers['Public'];
    if (publicHeader == null) return [];
    return publicHeader.split(',').map((m) {
      try {
        return RtspMethod.values.firstWhere(
            (e) => e.name.toUpperCase() == m.trim().toUpperCase(),
            orElse: () => RtspMethod.UNKNOWN);
      } catch (e) {
        return RtspMethod.UNKNOWN;
      }
    }).toList();
  }

  @override
  String toString() {
    final headerLines = headers.entries.map((e) => '${e.key}: ${e.value}').join('\r\n');
    return '$version $statusCode $statusPhrase\r\n'
        '$headerLines\r\n'
        '${body ?? ''}';
  }
}

// --- RTSP Response Parser ---

class RtspResponseParser {
  static const String _crlf = '\r\n';
  static const String _doubleCrlf = '\r\n\r\n';

  /// Parses raw bytes into an RtspResponse object.
  /// This method assumes the full response message is available in the buffer.
  /// In a real-world scenario, you might need a streaming parser
  /// that can handle partial messages.
  static RtspResponse? parse(List<int> bytes) {
    final rawString = utf8.decode(bytes);

    final parts = rawString.split(_doubleCrlf);
    if (parts.length < 1) {
      print('Invalid RTSP response format: No header-body separator.');
      return null;
    }

    final headerPart = parts[0];
    final bodyPart = parts.length > 1 ? parts.sublist(1).join(_doubleCrlf) : null;

    final lines = LineSplitter.split(headerPart).toList();
    if (lines.isEmpty) {
      print('Invalid RTSP response format: Empty header part.');
      return null;
    }

    // 1. Parse Status Line
    final statusLine = lines[0];
    final statusLineParts = statusLine.split(' ');
    if (statusLineParts.length < 3) {
      print('Invalid RTSP status line: $statusLine');
      return null;
    }

    final version = statusLineParts[0];
    final statusCode = int.tryParse(statusLineParts[1]);
    final statusPhrase = statusLineParts.sublist(2).join(' ');

    if (statusCode == null || !version.startsWith('RTSP/')) {
      print('Invalid RTSP status line: $statusLine');
      return null;
    }

    // 2. Parse Headers
    final Map<String, String> headers = {};
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i];
      final colonIndex = line.indexOf(':');
      if (colonIndex > 0) {
        final key = line.substring(0, colonIndex).trim();
        final value = line.substring(colonIndex + 1).trim();
        // RTSP headers are case-insensitive, store them normalized
        headers[key.toLowerCase()] = value;
      }
    }

    // 3. Handle Content Body
    String? responseBody = bodyPart;
    // Check Content-Length to ensure body is complete or correct
    final contentLengthStr = headers['content-length'];
    if (contentLengthStr != null) {
      final contentLength = int.tryParse(contentLengthStr);
      if (contentLength != null) {
        if (responseBody != null && utf8.encode(responseBody).length != contentLength) {
          print('Warning: Content-Length mismatch. Expected $contentLength, got ${utf8.encode(responseBody).length}');
          // In a real streaming parser, you would wait for more data here
        }
      }
    }

    // Attempt to get CSeq from headers (case-insensitive)
    final cseq = headers['cseq'];

    return RtspResponse(
      statusCode: statusCode,
      statusPhrase: statusPhrase,
      version: version,
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
  int _cseqCounter = 1;

  // Buffer for incoming data, as responses might not arrive in single packets
  final List<int> _receiveBuffer = [];

  Future<void> connect(RtspUrl serverUrl) async {
    try {
      if (serverUrl.scheme == RtspScheme.RTSP) {
        _socket = await Socket.connect(serverUrl.host, serverUrl.port);
        print('Connected to RTSP server (TCP): ${serverUrl.host}:${serverUrl.port}');
        _socket!.listen(
          _handleIncomingData, // Change to new handler
          onError: (error) => print('Socket error: $error'),
          onDone: () {
            print('Socket disconnected.');
            _currentSession = null; // Clear session on disconnect
          },
        );
      } else {
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
    if (_currentSession != null && request.method != RtspMethod.SETUP) {
      // Session header is typically only returned by server after SETUP
      // and then sent by client for subsequent stateful requests.
      request.headers['Session'] = _currentSession!.sessionId;
    }

    final requestString = request.toString();
    print('\n--- Sending RTSP Request (CSeq: ${request.cseq}) ---\n$requestString');
    _socket!.write(requestString);
  }

  void _handleIncomingData(List<int> data) {
    _receiveBuffer.addAll(data);

    // Look for the end of the message (double CRLF)
    final String bufferString = utf8.decode(_receiveBuffer, allowError: true);
    final int endOfHeaders = bufferString.indexOf(RtspResponseParser._doubleCrlf);

    if (endOfHeaders != -1) {
      // Potentially complete message, or at least headers are received
      String fullMessageCandidate = bufferString;
      int contentLength = 0;

      // Extract Content-Length if present to determine full message size
      final headerLines = bufferString.substring(0, endOfHeaders).split(RtspResponseParser._crlf);
      for (var line in headerLines) {
        if (line.toLowerCase().startsWith('content-length:')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            contentLength = int.tryParse(parts[1].trim()) ?? 0;
            break;
          }
        }
      }

      // Calculate total expected message length
      final expectedTotalLength = endOfHeaders + RtspResponseParser._doubleCrlf.length + contentLength;

      if (_receiveBuffer.length >= expectedTotalLength) {
        // We have received the full message (headers + body)
        final completeMessageBytes = _receiveBuffer.sublist(0, expectedTotalLength);
        final RtspResponse? response = RtspResponseParser.parse(completeMessageBytes);

        if (response != null) {
          print('\n--- Received RTSP Response (CSeq: ${response.cseq}) ---');
          print('Status: ${response.statusCode} ${response.statusPhrase}');
          print('Headers: ${response.headers}');
          if (response.body != null && response.body!.isNotEmpty) {
            print('Body:\n${response.body}');
          }

          // Process the parsed response
          _processParsedResponse(response);
        } else {
          print('Failed to parse RTSP response.');
        }

        // Remove the parsed message from the buffer
        _receiveBuffer.removeRange(0, expectedTotalLength);

        // Check if there's more data in the buffer for the next message
        if (_receiveBuffer.isNotEmpty) {
          _handleIncomingData([]); // Process remaining data recursively
        }
      }
    }
    // If not enough data, wait for more.
  }

  void _processParsedResponse(RtspResponse response) {
    // Logic based on the parsed response
    switch (response.statusCode) {
      case 200: // OK
        if (response.cseq == _cseqCounter.toString() && response.headers['session'] != null) {
          // This is a new session established by SETUP
          if (_currentSession == null && response.headers['session'] != null) {
            _currentSession = RtspSession(
              sessionId: response.headers['session']!,
              presentationUri: RtspUrl.parse('rtsp://example.com/dummy')!, // Placeholder
            );
            print('RTSP Session Established: ID = ${_currentSession!.sessionId}');
          } else if (_currentSession != null && response.sessionId != _currentSession!.sessionId) {
            print('Warning: Session ID changed from server. Old: ${_currentSession!.sessionId}, New: ${response.sessionId}');
            // Handle session ID change if applicable
            _currentSession = RtspSession(
              sessionId: response.headers['session']!,
              presentationUri: RtspUrl.parse('rtsp://example.com/dummy')!, // Placeholder
            );
          }
        }

        // Handle specific method responses
        switch (response.headers['cseq']) {
          case '1': // Corresponds to the OPTIONS request
            print('Server Supported Methods (from OPTIONS): ${response.publicMethods}');
            break;
          case '2': // Corresponds to the DESCRIBE request
            if (response.headers['content-type'] == 'application/sdp' && response.body != null) {
              print('Received SDP Presentation Description:\n${response.body}');
              // TODO: Parse SDP to extract stream information (e.g., media types,
              // control URIs for individual streams, RTP port suggestions).
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
            break;
          case '5': // Corresponds to the PAUSE request
            print('PAUSE command acknowledged. Stream should be paused.');
            break;
          case '6': // Corresponds to the TEARDOWN request
            print('TEARDOWN command acknowledged. Session resources freed.');
            _currentSession = null; // Session is terminated
            break;
        }
        break;
      case 401: // Unauthorized
        print('Authentication Required. Challenge: ${response.headers['www-authenticate']}');
        // Implement authentication logic (e.g., Digest authentication)
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

  Future<void> disconnect() async {
    if (_socket != null) {
      await _socket!.close();
      _socket = null;
      _currentSession = null;
      print('Disconnected from RTSP server.');
    }
  }
}

// --- Main Example Usage (same as before, just uses the enhanced client) ---

void main() async {
  final client = RtspClient();
  final serverUrl = RtspUrl.parse('rtsp://media.example.com:554/twister')!;

  await client.connect(serverUrl);

  if (client._socket != null) {
    // 1. Send OPTIONS request
    await client.sendRequest(RtspRequest(
      method: RtspMethod.OPTIONS,
      uri: serverUrl,
    ));

    // Simulate a delay for server response
    await Future.delayed(Duration(seconds: 1));

    // 2. Send DESCRIBE request
    await client.sendRequest(RtspRequest(
      method: RtspMethod.DESCRIBE,
      uri: serverUrl,
      headers: {'Accept': 'application/sdp'},
    ));

    // Simulate a delay
    await Future.delayed(Duration(seconds: 1));

    // 3. Send SETUP request (for an audio track within the presentation)
    // In a real scenario, the URI for the stream would come from the DESCRIBE response (SDP).
    final audioStreamUrl = RtspUrl.parse('rtsp://media.example.com:554/twister/audiotrack')!;
    await client.sendRequest(RtspRequest(
      method: RtspMethod.SETUP,
      uri: audioStreamUrl,
      headers: {'Transport': 'RTP/AVP;unicast;client_port=8000-8001'},
    ));

    // Simulate a delay
    await Future.delayed(Duration(seconds: 1));

    // 4. Send PLAY request
    await client.sendRequest(RtspRequest(
      method: RtspMethod.PLAY,
      uri: audioStreamUrl,
      headers: {'Range': NptTimeRange(start: '0.0').toString()},
    ));

    // Simulate playback for a few seconds
    await Future.delayed(Duration(seconds: 5));

    // 5. Send PAUSE request
    await client.sendRequest(RtspRequest(
      method: RtspMethod.PAUSE,
      uri: audioStreamUrl,
    ));

    // Simulate a delay
    await Future.delayed(Duration(seconds: 1));

    // 6. Send TEARDOWN request
    await client.sendRequest(RtspRequest(
      method: RtspMethod.TEARDOWN,
      uri: audioStreamUrl,
    ));

    // Simulate a delay
    await Future.delayed(Duration(seconds: 1));
  }

  await client.disconnect();
}