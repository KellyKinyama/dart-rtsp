// Dummy SDP Parser (would be a separate class/library)
import 'dart:convert';

class SdpParser {
  static Map<String, dynamic> parseSdp(String sdpContent) {
    final Map<String, dynamic> presentation = {};
    final List<Map<String, dynamic>> mediaStreams = [];

    // Basic line-by-line parsing (simplified)
    List<String> currentMedia = [];
    for (var line in LineSplitter.split(sdpContent)) {
      if (line.startsWith('m=')) {
        if (currentMedia.isNotEmpty) {
          mediaStreams.add(_parseMediaDescription(currentMedia));
        }
        currentMedia = [line];
      } else if (line.isNotEmpty) {
        currentMedia.add(line);
      }
    }
    if (currentMedia.isNotEmpty) {
      mediaStreams.add(_parseMediaDescription(currentMedia));
    }

    // Extract overall presentation attributes (v, o, s, t, a=control)
    // ... (logic to parse overall session attributes)

    presentation['media'] = mediaStreams;
    return presentation;
  }

  static Map<String, dynamic> _parseMediaDescription(List<String> mediaLines) {
    final Map<String, dynamic> media = {};
    for (var line in mediaLines) {
      if (line.startsWith('m=')) {
        final parts = line.substring(2).split(' ');
        media['type'] = parts[0];
        media['port'] = int.tryParse(parts[1]);
        media['protocol'] = parts[2];
        media['formats'] = parts
            .sublist(3)
            .map((f) => int.tryParse(f))
            .whereType<int>()
            .toList();
      } else if (line.startsWith('a=control:')) {
        media['control_uri'] = line.substring(10);
      } else if (line.startsWith('a=rtpmap:')) {
        final parts = line.substring(9).split(' ');
        if (parts.length >= 2) {
          final format = int.tryParse(parts[0]);
          final codecInfo = parts[1].split('/');
          if (format != null && codecInfo.isNotEmpty) {
            media['codec'] = {
              'format': format,
              'name': codecInfo[0],
              'clock_rate': int.tryParse(codecInfo[1] ?? ''),
            };
          }
        }
      }
      // Parse other 'a=' attributes as needed (fmtp, rtcp-fb, etc.)
    }
    return media;
  }
}
