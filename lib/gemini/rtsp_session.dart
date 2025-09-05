import 'rtsp_message2.dart';

// --- ENUMS AND EXCEPTIONS ---

/// Defines the possible states of an RTSP client session.
enum RtspState {
  init,
  ready,
  playing,
  recording,
  closed,
}

/// A custom exception for handling RTSP error responses.
class RtspException implements Exception {
  final RtspResponse response;
  RtspException(this.response);

  @override
  String toString() {
    return 'RTSP Error: Received status ${response.statusCode} ${response.reasonPhrase} for CSeq ${response.cSeq}';
  }
}

// --- SESSION MANAGEMENT ---

/// Manages the state and lifecycle of a single RTSP session.
class RtspSession {
  final String _uri;
  String? _sessionId;
  int _cSeq = 0;
  RtspState _state = RtspState.init;

  /// The session's base URI.
  String get uri => _uri;

  /// The current session ID, provided by the server after SETUP.
  String? get sessionId => _sessionId;
  
  /// The current state of the session.
  RtspState get state => _state;

  /// Creates a new RTSP session for a given media URI.
  RtspSession({required String uri}) : _uri = uri;

  int get _nextCSeq => ++_cSeq;

  /// Generates a SETUP request. Valid only in `init` or `ready` state.
  RtspRequest setup({required RtspTransportHeader transport}) {
    if (_state != RtspState.init && _state != RtspState.ready) {
      throw StateError('Cannot call SETUP from state $_state.');
    }
    return RtspRequest.setup(
        uri: _uri, cSeq: _nextCSeq, transport: transport, session: _sessionId);
  }

  /// Generates a PLAY request. Valid only in `ready` state.
  RtspRequest play({String? range}) {
    _assertReadyState();
    return RtspRequest.play(
        uri: _uri, cSeq: _nextCSeq, session: _sessionId!, range: range);
  }

  /// Generates a PAUSE request. Valid in `playing` or `recording` state.
  RtspRequest pause() {
    if (state != RtspState.playing && state != RtspState.recording) {
      throw StateError('Cannot call PAUSE from state $_state.');
    }
    _assertSessionId();
    return RtspRequest.pause(uri: _uri, cSeq: _nextCSeq, session: _sessionId!);
  }

  /// Generates a TEARDOWN request to terminate the session.
  RtspRequest teardown() {
    if (state == RtspState.closed) {
      throw StateError('Cannot call TEARDOWN on a closed session.');
    }
    return RtspRequest.teardown(
        uri: _uri, cSeq: _nextCSeq, session: _sessionId ?? '');
  }
  
  /// Generates an OPTIONS request to get server capabilities.
  RtspRequest options() {
    return RtspRequest.options(uri: _uri, cSeq: _nextCSeq);
  }

  /// Processes a server response and updates the session state accordingly.
  void handleResponse(RtspRequest request, RtspResponse response) {
    if (response.cSeq.toString() != request.headers['CSeq']) {
      print('Warning: CSeq mismatch. Ignoring response.');
      return;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RtspException(response);
    }

    switch (request.method) {
      case RtspMethod.SETUP:
        _sessionId = response.session;
        if (_sessionId == null) {
          throw Exception('Server did not return a Session ID on successful SETUP.');
        }
        _state = RtspState.ready;
        break;
      case RtspMethod.PLAY:
        _state = RtspState.playing;
        break;
      case RtspMethod.PAUSE:
        _state = RtspState.ready;
        break;
      case RtspMethod.TEARDOWN:
        _state = RtspState.closed;
        _sessionId = null;
        break;
      default:
        // No state change for methods like OPTIONS, DESCRIBE, etc.
        break;
    }
  }

  void _assertReadyState() {
    if (_state != RtspState.ready) {
      throw StateError('Operation requires state to be "ready", but it is "$_state".');
    }
    _assertSessionId();
  }

  void _assertSessionId() {
    if (_sessionId == null) {
      throw StateError('Operation requires a valid session ID, but none is set.');
    }
  }
}