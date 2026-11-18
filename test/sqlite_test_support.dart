import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';

/// Optional native library supplied by the test runner; never an app dependency.
void configureTestSqlite() {
  final library = Platform.environment['PICA_TEST_SQLITE3'];
  if (Platform.isWindows && library != null) {
    open.overrideFor(
        OperatingSystem.windows, () => DynamicLibrary.open(library));
  }
}
