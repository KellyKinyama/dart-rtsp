import 'rtsp_message.dart';
import 'rtsp_session.dart';

void main() {
  // The media URI we want to control
  final mediaUri = 'rtsp://wowzaec2demo.streamlock.net/vod/mp4:BigBuckBunny_115k.mov';

  // 1. Create a session manager instance
  final session = RtspSession(uri: mediaUri);
  print('Session created for $mediaUri. Initial state: ${session.state}');
  print('------------------------------------');

  try {
    // 2. SETUP
    final transport = RtspTransportHeader(isUnicast: true, clientPort: '8000-8001');
    final setupRequest = session.setup(transport: transport);
    print('>>> Sending SETUP Request:\n$setupRequest');

    // --- Simulate server response for SETUP ---
    final setupResponse = RtspResponse(
      statusCode: 200,
      reasonPhrase: 'OK',
      cSeq: setupRequest.cSeq.toString(),
      headers: {
        'Session': 'f8f3d1a2',
        'Transport': 'RTP/AVP;unicast;client_port=8000-8001;server_port=5541-5542',
      },
    );
    print('<<< Received SETUP Response:\n$setupResponse');
    
    // Process the response
    session.handleResponse(setupRequest, setupResponse);
    print('✅ SETUP successful! New state: ${session.state}. Session ID: ${session.sessionId}');
    print('------------------------------------');


    // 3. PLAY
    final playRequest = session.play(range: 'npt=0-');
    print('>>> Sending PLAY Request:\n$playRequest');
    
    // --- Simulate server response for PLAY ---
    final playResponse = RtspResponse(
      statusCode: 200,
      reasonPhrase: 'OK',
      cSeq: playRequest.cSeq.toString(),
      headers: {'Session': session.sessionId!},
    );
    print('<<< Received PLAY Response:\n$playResponse');

    // Process the response
    session.handleResponse(playRequest, playResponse);
    print('✅ PLAY successful! New state: ${session.state}');
    print('------------------------------------');


    // 4. PAUSE
    final pauseRequest = session.pause();
    print('>>> Sending PAUSE Request:\n$pauseRequest');
    
    // --- Simulate server response for PAUSE ---
    final pauseResponse = RtspResponse(
      statusCode: 200,
      reasonPhrase: 'OK',
      cSeq: pauseRequest.cSeq.toString(),
      headers: {'Session': session.sessionId!},
    );
    print('<<< Received PAUSE Response:\n$pauseResponse');

    // Process the response
    session.handleResponse(pauseRequest, pauseResponse);
    print('✅ PAUSE successful! New state: ${session.state}');
    print('------------------------------------');


    // 5. TEARDOWN
    final teardownRequest = session.teardown();
    print('>>> Sending TEARDOWN Request:\n$teardownRequest');
    
    // --- Simulate server response for TEARDOWN ---
    final teardownResponse = RtspResponse(
      statusCode: 200,
      reasonPhrase: 'OK',
      cSeq: teardownRequest.cSeq.toString(),
      headers: {'Session': session.sessionId!},
    );
    print('<<< Received TEARDOWN Response:\n$teardownResponse');

    // Process the response
    session.handleResponse(teardownRequest, teardownResponse);
    print('✅ TEARDOWN successful! Final state: ${session.state}');
    print('------------------------------------');

  } on StateError catch (e) {
    print('State Error: ${e.message}');
  } on RtspException catch (e) {
    print('RTSP Error: $e');
  } catch (e) {
    print('An unexpected error occurred: $e');
  }
}