import 'rtsp_message.dart';
import 'rtsp_session.dart';

void main() {
  final mediaUri = 'rtsp://wowzaec2demo.streamlock.net/vod/mp4:BigBuckBunny_115k.mov';

  // 1. Create a session manager instance
  final session = RtspSession(uri: mediaUri);
  print('Session created for $mediaUri. Initial state: ${session.state}');

  try {
    // 2. SETUP
    final transport = RtspTransportHeader(isUnicast: true, clientPort: '8000-8001');
    final setupRequest = session.setup(transport: transport);
    print('\nSending SETUP request (CSeq ${setupRequest.cSeq})...');

    // Simulate server response
    final setupResponse = RtspResponse(
      statusCode: 200,
      reasonPhrase: 'OK',
      cSeq: setupRequest.cSeq.toString(),
      headers: {
        'Session': 'f8f3d1a2',
        'Transport': 'RTP/AVP;unicast;client_port=8000-8001;server_port=5541-5542',
      },
    );
    session.handleResponse(setupRequest, setupResponse);
    print('SETUP successful! New state: ${session.state}. Session ID: ${session.sessionId}');

    // 3. PLAY
    final playRequest = session.play(range: 'npt=0-');
    print('\nSending PLAY request (CSeq ${playRequest.cSeq})...');
    
    // Simulate server response
    final playResponse = RtspResponse(
      statusCode: 200,
      reasonPhrase: 'OK',
      cSeq: playRequest.cSeq.toString(),
      headers: {'Session': session.sessionId!},
    );
    session.handleResponse(playRequest, playResponse);
    print('PLAY successful! New state: ${session.state}');

    // 4. PAUSE
    final pauseRequest = session.pause();
    print('\nSending PAUSE request (CSeq ${pauseRequest.cSeq})...');
    
    // Simulate server response
    final pauseResponse = RtspResponse(
      statusCode: 200,
      reasonPhrase: 'OK',
      cSeq: pauseRequest.cSeq.toString(),
      headers: {'Session': session.sessionId!},
    );
    session.handleResponse(pauseRequest, pauseResponse);
    print('PAUSE successful! New state: ${session.state}');

    // 5. TEARDOWN
    final teardownRequest = session.teardown();
    print('\nSending TEARDOWN request (CSeq ${teardownRequest.cSeq})...');
    
    // Simulate server response
    final teardownResponse = RtspResponse(
      statusCode: 200,
      reasonPhrase: 'OK',
      cSeq: teardownRequest.cSeq.toString(),
      headers: {'Session': session.sessionId!},
    );
    session.handleResponse(teardownRequest, teardownResponse);
    print('TEARDOWN successful! Final state: ${session.state}');

  } on StateError catch (e) {
    print('State Error: ${e.message}');
  } on RtspException catch (e) {
    print('RTSP Error: $e');
  } catch (e) {
    print('An unexpected error occurred: $e');
  }
}