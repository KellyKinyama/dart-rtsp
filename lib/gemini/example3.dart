import 'dart:io';
import 'dart:typed_data';
import 'rtsp_message.dart'; // Your existing RTSP library
import 'rtsp_session.dart';

Future<void> main() async {
  // Replace with a real RTSP server address and port
  final serverHost = 'localhost';
  final serverPort = 8554; // Default RTSP port
  // final mediaUri = 'rtsp://$serverHost/vod/mp4:BigBuckBunny_115k.mov';
  final mediaUri = 'rtsp://$serverHost';

  Socket? socket;

  try {
    // 1. Establish a TCP connection to the RTSP server
    print('Connecting to $serverHost:$serverPort...');
    socket = await Socket.connect(serverHost, serverPort);
    print('✅ Connected!');

    // 2. Create an RTSP session
    final session = RtspSession(uri: mediaUri);

    // 3. Send an OPTIONS request to start
    final optionsRequest = session.options();
    print('\n>>> Sending OPTIONS Request:\n$optionsRequest');
    socket.add(optionsRequest.buildMessageBytes());

    // 4. Listen for the server's response
    await for (Uint8List data in socket) {
      final response = RtspParser.parse(data) as RtspResponse;
      print('<<< Received OPTIONS Response:\n$response');

      // Now that you have a real response, you can handle it
      session.handleResponse(optionsRequest, response);

      // In a real client, you would continue the sequence here (SETUP, PLAY, etc.)
      // For this example, we'll just break the loop.
      break;
    }
  } catch (e) {
    print('An error occurred: $e');
  } finally {
    // 5. Clean up the connection
    print('\nClosing the connection.');
    socket?.destroy();
  }
}
