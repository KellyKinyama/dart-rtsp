import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'rtsp_message_fixed.dart'; // We import the new, fixed file

Future<void> main() async {
  final serverHost = 'localhost';
  final serverPort = 8554;
  final mediaUri = 'rtsp://$serverHost:$serverPort/test';

  Socket? socket;

  try {
    print('Connecting to $serverHost:$serverPort...');
    socket = await Socket.connect(serverHost, serverPort);
    print('✅ Connected!');

    final cSeq = 1;
    final optionsRequest = RtspRequest(RtspMethod.OPTIONS, mediaUri, cSeq);
    print('\n>>> Sending Request:\n$optionsRequest');
    socket.add(optionsRequest.buildMessageBytes());

    await for (Uint8List data in socket) {
      print('<<< Received Response:');
      print(utf8.decode(data));

      final response = RtspParser.parse(data);

      print('--- PARSER TEST ---');
      print('Request CSeq was: $cSeq');
      print('Parsed CSeq from response: ${response.cSeq}');

      if (response.cSeq == cSeq) {
        print('✅ Parser Test: SUCCESS!');
      } else {
        print('❌ Parser Test: FAILED!');
      }
      break;
    }
  } catch (e) {
    print('An error occurred: $e');
  } finally {
    print('\nClosing connection.');
    socket?.destroy();
  }
}
