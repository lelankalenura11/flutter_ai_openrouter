import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

/// Handles audio recording from the device microphone.
///
/// Uses the [record] package which wraps platform-native audio recording
/// (AudioRecord/MediaCodec on Android, AVFoundation on iOS/macOS, etc.).
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentOutputPath;
  DateTime? _recordStartTime;
  Timer? _durationTimer;

  /// Stream of recording duration updated every 100ms while recording.
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();

  /// Stream of recording duration (updated every 100ms).
  Stream<Duration> get onDurationChanged => _durationController.stream;

  /// Whether a recording is currently in progress (async check).
  Future<bool> get isRecording => _recorder.isRecording();

  /// Request microphone permission from the user.
  ///
  /// [hasPermission] with [request] = true will show the system dialog
  /// if permission hasn't been granted yet.
  Future<bool> requestPermission() async {
    try {
      return await _recorder.hasPermission(request: true);
    } catch (e) {
      debugPrint('Permission request error: $e');
      return false;
    }
  }

  /// Start recording audio to a temporary file.
  ///
  /// Returns the output file path.
  /// Throws if permission was not granted or recording fails to start.
  Future<String> startRecording() async {
    // Ensure we have permission
    final hasPermission = await _recorder.hasPermission(request: true);
    if (!hasPermission) {
      throw Exception('Microphone permission not granted');
    }

    // Stop any existing recording first
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    // Generate output path in app temp directory
    final appDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentOutputPath = '${appDir.path}/recording_$timestamp.m4a';

    // Start recording with AAC-LC encoder for good quality/size balance
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: _currentOutputPath!,
    );

    _recordStartTime = DateTime.now();

    // Emit duration updates every 100ms
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        if (_recordStartTime != null) {
          _durationController.add(
            DateTime.now().difference(_recordStartTime!),
          );
        }
      },
    );

    return _currentOutputPath!;
  }

  /// Stop the current recording.
  ///
  /// Returns the path to the recorded audio file, or null if nothing was recording.
  Future<String?> stopRecording() async {
    _durationTimer?.cancel();
    _durationTimer = null;
    _recordStartTime = null;

    if (!(await _recorder.isRecording())) {
      return _currentOutputPath;
    }

    try {
      final path = await _recorder.stop();
      // If stop() returns a path, use it; otherwise fall back to our stored path
      final resultPath = path ?? _currentOutputPath;
      _currentOutputPath = null;
      return resultPath;
    } catch (e) {
      debugPrint('Stop recording error: $e');
      final fallback = _currentOutputPath;
      _currentOutputPath = null;
      return fallback;
    }
  }

  /// Cancel the current recording and delete the temp file.
  Future<void> cancelRecording() async {
    _durationTimer?.cancel();
    _durationTimer = null;
    _recordStartTime = null;

    if (await _recorder.isRecording()) {
      try {
        await _recorder.cancel();
      } catch (_) {}
    }

    if (_currentOutputPath != null) {
      try {
        final file = File(_currentOutputPath!);
        if (file.existsSync()) {
          await file.delete();
        }
      } catch (_) {}
      _currentOutputPath = null;
    }
  }

  /// Clean up resources.
  void dispose() {
    _durationTimer?.cancel();
    _durationController.close();
    _recorder.dispose();
  }
}