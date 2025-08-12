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

// Manages the state and communication for a single RTSP session.
class RtspSession {
  late Socket _socket;
  int _cseq = 0;
  String? _sessionId;
  late String _rtspUrl;

  final Completer<String> _sdpCompleter = Completer<String>();

  RtspSession(String rtspUrl) {
    _rtspUrl = rtspUrl;
    logger.info('Initializing RTSP session for $_rtspUrl');
  }

  Future<void> connect() async {
    final uri = Uri.parse(_rtspUrl);
    try {
      _socket = await Socket.connect(uri.host, uri.port);
      logger.info('Connected to ${uri.host}:${uri.port}');
      _listenForResponse();
    } catch (e) {
      logger.error('Connection failed: $e');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (_sessionId != null) {
      await teardown();
    }
    _socket.close();
    logger.info('Disconnected from server.');
  }

  void _listenForResponse() {
    _socket.listen(
      (data) {
        final response = utf8.decode(data);
        // Print the raw response from the server.
        print(
          '\n--- Raw Server Response ---\n$response\n-------------------------\n',
        );
        _parseResponse(response);
      },
      onError: (error) => logger.error('Socket error: $error'),
      onDone: () => logger.info('Socket connection closed by server.'),
      cancelOnError: true,
    );
  }

  void _parseResponse(String response) {
    if (_sessionId == null) {
      final sessionMatch = RegExp(r'Session: (\S+)').firstMatch(response);
      if (sessionMatch != null) {
        _sessionId = sessionMatch.group(1);
        logger.info('Extracted Session ID: $_sessionId');
      }
    }

    if (response.contains('Content-Type: application/sdp')) {
      final sdpBody = response
          .substring(response.indexOf('\r\n\r\n') + 4)
          .trim();
      if (!_sdpCompleter.isCompleted) {
        _sdpCompleter.complete(sdpBody);
      }
    }
  }

  Future<void> _sendRequest(
    String method, {
    String? uri,
    Map<String, String>? headers,
  }) async {
    _cseq++;
    final request = StringBuffer('$method ${uri ?? _rtspUrl} RTSP/1.0\r\n');
    request.writeln('CSeq: $_cseq');

    final uriObj = Uri.parse(_rtspUrl);
    if (uriObj.userInfo.isNotEmpty) {
      final auth = base64Encode(utf8.encode(uriObj.userInfo));
      request.writeln('Authorization: Basic $auth');
    }

    if (_sessionId != null) {
      request.writeln('Session: $_sessionId');
    }

    if (headers != null) {
      headers.forEach((key, value) {
        request.writeln('$key: $value');
      });
    }
    request.writeln('\r\n');

    logger.debug('Sending request:\n${request.toString()}');
    _socket.write(request.toString());
  }

  Future<void> options() async {
    await _sendRequest('OPTIONS');
  }

  Future<String> describe() async {
    await _sendRequest('DESCRIBE', headers: {'Accept': 'application/sdp'});
    return _sdpCompleter.future;
  }

  Future<void> setup(String mediaUri, String transport) async {
    await _sendRequest(
      'SETUP',
      uri: mediaUri,
      headers: {'Transport': transport},
    );
  }

  Future<void> play(String range) async {
    await _sendRequest('PLAY', headers: {'Range': range});
  }

  Future<void> teardown() async {
    await _sendRequest('TEARDOWN');
  }
}

// Main function to execute the RTSP client logic.
void main(List<String> args) async {
  final rtspUrl =
      'rtsp://807e9439d5ca.entrypoint.cloud.wowza.com:1935/app-rC94792j/068b9c9a_stream2';
  final session = RtspSession(rtspUrl);

  try {
    await session.connect();
    await Future.delayed(const Duration(seconds: 1));

    await session.options();
    await Future.delayed(const Duration(seconds: 1));

    logger.info('Requesting SDP data...');
    final sdpContent = await session.describe();
    print(
      '\n--- Parsed SDP Data ---\n$sdpContent\n-------------------------\n',
    );

    final uri = Uri.parse(rtspUrl);
    final mediaControlUri = 'rtsp://${uri.host}:${uri.port}/trackID=1';

    await session.setup(
      mediaControlUri,
      'RTP/AVP;unicast;client_port=1234-1235',
    );
    await Future.delayed(const Duration(seconds: 1));

    await session.play('npt=0-');
    logger.info('Playback started. Press Enter to stop...');
    await stdin.first;

    await session.disconnect();
  } catch (e) {
    logger.error('An error occurred during the RTSP session: $e');
  }
  exit(0);
}
