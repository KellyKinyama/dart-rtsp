import 'rtsp_message2.dart';
import 'rtsp_session.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

Future<void> main() async {
  final serverHost = 'localhost';
  final serverPort = 8554;
  // ✅ Updated URI to match your GStreamer command
  final mediaUri = 'rtsp://$serverHost:$serverPort/test';

  Socket? socket;
  StreamSubscription? subscription;

  try {
    print('Connecting to $serverHost:$serverPort...');
    socket = await Socket.connect(serverHost, serverPort);
    print('✅ Connected!');

    final session = RtspSession(uri: mediaUri);
    late RtspRequest lastRequest;

    // Listen to the stream of data from the server
    subscription = socket.listen(
      (Uint8List data) {
        try {
          final response = RtspParser.parse(data) as RtspResponse;
          print('\n<<< Received Response:\n$response');
          session.handleResponse(lastRequest, response);
          print('✅ State is now: ${session.state}');

          // --- State Machine Logic ---
          switch (session.state) {
            case RtspState.init:
              final transport = RtspTransportHeader(
                isUnicast: true,
                clientPort: '8000-8001',
              );
              lastRequest = session.setup(transport: transport);
              print('\n>>> Sending SETUP Request:\n$lastRequest');
              socket!.add(lastRequest.buildMessageBytes());
              break;
            case RtspState.ready:
              if (lastRequest.method == RtspMethod.SETUP) {
                lastRequest = session.play();
                print('\n>>> Sending PLAY Request:\n$lastRequest');
                socket!.add(lastRequest.buildMessageBytes());
              } else if (lastRequest.method == RtspMethod.PAUSE) {
                lastRequest = session.teardown();
                print('\n>>> Sending TEARDOWN Request:\n$lastRequest');
                socket!.add(lastRequest.buildMessageBytes());
              }
              break;
            case RtspState.playing:
              // After playing for a bit, let's PAUSE.
              Future.delayed(Duration(seconds: 5), () {
                if (session.state == RtspState.playing) {
                  lastRequest = session.pause();
                  print('\n>>> Sending PAUSE Request:\n$lastRequest');
                  socket!.add(lastRequest.buildMessageBytes());
                }
              });
              break;
            case RtspState.closed:
              print('\nSession closed. Closing connection.');
              socket!.destroy();
              break;
            default:
              break;
          }
        } catch (e) {
          print("Error processing server response: $e");
          socket!.destroy();
        }
      },
      onError: (error) {
        print('Socket Error: $error');
        socket!.destroy();
      },
      onDone: () {
        print('Connection closed by server.');
      },
    );

    // Start the sequence with an OPTIONS request
    lastRequest = session.options();
    print('\n>>> Sending OPTIONS Request:\n$lastRequest');
    socket.add(lastRequest.buildMessageBytes());
  } catch (e) {
    print('Failed to connect or run sequence: $e');
    socket?.destroy();
  }
}
