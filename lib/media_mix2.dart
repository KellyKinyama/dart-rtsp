import 'dart:io';
import 'dart:convert';
import 'dart:async';

void main() async {
  // Define the RTSP server details.
  // We use localhost since the server is running on the same machine.
  // The port is 8554, as shown in your MediaMTX log.
  const String host = 'localhost';
  const int port = 8554;
  const String streamPath =
      '/test'; // The path of the stream you are publishing.

  Socket? socket;
  int cseqCounter = 1;

  try {
    // Step 1: Establish a TCP connection to the RTSP server.
    print('Attempting to connect to $host:$port...');
    socket = await Socket.connect(host, port);
    print('Connected successfully!');

    // Use a completer to wait for a response for a specific CSeq.
    final completer = Completer<String>();

    // Step 2: Listen for the server's responses and process them.
    socket.listen(
      (data) {
        final String response = utf8.decode(data);
        print(
          '\n--- Received RTSP Response ---\n$response\n----------------------------\n',
        );

        // Check if the response matches the expected CSeq and is a success.
        if (response.contains('CSeq: $cseqCounter') &&
            response.contains('RTSP/1.0 200 OK')) {
          completer.complete(response);
        } else {
          completer.completeError('Unexpected or erroneous response.');
        }
      },
      onError: (e) => completer.completeError('Socket error: $e'),
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
            'Socket closed before response was received.',
          );
        }
      },
    );

    // Step 3: Send the OPTIONS request.
    final optionsRequest =
        'OPTIONS rtsp://$host:$port$streamPath RTSP/1.0\r\n'
        'CSeq: ${cseqCounter++}\r\n\r\n';
    print('Sending RTSP OPTIONS request...');
    socket.write(optionsRequest);

    // Wait for the OPTIONS response.
    await completer.future;

    // Reset the completer for the next request.
    final describeCompleter = Completer<String>();

    // Reset the socket listener for the new completer.
    socket.listen(
      (data) {
        final String response = utf8.decode(data);
        print(
          '\n--- Received RTSP Response ---\n$response\n----------------------------\n',
        );

        // Check if the response matches the expected CSeq and is a success.
        if (response.contains('CSeq: $cseqCounter') &&
            response.contains('RTSP/1.0 200 OK')) {
          // Check if the response has a content body (the SDP).
          final bodyStart = response.indexOf('\r\n\r\n');
          if (bodyStart != -1) {
            final sdpBody = response.substring(bodyStart + 4);
            describeCompleter.complete(sdpBody);
          } else {
            describeCompleter.completeError(
              'No SDP data in DESCRIBE response.',
            );
          }
        } else {
          describeCompleter.completeError('Unexpected or erroneous response.');
        }
      },
      onError: (e) => describeCompleter.completeError('Socket error: $e'),
      onDone: () {
        if (!describeCompleter.isCompleted) {
          describeCompleter.completeError(
            'Socket closed before response was received.',
          );
        }
      },
    );

    // Step 4: Send the DESCRIBE request.
    final describeRequest =
        'DESCRIBE rtsp://$host:$port$streamPath RTSP/1.0\r\n'
        'CSeq: ${cseqCounter++}\r\n'
        'Accept: application/sdp\r\n\r\n';
    print('Sending RTSP DESCRIBE request...');
    socket.write(describeRequest);

    // Wait for the DESCRIBE response and get the SDP data.
    final sdpData = await describeCompleter.future;
    print('\n--- Received SDP Data ---\n$sdpData\n------------------------\n');
  } catch (e) {
    // Handle any errors that occur during the connection or communication.
    stderr.writeln('Error: $e');
  } finally {
    // Step 5: Close the connection cleanly.
    if (socket != null) {
      // await socket.close();
      print('Connection closed.');
    }
  }
}
