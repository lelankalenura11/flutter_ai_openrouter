import 'package:flutter/services.dart';

class ClipboardService {
  static const platform = MethodChannel('com.example.app/clipboard');

  static Future<Uint8List?> getClipboardImage() async {
    try {
      final result = await platform.invokeMethod<Uint8List>('getClipboardImage');
      return result;
    } on PlatformException {
      return null;
    }
  }
}