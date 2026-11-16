import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/import_database.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/cookie_jar.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/download_model.dart';
import 'package:pica_comic/tools/io_extensions.dart';
import 'package:zip_flutter/zip_flutter.dart';

import '../foundation/app.dart';

Future<double> getFolderSize(Directory path) async {
  double total = 0;
  for (var f in path.listSync(recursive: true)) {
    if (FileSystemEntity.typeSync(f.path) == FileSystemEntityType.file) {
      total += File(f.path).lengthSync() / 1024 / 1024;
    }
  }
  return total;
}

Future<bool> exportComic(String id, String name,
    [List<String>? epNames]) async {
  try {
    name = sanitizeFileName(name);
    var data = ExportComicData(
      id,
      downloadManager.path!,
      name,
      epNames,
      downloadManager.getDirectory(id),
    );
    var res = await compute(runningExportComic, data);
    if (!res) {
      return false;
    }

    if (App.isMobile) {
      var params =
          SaveFileDialogParams(sourceFilePath: '${data.path}$pathSep$name.zip');
      await FlutterFileDialog.saveFile(params: params);
    } else {
      final FileSaveLocation? result =
          await getSaveLocation(suggestedName: '$name.zip');

      if (result != null) {
        const String mimeType = 'application/zip';
        final XFile textFile =
            XFile('${data.path}$pathSep$name.zip', mimeType: mimeType);
        await textFile.saveTo(result.path);
      }
    }

    var file = File('${data.path}$pathSep$name.zip');
    file.delete();
    return true;
  } catch (e) {
    return false;
  }
}

Future<bool> exportComics(List<DownloadedItem> comics) async {
  try {
    var exportDatas = <ExportComicData>[];
    for (var comic in comics) {
      var id = comic.id;
      var name = sanitizeFileName(comic.name);
      var path = downloadManager.path;
      var epNames = comic.eps;
      exportDatas.add(ExportComicData(
        id,
        path!,
        name,
        epNames,
        downloadManager.getDirectory(id),
      ));
    }
    await Isolate.run(() => runningExportComics(exportDatas));
    if (App.isMobile) {
      var params = SaveFileDialogParams(
          sourceFilePath: '${downloadManager.path}/comics.zip');
      await FlutterFileDialog.saveFile(params: params);
    } else {
      final FileSaveLocation? result =
          await getSaveLocation(suggestedName: 'comics.zip');

      if (result != null) {
        const String mimeType = 'application/zip';
        final XFile textFile =
            XFile('${downloadManager.path}/comics.zip', mimeType: mimeType);
        await textFile.saveTo(result.path);
      }
    }
    var file = File('${downloadManager.path}/comics.zip');
    if (file.existsSync()) {
      file.delete();
    }
    return true;
  } catch (e) {
    return false;
  }
}

Future<bool> exportPdf(String pdfPath) async {
  try {
    if (App.isMobile) {
      var params = SaveFileDialogParams(sourceFilePath: pdfPath);
      await FlutterFileDialog.saveFile(params: params);
    } else {
      final FileSaveLocation? result = await getSaveLocation(
        suggestedName: File(pdfPath).name,
        acceptedTypeGroups: [const XTypeGroup(label: 'pdf', extensions: ['pdf'])],
      );

      if (result != null) {
        const String mimeType = 'application/pdf';
        final XFile textFile = XFile(pdfPath, mimeType: mimeType);
        await textFile.saveTo(result.path);
      }
    }
    if (File(pdfPath).existsSync()) {
      File(pdfPath).delete();
    }
    return true;
  } catch (e) {
    return false;
  }
}

class ExportComicData {
  String id;
  String path;
  String name;
  String directory;
  List<String>? epNames;

  ExportComicData(this.id, this.path, this.name, this.epNames, this.directory);
}

Future<bool> runningExportComic(ExportComicData data) async {
  final fileName = '${data.path}/${data.name}.zip';
  try {
    final path = Directory("${data.path}/${data.directory}");
    var zipFile = ZipFile.open(fileName);
    String? currentDirName;

    void walk(String path) {
      for (var entry in Directory(path).listSync()) {
        if (entry is Directory) {
          var index = int.parse(entry.name) - 1;
          currentDirName = sanitizeFileName(
              data.epNames?.elementAtOrNull(index) ?? "Chapter ${index + 1}");
          walk(entry.path);
        } else {
          var filePathInZip = sanitizeFileName(data.name);
          if (currentDirName != null) {
            filePathInZip += "/$currentDirName";
          }
          filePathInZip += "/${entry.name}";
          zipFile.addFile(filePathInZip, entry.path);
        }
      }
    }

    walk(path.path);
    zipFile.close();
    return true;
  } catch (e, s) {
    LogManager.addLog(LogLevel.error, "IO", "$e\n$s");
    return false;
  }
}

Future<bool> runningExportComics(List<ExportComicData> datas) async {
  try {
    var result = "${datas.first.path}/comics.zip";
    if (File(result).existsSync()) {
      File(result).deleteSync();
    }
    var zipFile = ZipFile.open(result);
    for (var data in datas) {
      final directory = Directory('${data.path}/${data.directory}');

      String? currentDirName;

      void walk(String path) {
        for (var entry in Directory(path).listSync()) {
          if (entry is Directory) {
            var index = int.parse(entry.name) - 1;
            currentDirName = sanitizeFileName(
                data.epNames?.elementAtOrNull(index) ?? "Chapter ${index + 1}");
            walk(entry.path);
          } else {
            var filePathInZip = sanitizeFileName(data.name);
            if (currentDirName != null) {
              filePathInZip += "/$currentDirName";
            }
            filePathInZip += "/${entry.name}";
            zipFile.addFile(filePathInZip, entry.path);
          }
        }
      }

      walk(directory.path);
    }
    zipFile.close();
    return true;
  } catch (e, s) {
    LogManager.addLog(LogLevel.error, "IO", "$e\n$s");
    return false;
  }
}

Future<void> eraseCache() async {
  return CacheManager().clear();
}

Future<void> copyDirectory(Directory source, Directory destination) async {
  try {
    List<FileSystemEntity> contents = source.listSync();
    for (FileSystemEntity content in contents) {
      String newPath = destination.path +
          Platform.pathSeparator +
          content.path.split(Platform.pathSeparator).last;

      if (content is File) {
        content.copySync(newPath);
      } else if (content is Directory) {
        Directory newDirectory = Directory(newPath);
        newDirectory.createSync();
        copyDirectory(content.absolute, newDirectory.absolute);
      }
    }
  } catch (e, s) {
    LogManager.addLog(LogLevel.error, "IO", "$e\n$s");
    rethrow;
  }
}

/// move all files and directories from source to destination
Future<void> moveDirectory(Directory source, Directory destination) async {
  try {
    source = source.absolute;
    destination = destination.absolute;
    List<FileSystemEntity> contents = source.listSync();
    for (FileSystemEntity content in contents) {
      if (content is File) {
        await content
            .rename(destination.path + Platform.pathSeparator + content.name);
      } else if (content is Directory) {
        Directory newDirectory =
            Directory(destination.path + Platform.pathSeparator + content.name);
        newDirectory.createSync(recursive: true);
        await moveDirectory(content, newDirectory);
      }
    }
    await source.deleteIgnoreError(recursive: true);
  } catch (e, s) {
    LogManager.addLog(LogLevel.error, "IO", "$e\n$s");
    rethrow;
  }
}

///检查下载目录是否可用, 不可用则重置
Future<void> checkDownloadPath() async {
  var path = appdata.settings[22];
  if (path != "") {
    var directory = Directory(path);
    if (!directory.existsSync()) {
      appdata.settings[22] = "";
      appdata.updateSettings();
    }
  }
}

Future<String?> _exportData(String path, String appdataString,
    String? downloadPath, String outPath) async {
  var encode = ZipFile.open(outPath);
  try {
    var filePath = "$path${pathSep}appdata";
    var file = File(filePath);
    if (file.existsSync()) {
      file.deleteSync();
    }
    file.createSync();
    file.writeAsStringSync(appdataString);
    encode.addFile(file.uri.pathSegments.last, file.path);
    var localFavorite = File("$path${pathSep}local_favorite.db");
    var history = File("$path${pathSep}history.db");
    if (!localFavorite.existsSync()) {
      localFavorite.createSync();
    }
    if (!history.existsSync()) {
      history.createSync();
    }
    encode.addFile(
        localFavorite.name, localFavorite.path.replaceAll("\\", "/"));
    encode.addFile(history.name, history.path);
    encode.addFile('cookies.db', "$path/cookies.db");
    await for (var entry in Directory("$path/comic_source").list()) {
      if (entry is File) {
        encode.addFile('comic_source/${entry.name}', entry.path);
      }
    }
    if (downloadPath != null) {
      downloadPath = downloadPath.replaceAll('\\', '/');
      var sourceFolder =
          downloadPath.substring(0, downloadPath.lastIndexOf('/'));
      void walk(String path) {
        for (var entry in Directory(path).listSync()) {
          if (entry is Directory) {
            walk(entry.path);
          } else {
            var filePathInZip = entry.path.replaceFirst(sourceFolder, "");
            if (filePathInZip.startsWith('/') ||
                filePathInZip.startsWith('\\')) {
              filePathInZip = filePathInZip.substring(1);
            }
            encode.addFile(filePathInZip, entry.path);
          }
        }
      }

      walk(downloadPath);
    }
    return null;
  } catch (e) {
    return e.toString();
  } finally {
    encode.close();
  }
}

Future<String> exportDataToFile(bool includeDownload, String outPath) async {
  var path = App.dataPath;
  try {
    var appdataString = const JsonEncoder().convert(appdata.toJson());
    var downloadPath = includeDownload ? DownloadManager().path : null;
    var res = await compute<List<String?>, String?>(
        (message) =>
            _exportData(message[0]!, message[1]!, message[2], message[3]!),
        [path, appdataString, downloadPath, outPath]);

    if (res != null) {
      throw Exception(res);
    }
  } catch (e, s) {
    LogManager.addLog(LogLevel.error, "IO", "$e\n$s");
    rethrow;
  }
  return outPath;
}

Future<bool> runExportData(bool includeDownload) async {
  try {
    var outPath = '${App.cachePath}/userdata.picadata';
    if (App.isDesktop) {
      final FileSaveLocation? result =
          await getSaveLocation(suggestedName: 'userData.picadata');
      if (result == null) {
        return true;
      }
      outPath = result.path;
    }
    if (await File(outPath).exists()) {
      await File(outPath).delete();
    }
    await exportDataToFile(includeDownload, outPath);

    var dialog = showLoadingDialog(
      App.globalContext!,
      barrierDismissible: false,
      allowCancel: false,
    );

    if (App.isMobile) {
      var params = SaveFileDialogParams(sourceFilePath: outPath);
      await FlutterFileDialog.saveFile(params: params);
      File(outPath).delete();
    }

    dialog.close();
  } catch (e, s) {
    LogManager.addLog(LogLevel.error, "IO", "$e\n$s");
    return false;
  }
  return true;
}

/// An explicit path is used by WebDAV and checks the data version.
Future<bool> importData([String? filePath]) async {
  final checkVersion = filePath != null;
  try {
    if (filePath == null) {
      if (App.isMobile) {
        filePath = await FlutterFileDialog.pickFile(
            params: const OpenFileDialogParams());
      } else {
        filePath = (await openFile(acceptedTypeGroups: const [
          XTypeGroup(label: 'data'),
        ]))?.path;
      }
    }
    if (filePath == null) return false;
    return await importDataFromFile(filePath, checkVersion: checkVersion);
  } catch (e, s) {
    Log.error("importData", "$e\n$s");
    return false;
  }
}

bool _importInProgress = false;

/// The manual picker bypasses WebDAV's newer-version check. Keeping the file
/// operation separate also lets device tests use neutral, generated archives.
Future<bool> importDataFromFile(String filePath,
    {bool checkVersion = true}) async {
  if (_importInProgress) return false;
  _importInProgress = true;
  Directory? staging;
  var cookieClosed = false;
  var downloadsClosed = false;
  try {
    final path = App.dataPath;
    staging = await Directory(path).createTemp('data-import-');
    final stagePath = staging.path;
    final data = await Isolate.run(() => _extractImport(filePath, stagePath));
    final json = jsonDecode(data) as Map<String, dynamic>;
    final settings = List<String>.from(json['settings']);
    final fileVersion = int.parse(settings.elementAtOrNull(46) ?? '1');
    if (checkVersion && fileVersion <= int.parse(appdata.settings[46])) {
      return true; // A stale WebDAV export must not overwrite local settings.
    }

    // Do not overwrite files left by an interrupted previous import.
    await LocalFavoritesManager().readData();
    await HistoryManager().tryUpdateDb();
    final hasCookies = File('$stagePath/cookies.db').existsSync();
    final hasDownloads = Directory('$stagePath/download').existsSync();
    final hasSources = Directory('$stagePath/comic_source').existsSync();
    final downloadPath = DownloadManager().path;
    if (hasDownloads && downloadPath == null) {
      throw StateError('Download directory is not initialized');
    }
    if (hasCookies && SingleInstanceCookieJar.instance != null) {
      SingleInstanceCookieJar.instance!.dispose();
      cookieClosed = true;
    }
    if (hasDownloads) {
      DownloadManager().dispose();
      downloadsClosed = true;
    }
    await Isolate.run(() => _installImportFiles(stagePath, path, downloadPath));
    if (cookieClosed) {
      SingleInstanceCookieJar.instance!.init();
      cookieClosed = false;
    }
    if (downloadsClosed) {
      await DownloadManager().init();
      downloadsClosed = false;
    }
    if (hasSources) await ComicSource.reload();
    await LocalFavoritesManager().readData();
    await HistoryManager().tryUpdateDb();
    if (!await appdata.readDataFromJson(json)) return false;
    LocalFavoritesManager().updateUI();
    return true;
  } catch (e, s) {
    Log.error('importData', '$e\n$s');
    return false;
  } finally {
    try {
      if (cookieClosed) SingleInstanceCookieJar.instance?.init();
    } catch (e, s) {
      Log.error('importData.cookies', '$e\n$s');
    }
    try {
      if (downloadsClosed) await DownloadManager().init();
    } catch (e, s) {
      Log.error('importData.downloads', '$e\n$s');
    }
    try {
      if (staging != null && staging.existsSync()) {
        await staging.delete(recursive: true);
      }
    } catch (e, s) {
      Log.error('importData.cleanup', '$e\n$s');
    }
    _importInProgress = false;
  }
}

String _extractImport(String filePath, String staging) {
  final zip = ZipFile.openRead(filePath);
  try {
    for (final entry in zip.getAllEntries()) {
      final name = entry.name.replaceAll('\\', '/');
      if (name.startsWith('/') || name.contains(':') ||
          name.split('/').contains('..')) {
        throw const FormatException('Invalid archive path');
      }
    }
  } finally {
    zip.close();
  }
  ZipFile.openAndExtract(filePath, staging);
  final data = File('$staging/appdata').readAsStringSync();
  final json = jsonDecode(data) as Map<String, dynamic>;
  final settings = List<String>.from(json['settings']);
  if (settings.isEmpty) throw const FormatException('Missing settings');
  int.parse(settings.elementAtOrNull(46) ?? '1');
  List<String>.from(json['firstUse']);
  List<String>.from(json['blockingKeywords'] ?? []);
  List<String>.from(json['favoriteTags'] ?? []);
  if (File('$staging/localFavorite').existsSync()) {
    jsonDecode(File('$staging/localFavorite').readAsStringSync()) as Map;
  } else {
    validateImportDatabase('$staging/local_favorite.db', favorites: true);
  }
  if (File('$staging/history.db').existsSync()) {
    validateImportDatabase('$staging/history.db', favorites: false);
  }
  // Older exports used the original download directory's name.
  for (final item in Directory(staging).listSync()) {
    if (item is Directory && item.name != 'comic_source' &&
        item.name != 'download') {
      item.renameSync('$staging/download');
    }
  }
  return data;
}

Future<void> _installImportFiles(
    String staging, String path, String? downloadPath) async {
  final legacy = File('$staging/localFavorite');
  if (legacy.existsSync()) {
    legacy.copySync('$path/localFavorite');
  } else {
    File('$staging/local_favorite.db').copySync('$path/local_favorite_temp.db');
  }
  final history = File('$staging/history.db');
  if (history.existsSync()) history.copySync('$path/history_temp.db');
  final sources = Directory('$staging/comic_source');
  if (sources.existsSync()) {
    final current = Directory('$path/comic_source');
    if (current.existsSync()) current.deleteSync(recursive: true);
    sources.renameSync(current.path);
  }
  final cookies = File('$staging/cookies.db');
  if (cookies.existsSync()) cookies.copySync('$path/cookies.db');
  final downloads = Directory('$staging/download');
  if (downloads.existsSync()) {
    final current = Directory(downloadPath!);
    if (current.existsSync()) current.deleteSync(recursive: true);
    current.createSync(recursive: true);
    await moveDirectory(downloads, current);
  }
}

void saveLog(String log) async {
  var path = (await getTemporaryDirectory()).path;
  var file = File("$path${pathSep}logs.txt");
  file.writeAsStringSync(log);
  if (App.isMobile) {
    var params =
        SaveFileDialogParams(sourceFilePath: "$path${pathSep}logs.txt");
    await FlutterFileDialog.saveFile(params: params);
  } else {
    final String? directoryPath = await getDirectoryPath();
    if (directoryPath != null) {
      await file.copy("$directoryPath${pathSep}logs.txt");
    }
  }
}

Future<void> exportStringDataAsFile(String data, String fileName) async {
  if (App.isMobile) {
    var cachePath = (await getApplicationCacheDirectory()).path;
    var file = File("$cachePath$pathSep$fileName");
    if (!file.existsSync()) {
      file.createSync();
    }
    file.writeAsStringSync(data);
    var params = SaveFileDialogParams(sourceFilePath: file.path);
    await FlutterFileDialog.saveFile(params: params);
  } else {
    final FileSaveLocation? result =
        await getSaveLocation(suggestedName: fileName);
    if (result == null) {
      return;
    }

    final Uint8List fileData =
        Uint8List.fromList(const Utf8Encoder().convert(data));
    const String mimeType = 'text/plain';
    final XFile textFile =
        XFile.fromData(fileData, mimeType: mimeType, name: fileName);
    await textFile.saveTo(result.path);
  }
}

Future<String?> getDataFromUserSelectedFile(List<String> extensions) async {
  String? filePath;
  if (App.isMobile) {
    var params = const OpenFileDialogParams();
    filePath = await FlutterFileDialog.pickFile(params: params);
  } else {
    XTypeGroup typeGroup = XTypeGroup(
      label: 'data',
      extensions: extensions,
    );
    final XFile? file =
        await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    filePath = file?.path;
  }
  if (filePath == null) {
    return null;
  }
  return File(filePath).readAsStringSync();
}

extension FileExtension on File {
  String get name => uri.pathSegments.last;
}

String bytesLengthToReadableSize(int size) {
  if (size < 1024) {
    return "$size B";
  } else if (size < 1024 * 1024) {
    return "${(size / 1024).toStringAsFixed(2)} KB";
  } else if (size < 1024 * 1024 * 1024) {
    return "${(size / 1024 / 1024).toStringAsFixed(2)} MB";
  } else {
    return "${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB";
  }
}
