import 'dart:typed_data';
import 'dart:convert';

// --- ENUMS ---
enum RtspMethod {
  DESCRIBE, ANNOUNCE, GET_PARAMETER, OPTIONS, PAUSE,
  PLAY, RECORD, REDIRECT, SETUP, SET_PARAMETER, TEARDOWN
}

// --- MESSAGE MODELS and PARSER (WITH FIX) ---
// NOTE: All necessary classes are included in this single file for simplicity.

class RtspRequest {
  final RtspMethod method;
  final String uri;
  final Map<String, String> headers;

  RtspRequest(this.method, this.uri, int cSeq, {Map<String, String>? headers})
      : this.headers = headers ?? {} {
    this.headers['CSeq'] = cSeq.toString();
  }

  Uint8List buildMessageBytes() {
    final buffer = StringBuffer();
    buffer.write('${method.name} $uri RTSP/1.0\r\n');
    headers.forEach((key, value) {
      buffer.write('$key: $value\r\n');
    });
    buffer.write('\r\n');
    return utf8.encode(buffer.toString());
  }

  @override
  String toString() => utf8.decode(buildMessageBytes());
}

class RtspResponse {
  final int statusCode;
  final String reasonPhrase;
  final Map<String, String> headers;
  final Uint8List? body;

  int get cSeq => int.parse(headers['CSeq'] ?? '0');

  RtspResponse(this.statusCode, this.reasonPhrase, this.headers, this.body);

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('RTSP/1.0 $statusCode $reasonPhrase\r\n');
    headers.forEach((key, value) {
      buffer.write('$key: $value\r\n');
    });
    buffer.write('\r\n');
    if (body != null) {
      buffer.write(utf8.decode(body!));
    }
    return buffer.toString();
  }
}

class RtspParser {
  static String _normalizeHeaderKey(String key) {
    if (key.isEmpty) return '';
    return key
        .toLowerCase()
        .split('-')
        .map((part) => part.isNotEmpty ? '${part[0].toUpperCase()}${part.substring(1)}' : '')
        .join('-');
  }

  static RtspResponse parse(Uint8List rawData) {
    final separator = [13, 10, 13, 10]; // CRLFCRLF
    int separatorIndex = -1;
    for (int i = 0; i <= rawData.length - separator.length; i++) {
      if (rawData[i] == separator[0] &&
          rawData[i + 1] == separator[1] &&
          rawData[i + 2] == separator[2] &&
          rawData[i + 3] == separator[3]) {
        separatorIndex = i;
        break;
      }
    }

    if (separatorIndex == -1) {
      throw FormatException('Invalid RTSP message: no header/body separator found.');
    }

    final headerPart = utf8.decode(rawData.sublist(0, separatorIndex));
    final lines = headerPart.split('\r\n');
    if (lines.isEmpty) throw FormatException('Invalid RTSP message: empty header.');

    final headers = <String, String>{};
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i];
      final colonIndex = line.indexOf(':');
      if (colonIndex != -1) {
        final key = _normalizeHeaderKey(line.substring(0, colonIndex).trim());
        final value = line.substring(colonIndex + 1).trim();
        
        // ✅ THIS IS THE CRITICAL FIX
        headers.putIfAbsent(key, () => value);
      }
    }

    Uint8List? body;
    final contentLengthStr = headers['Content-Length'];
    if (contentLengthStr != null) {
      final contentLength = int.tryParse(contentLengthStr) ?? 0;
      if (contentLength > 0) {
        final bodyStartIndex = separatorIndex + separator.length;
        if (rawData.length >= bodyStartIndex + contentLength) {
          body = rawData.sublist(bodyStartIndex, bodyStartIndex + contentLength);
        }
      }
    }

    final startLine = lines[0];
    final startLineParts = startLine.split(' ');
    if (startLineParts.length < 3) throw FormatException('Invalid start line: $startLine');

    return RtspResponse(
      int.parse(startLineParts[1]),
      startLineParts.sublist(2).join(' '),
      headers,
      body,
    );
  }
}