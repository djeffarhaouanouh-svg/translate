import 'dart:io' show Platform;

String defaultTokenApiBase() =>
    Platform.isAndroid ? 'http://10.0.2.2:8787' : 'http://127.0.0.1:8787';
