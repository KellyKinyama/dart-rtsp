A sample command-line application with an entrypoint in `bin/`, library code
in `lib/`, and example unit test in `test/`.


gstreamer: gst-launch-1.0 -v videotestsrc ! videoconvert ! videoscale ! video/x-raw,width=640,height=480 ! mfh264enc ! rtspclientsink location=rtsp://localhost:8554/test

http://localhost:8889/test/