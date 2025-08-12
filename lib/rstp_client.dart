import 'dart:io';
import 'dart:convert';
import 'dart:async';

// A simple logger for formatted output.
class Logger {
  void info(String message) => print('INFO: $message');
  void error(String message) => stderr.writeln('ERROR: $message');
  void debug(String message) => print('DEBUG: $message');
}

final logger = Logger();

// --- RTSP Protocol Definitions ---

enum RtspMethod { OPTIONS, DESCRIBE, SETUP, PLAY, PAUSE, TEARDOWN, UNKNOWN }

enum RtspScheme { RTSP, RTSPS }

class RtspUrl {
  final RtspScheme scheme;
  final String host;
  final int port;
  final String? path;
  final String? userInfo;

  RtspUrl({
    required this.scheme,
    required this.host,
    required this.port,
    this.path,
    this.userInfo,
  });

  static RtspUrl? parse(String url) {
    try {
      final uri = Uri.parse(url);
      final scheme = uri.scheme.toUpperCase() == 'RTSPS'
          ? RtspScheme.RTSPS
          : RtspScheme.RTSP;
      return RtspUrl(
        scheme: scheme,
        host: uri.host,
        port: uri.port,
        path: uri.path,
        userInfo: uri.userInfo,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  String toString() {
    String auth = userInfo != null && userInfo!.isNotEmpty ? '$userInfo@' : '';
    String p = path ?? '';
    return '${scheme.name.toLowerCase()}://$auth$host:$port$p';
  }
}

abstract class RtspMessage {
  String version = 'RTSP/1.0';
  Map<String, String> headers = {};
  String? body;

  @override
  String toString();
}

class RtspRequest extends RtspMessage {
  final RtspMethod method;
  final RtspUrl uri;
  String? _cseq;

  RtspRequest({
    required this.method,
    required this.uri,
    Map<String, String>? headers,
    String? body,
  }) : super() {
    if (headers != null) {
      this.headers.addAll(headers);
    }
    this.body = body;
  }

  set cseq(String value) {
    _cseq = value;
    headers['CSeq'] = value;
  }

  String? get cseq => _cseq;

  @override
  String toString() {
    final headerLines = headers.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\r\n');
    return '${method.name.toUpperCase()} $uri $version\r\n'
        '$headerLines\r\n'
        '${body ?? ''}';
  }
}

// --- RTSP Response Structure ---

class RtspResponse extends RtspMessage {
  final int statusCode;
  final String statusPhrase;
  String? _cseq;

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

  set cseq(String value) {
    _cseq = value;
    headers['CSeq'] = value;
  }

  String? get cseq => _cseq;

  String? get sessionId => headers['session'];

  List<RtspMethod> get publicMethods {
    final publicHeader = headers['public'];
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
}

// --- RTSP Response Parser ---

class RtspResponseParser {
  static const String _crlf = '\r\n';
  static const String _doubleCrlf = '\r\n\r\n';

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

    final version = statusLineParts[0];
    final statusCode = int.tryParse(statusLineParts[1]);
    final statusPhrase = statusLineParts.sublist(2).join(' ');

    if (statusCode == null || !version.startsWith('RTSP/')) {
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
          logger.debug(
            'Warning: Content-Length mismatch. Expected $contentLength, got ${utf8.encode(responseBody).length}',
          );
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
  RtspUrl? _serverUrl;
  String? _sessionId;
  int _cseqCounter = 1;

  final List<int> _receiveBuffer = [];
  final StreamController<RtspResponse> _responseController =
      StreamController<RtspResponse>.broadcast();

  Stream<RtspResponse> get responses => _responseController.stream;

  Future<void> connect(RtspUrl serverUrl) async {
    _serverUrl = serverUrl;
    try {
      _socket = await Socket.connect(serverUrl.host, serverUrl.port);
      logger.info(
        'Connected to RTSP server (TCP): ${serverUrl.host}:${serverUrl.port}',
      );
      _socket!.listen(
        _handleIncomingData,
        onError: (error) => logger.error('Socket error: $error'),
        onDone: () {
          logger.info('Socket disconnected.');
          _sessionId = null;
        },
      );
    } catch (e) {
      logger.error('Failed to connect: $e');
      rethrow;
    }
  }

  Future<void> sendRequest(RtspRequest request) async {
    if (_socket == null) {
      logger.error('Not connected to an RTSP server.');
      return;
    }

    request.cseq = (_cseqCounter++).toString();
    if (_sessionId != null) {
      request.headers['Session'] = _sessionId!;
    }

    final uriObj = Uri.parse(request.uri.toString());
    if (uriObj.userInfo.isNotEmpty) {
      final auth = base64Encode(utf8.encode(uriObj.userInfo));
      request.headers['Authorization'] = 'Basic $auth';
    }

    final requestString = request.toString();
    logger.debug(
      'Sending RTSP Request (CSeq: ${request.cseq}):\n$requestString',
    );
    _socket!.write(requestString);
  }

  void _handleIncomingData(List<int> data) {
    _receiveBuffer.addAll(data);

    final String bufferString = utf8.decode(
      _receiveBuffer,
      allowMalformed: true,
    );
    final int endOfHeaders = bufferString.indexOf(
      RtspResponseParser._doubleCrlf,
    );

    if (endOfHeaders != -1) {
      int contentLength = 0;
      final headerLines = bufferString
          .substring(0, endOfHeaders)
          .split(RtspResponseParser._crlf);
      for (var line in headerLines) {
        if (line.toLowerCase().startsWith('content-length:')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            contentLength = int.tryParse(parts[1].trim()) ?? 0;
            break;
          }
        }
      }

      final expectedTotalLength =
          endOfHeaders + RtspResponseParser._doubleCrlf.length + contentLength;

      if (_receiveBuffer.length >= expectedTotalLength) {
        final completeMessageBytes = _receiveBuffer.sublist(
          0,
          expectedTotalLength,
        );
        final RtspResponse? response = RtspResponseParser.parse(
          completeMessageBytes,
        );

        if (response != null) {
          logger.info(
            'Received RTSP Response (CSeq: ${response.cseq}): ${response.statusCode} ${response.statusPhrase}',
          );
          _responseController.add(response);
          if (response.sessionId != null) {
            _sessionId = response.sessionId;
          }
        } else {
          logger.error('Failed to parse RTSP response.');
        }

        _receiveBuffer.removeRange(0, expectedTotalLength);

        if (_receiveBuffer.isNotEmpty) {
          _handleIncomingData([]);
        }
      }
    }
  }

  Future<void> disconnect() async {
    if (_socket != null) {
      await _socket!.close();
      _socket = null;
      _sessionId = null;
      _responseController.close();
      logger.info('Disconnected from RTSP server.');
    }
  }
}

// --- Main Example Usage with new client ---

// --- Main Example Usage with new client ---

void main() async {
  final client = RtspClient();
  final rtspUrl = RtspUrl.parse('rtsp://localhost:8554/test')!;

  // Create a completer to handle the SDP data
  final sdpCompleter = Completer<String>();

  // Listen for all responses
  client.responses.listen((response) {
    if (response.statusCode == 200 &&
        response.headers['content-type'] == 'application/sdp' &&
        response.body != null) {
      print(
        '\n--- Parsed SDP Data ---\n${response.body}\n-------------------------\n',
      );
      if (!sdpCompleter.isCompleted) {
        sdpCompleter.complete(response.body);
      }
    }
  });

  try {
    await client.connect(rtspUrl);

    await client.sendRequest(
      RtspRequest(method: RtspMethod.OPTIONS, uri: rtspUrl),
    );
    await client.sendRequest(
      RtspRequest(
        method: RtspMethod.DESCRIBE,
        uri: rtspUrl,
        headers: {'Accept': 'application/sdp'},
      ),
    );

    logger.info('Requesting SDP data...');
    final sdpContent = await sdpCompleter.future;

    // This is the corrected line to build the media control URI.
    final mediaControlUri = RtspUrl.parse('$rtspUrl/trackID=1')!;
    await client.sendRequest(
      RtspRequest(
        method: RtspMethod.SETUP,
        uri: mediaControlUri,
        headers: {'Transport': 'RTP/AVP;unicast;client_port=1234-1235'},
      ),
    );

    await Future.delayed(const Duration(seconds: 1));
    await client.sendRequest(
      RtspRequest(method: RtspMethod.PLAY, uri: mediaControlUri),
    );

    logger.info('Playback started. Press Enter to stop...');
    await stdin.first;

    await client.sendRequest(
      RtspRequest(method: RtspMethod.TEARDOWN, uri: mediaControlUri),
    );
  } catch (e) {
    logger.error('An error occurred during the RTSP session: $e');
  } finally {
    await client.disconnect();
  }
  exit(0);
}
