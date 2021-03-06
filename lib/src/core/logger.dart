import 'package:qiscus_chat_sdk/src/core/core.dart';

enum QLogLevel {
  verbose,
  log,
  debug,
}

class Logger {
  const Logger(this.storage);

  final Storage storage;

  QLogLevel get level => QLogLevel.verbose;

  bool get enabled => storage.debugEnabled;

  void log(String str) {
    if (enabled) print(str);
  }

  void debug(dynamic data) {
    if (enabled) print(data);
  }
}
